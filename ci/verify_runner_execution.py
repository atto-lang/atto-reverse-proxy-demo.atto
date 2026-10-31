#!/usr/bin/env python3
"""Fail-closed GitHub Actions *execution admission* checker, not a guest test.

Consumes operator-supplied raw GitHub REST JSON responses obtained from the
trusted GitHub Actions API; never invokes GitHub, runs guest code, or checks out
any source. Successful steps alone do NOT prove compiler digest, source tree,
capability enforcement, or Java/LLVM backend acceptance: inspect job logs
and independent backend receipts before changing a draft/merge decision.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys

SOURCE_REPO_ID = 1429954649
PROFILES = {
    "native": {
        "workflow_id": 393589123,
        "path": ".github/workflows/native-contracts.yml",
        "job": "native-contracts",
        "steps": (
            "Checkout exact PR tree",
            "Fail closed on exact source and approved native runner provenance",
            "Compiler-check all reviewed Oreslang files",
            "Run every reviewed standalone pure contract",
            "Execute complete Oreslang safety contracts",
        ),
    },
    "wire": {
        "workflow_id": 394408723,
        "path": ".github/workflows/actor-ingress-wire.yml",
        "job": "actor-ingress",
        "steps": (
            "Checkout exact PR head",
            "Verify trusted exact source and approved native runtime",
            "Real native Oreslang actor HTTP exchange over loopback",
        ),
    },
}
REQUIRED_LABELS = {"self-hosted", "linux", "x64", "oreslang-jdk25"}


class Unexecuted(RuntimeError):
    pass


def require(ok: bool, reason: str) -> None:
    if not ok:
        raise Unexecuted(reason)


def positive_int(value: object) -> bool:
    return type(value) is int and value > 0


def check_execution(run: dict, jobs_payload: dict, *, profile: str,
                    expected_head: str, expected_run_id: int,
                    pr: dict | None = None) -> dict:
    """Return verified step metadata; never claim guest or wire acceptance."""
    require(profile in PROFILES, "unknown workflow profile")
    require(bool(re.fullmatch(r"[0-9a-f]{40}", expected_head)), "expected SHA invalid")
    config = PROFILES[profile]
    if pr is not None:
        require(isinstance(pr, dict), "PR snapshot malformed")
        require(pr.get("state") == "open" and pr.get("number") == 11,
                "not the target open PR")
        require(isinstance(pr.get("head"), dict)
                and pr["head"].get("sha") == expected_head
                and isinstance(pr["head"].get("repo"), dict)
                and pr["head"]["repo"].get("id") == SOURCE_REPO_ID,
                "stale PR head or foreign head repository")
        require(isinstance(pr.get("base"), dict)
                and isinstance(pr["base"].get("repo"), dict)
                and pr["base"]["repo"].get("id") == SOURCE_REPO_ID,
                "foreign base repository")
    require(isinstance(run, dict) and isinstance(jobs_payload, dict), "malformed JSON")
    # Bind the run to the fresh PR identity, not merely a caller-supplied SHA.
    require(pr is not None, "fresh PR snapshot required")
    require(run.get("path") == config["path"], "wrong workflow path")
    require(run.get("head_branch") == pr["head"].get("ref"), "run head branch differs from PR")
    prs = run.get("pull_requests")
    require(isinstance(prs, list), "run PR associations missing")
    linked = [p for p in prs if isinstance(p, dict) and p.get("number") == 11]
    require(len(linked) == 1, "run is not uniquely linked to PR #11")
    linked_pr = linked[0]
    require(isinstance(linked_pr.get("head"), dict)
            and linked_pr["head"].get("sha") == expected_head
            and isinstance(linked_pr["head"].get("repo"), dict)
            and linked_pr["head"]["repo"].get("id") == SOURCE_REPO_ID,
            "run PR association head mismatch")
    require(isinstance(linked_pr.get("base"), dict)
            and isinstance(linked_pr["base"].get("repo"), dict)
            and linked_pr["base"]["repo"].get("id") == SOURCE_REPO_ID,
            "run PR association base repository mismatch")
    require(run.get("id") == expected_run_id and positive_int(expected_run_id),
            "run ID mismatch")
    require(run.get("workflow_id") == config["workflow_id"], "workflow ID mismatch")
    require(run.get("head_sha") == expected_head, "stale or mismatched head")
    require(run.get("event") == "pull_request", "not a pull-request run")
    repo = run.get("repository")
    require(isinstance(repo, dict) and repo.get("id") == SOURCE_REPO_ID,
            "source repository identity mismatch")
    head_repo = run.get("head_repository")
    require(isinstance(head_repo, dict) and head_repo.get("id") == SOURCE_REPO_ID,
            "missing or unapproved run head repository")
    require(run.get("status") == "completed" and run.get("conclusion") == "success",
            "run not successfully completed")
    attempt = run.get("run_attempt")
    require(positive_int(attempt), "invalid run attempt")

    jobs = jobs_payload.get("jobs")
    require(isinstance(jobs, list), "jobs payload missing")
    require(type(jobs_payload.get("total_count")) is int
            and jobs_payload["total_count"] == len(jobs),
            "incomplete or inconsistent paginated jobs payload")
    require(len(jobs) == 1, "unexpected job present or required job missing")
    matching = [j for j in jobs if isinstance(j, dict)
                and j.get("name") == config["job"]]
    require(len(matching) == 1, "required job missing or ambiguous")
    job = matching[0]
    require(job.get("run_id") == expected_run_id, "job linked to another run")
    require(job.get("run_attempt") == attempt, "job from another attempt")
    require(job.get("head_sha") == expected_head, "job head mismatch")
    require(job.get("status") == "completed" and job.get("conclusion") == "success",
            "required job failed, skipped, cancelled or queued")
    require(positive_int(job.get("id")), "job ID missing")
    require(positive_int(job.get("runner_id")), "no assigned runner")
    require(isinstance(job.get("runner_name"), str)
            and bool(job["runner_name"].strip()), "runner name missing")
    require(isinstance(job.get("labels"), list)
            and REQUIRED_LABELS.issubset(set(job["labels"])), "required runner labels missing")

    steps = job.get("steps")
    require(isinstance(steps, list) and bool(steps), "zero executed steps")
    names = [s.get("name") for s in steps if isinstance(s, dict)]
    require(len(names) == len(steps) and all(isinstance(n, str) and n for n in names)
            and len(names) == len(set(names)),
            "missing, malformed or duplicate step names")
    require(all(s.get("status") == "completed" and s.get("conclusion") == "success"
                and positive_int(s.get("number")) for s in steps),
            "incomplete, skipped, or failed step")
    step_numbers = [s["number"] for s in steps]
    require(step_numbers == sorted(set(step_numbers)),
            "duplicate or out-of-order step numbers")
    require(all(n in names for n in config["steps"]), "required execution step absent")
    indices = [names.index(n) for n in config["steps"]]
    require(indices == sorted(indices), "required execution steps out of order")
    return {"profile": profile, "run_id": expected_run_id,
            "head_sha": expected_head, "run_attempt": attempt,
            "job_id": job["id"], "runner_id": job["runner_id"],
            "steps": len(steps), "scope": "workflow-step-execution-only"}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pr-json", type=Path, required=True,
                        help="Fresh raw GitHub REST PR #11 snapshot")
    parser.add_argument("--run-json", type=Path, required=True)
    parser.add_argument("--jobs-json", type=Path, required=True)
    parser.add_argument("--profile", choices=sorted(PROFILES), required=True)
    parser.add_argument("--expected-head", required=True)
    parser.add_argument("--expected-run-id", required=True, type=int)
    args = parser.parse_args()
    try:
        pr = json.loads(args.pr_json.read_text(encoding="utf-8"))
        run = json.loads(args.run_json.read_text(encoding="utf-8"))
        jobs = json.loads(args.jobs_json.read_text(encoding="utf-8"))
        verified = check_execution(
            run, jobs, profile=args.profile,
            expected_head=args.expected_head,
            expected_run_id=args.expected_run_id, pr=pr)
    except (Unexecuted, OSError, ValueError, TypeError, KeyError) as exc:
        print(f"UNEXECUTED_OR_UNVERIFIED: {exc}", file=sys.stderr)
        return 1
    print("EXECUTED_WORKFLOW_STEPS_OBSERVED " + json.dumps(verified, sort_keys=True))
    print("NOT_GUEST_WIRE_OR_BACKEND_ACCEPTANCE")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
