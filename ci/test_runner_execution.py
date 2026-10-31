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


def good_pr():
    return {"state": "open", "number": 11,
            "head": {"sha": HEAD, "ref": "feat/executable-actor-ingress-gate-20261023", "repo": {"id": gate.SOURCE_REPO_ID}},
            "base": {"repo": {"id": gate.SOURCE_REPO_ID}}}


def good(profile="wire"):
    cfg = gate.PROFILES[profile]
    steps = [{"name": name, "number": i, "status": "completed",
              "conclusion": "success"}
             for i, name in enumerate(cfg["steps"], 1)]
    run = {
        "id": RUN_ID, "workflow_id": cfg["workflow_id"],
        "path": cfg["path"],
        "head_branch": "feat/executable-actor-ingress-gate-20261023",
        "pull_requests": [{"number": 11,
                           "head": {"sha": HEAD, "repo": {"id": gate.SOURCE_REPO_ID}},
                           "base": {"repo": {"id": gate.SOURCE_REPO_ID}}}],
        "head_sha": HEAD, "event": "pull_request",
        "repository": {"id": gate.SOURCE_REPO_ID},
        "head_repository": {"id": gate.SOURCE_REPO_ID},
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
    return run, {"total_count": 1, "jobs": [job]}


class AdmissionEvidence(unittest.TestCase):
    def verify(self, run, jobs, profile="wire"):
        return gate.check_execution(run, jobs, profile=profile,
                                    expected_head=HEAD, expected_run_id=RUN_ID, pr=good_pr())

    def test_synthetic_wire_metadata(self):
        run, jobs = good()
        record = self.verify(run, jobs)
        self.assertEqual(record["scope"], "workflow-step-execution-only")

    def test_synthetic_native_metadata(self):
        run, jobs = good("native")
        self.assertEqual(self.verify(run, jobs, "native")["steps"], 5)

    def test_pr_snapshot_head_must_match(self):
        run, jobs = good()
        pr = good_pr()
        pr["head"]["sha"] = "b" * 40
        with self.assertRaises(gate.Unexecuted):
            gate.check_execution(run, jobs, profile="wire", expected_head=HEAD,
                                 expected_run_id=RUN_ID, pr=pr)

    def test_pr_foreign_head_repository(self):
        run, jobs = good()
        pr = good_pr()
        pr["head"]["repo"]["id"] = 999
        with self.assertRaises(gate.Unexecuted):
            gate.check_execution(run, jobs, profile="wire", expected_head=HEAD,
                                 expected_run_id=RUN_ID, pr=pr)

    def test_workflow_path_replacement(self):
        run, jobs = good()
        run["path"] = ".github/workflows/fake.yml"
        with self.assertRaises(gate.Unexecuted):
            self.verify(run, jobs)

    def test_mismatched_run_branch(self):
        run, jobs = good()
        run["head_branch"] = "another-branch"
        with self.assertRaises(gate.Unexecuted):
            self.verify(run, jobs)

    def test_wrong_pr_linkage(self):
        for change in ("missing", "another_pr", "stale_sha", "foreign_repo"):
            with self.subTest(change=change):
                run, jobs = good()
                if change == "missing":
                    run["pull_requests"] = []
                elif change == "another_pr":
                    run["pull_requests"][0]["number"] = 33
                elif change == "stale_sha":
                    run["pull_requests"][0]["head"]["sha"] = "b" * 40
                else:
                    run["pull_requests"][0]["base"]["repo"]["id"] = 0
                with self.assertRaises(gate.Unexecuted):
                    self.verify(run, jobs)

    def test_incomplete_job_pagination(self):
        run, jobs = good()
        jobs["total_count"] = 2
        with self.assertRaises(gate.Unexecuted):
            self.verify(run, jobs)

    def test_missing_run_head_repo(self):
        run, jobs = good()
        run["head_repository"] = None
        with self.assertRaises(gate.Unexecuted):
            self.verify(run, jobs)

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
