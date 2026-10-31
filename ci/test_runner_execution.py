#!/usr/bin/env python3
"""Synthetic-only unit tests. Passing these does NOT establish guest execution."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest

SCRIPT = Path(__file__).with_name("verify_runner_execution.py")
spec = importlib.util.spec_from_file_location("verify_runner_execution", SCRIPT)
gate = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(gate)
HEAD = "a" * 40
RUN_ID = 8001


def good(profile="wire"):
    cfg = gate.PROFILES[profile]
    steps = [{"name": name, "number": i, "status": "completed",
              "conclusion": "success"}
             for i, name in enumerate(cfg["steps"], 1)]
    run = {
        "id": RUN_ID, "workflow_id": cfg["workflow_id"],
        "head_sha": HEAD, "event": "pull_request",
        "repository": {"id": gate.SOURCE_REPO_ID},
        "head_repository": {"id": gate.SOURCE_REPO_ID},
        "status": "completed", "conclusion": "success", "run_attempt": 1,
    }
    job = {
        "id": 123, "name": cfg["job"], "run_id": RUN_ID, "head_sha": HEAD,
        "run_attempt": 1, "status": "completed", "conclusion": "success",
        "runner_id": 41, "runner_name": "isolated-jdk25-1",
        "labels": ["self-hosted", "linux", "x64", "oreslang-jdk25"],
        "steps": steps,
    }
    return run, {"jobs": [job]}


class AdmissionEvidence(unittest.TestCase):
    def verify(self, run, jobs, profile="wire"):
        return gate.check_execution(run, jobs, profile=profile,
                                    expected_head=HEAD, expected_run_id=RUN_ID)

    def test_synthetic_wire_metadata(self):
        run, jobs = good()
        record = self.verify(run, jobs)
        self.assertEqual(record["scope"], "workflow-step-execution-only")

    def test_synthetic_native_metadata(self):
        run, jobs = good("native")
        self.assertEqual(self.verify(run, jobs, "native")["steps"], 5)

    def test_no_jobs(self):
        run, jobs = good()
        jobs["jobs"] = []
        with self.assertRaises(gate.Unexecuted):
            self.verify(run, jobs)

    def test_queued_never_passes(self):
        run, jobs = good()
        run.update(status="queued", conclusion=None)
        with self.assertRaises(gate.Unexecuted):
            self.verify(run, jobs)

    def test_cancelled_never_passes(self):
        run, jobs = good()
        run.update(status="completed", conclusion="cancelled")
        with self.assertRaises(gate.Unexecuted):
            self.verify(run, jobs)

    def test_zero_step_job(self):
        run, jobs = good()
        jobs["jobs"][0]["steps"] = []
        with self.assertRaises(gate.Unexecuted):
            self.verify(run, jobs)

    def test_runner_id_zero(self):
        run, jobs = good()
        jobs["jobs"][0]["runner_id"] = 0
        with self.assertRaises(gate.Unexecuted):
            self.verify(run, jobs)

    def test_empty_runner_name(self):
        run, jobs = good()
        jobs["jobs"][0]["runner_name"] = ""
        with self.assertRaises(gate.Unexecuted):
            self.verify(run, jobs)

    def test_wrong_head(self):
        run, jobs = good()
        run["head_sha"] = "b" * 40
        with self.assertRaises(gate.Unexecuted):
            self.verify(run, jobs)

    def test_wrong_repository_or_fork(self):
        for field in ("repository", "head_repository"):
            with self.subTest(field=field):
                run, jobs = good()
                run[field] = {"id": 999}
                with self.assertRaises(gate.Unexecuted):
                    self.verify(run, jobs)

    def test_wrong_workflow_id(self):
        run, jobs = good()
        run["workflow_id"] = 1
        with self.assertRaises(gate.Unexecuted):
            self.verify(run, jobs)

    def test_wrong_run_attempt(self):
        run, jobs = good()
        jobs["jobs"][0]["run_attempt"] = 2
        with self.assertRaises(gate.Unexecuted):
            self.verify(run, jobs)

    def test_wrong_job_head(self):
        run, jobs = good()
        jobs["jobs"][0]["head_sha"] = "b" * 40
        with self.assertRaises(gate.Unexecuted):
            self.verify(run, jobs)

    def test_missing_required_step(self):
        run, jobs = good()
        jobs["jobs"][0]["steps"].pop()
        with self.assertRaises(gate.Unexecuted):
            self.verify(run, jobs)

    def test_skipped_step(self):
        run, jobs = good()
        jobs["jobs"][0]["steps"][-1]["conclusion"] = "skipped"
        with self.assertRaises(gate.Unexecuted):
            self.verify(run, jobs)

    def test_duplicate_or_reordered_steps(self):
        for variant in ("duplicate", "reorder"):
            with self.subTest(variant=variant):
                run, jobs = good()
                steps = jobs["jobs"][0]["steps"]
                if variant == "duplicate":
                    steps.append(dict(steps[-1]))
                else:
                    steps.reverse()
                with self.assertRaises(gate.Unexecuted):
                    self.verify(run, jobs)

    def test_runner_labels_not_sufficient_if_missing(self):
        run, jobs = good()
        jobs["jobs"][0]["labels"].remove("oreslang-jdk25")
        with self.assertRaises(gate.Unexecuted):
            self.verify(run, jobs)

    def test_job_link_mismatch(self):
        run, jobs = good()
        jobs["jobs"][0]["run_id"] = 9001
        with self.assertRaises(gate.Unexecuted):
            self.verify(run, jobs)


if __name__ == "__main__":
    unittest.main()
