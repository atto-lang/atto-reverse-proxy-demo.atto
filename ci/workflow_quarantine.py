#!/usr/bin/env python3
"""Fail-closed structural admission check for *fixed* legacy native CI jobs.

This is deliberately not a YAML parser or an authorization decision. It only
accepts the exact job layout currently quarantined while protected-main native
runner admission is being designed. Treat PR-editable checks as advisory.
"""
from __future__ import annotations

import re

RUNNER_LINE = "    runs-on: [self-hosted, linux, x64, oreslang-jdk25]"
HOLD_LINE = "    if: ${{ false }}"


def verify_quarantined_job(workflow: str, expected_job: str) -> None:
    if not re.fullmatch(r"[a-z][a-z0-9-]*", expected_job):
        raise AssertionError("invalid expected native job identifier")

    lines = workflow.splitlines()
    top_level_jobs = [line for line in lines
                      if re.match(r"^jobs\s*:", line)]
    if top_level_jobs != ["jobs:"]:
        raise AssertionError("native workflow must have one unambiguous jobs section")
    jobs_start = lines.index("jobs:") + 1
    jobs_end = next((i for i in range(jobs_start, len(lines))
                     if lines[i] and not lines[i][0].isspace()
                     and not lines[i].startswith("#")), len(lines))
    body = lines[jobs_start:jobs_end]

    # Fail if an unexpected job could request a runner. A fixed-layout
    # allowlist is easier to audit than attempting to parse arbitrary YAML.
    job_keys = [line for line in body if re.fullmatch(r"  [A-Za-z0-9_-]+:\s*", line)]
    if job_keys != [f"  {expected_job}:"]:
        raise AssertionError("native workflow has an unexpected or missing job")

    # Do not accept YAML merges, anchors, aliases, or malformed indentation at
    # the job level. They could make a textual guard diverge from parsed YAML.
    if any(re.match(r"^  \S", line) and line != f"  {expected_job}:"
           and not line.lstrip().startswith("#") for line in body):
        raise AssertionError("native workflow has ambiguous job-level syntax")
    direct = [line for line in body if line.startswith("    ")
              and not line.startswith("     ")
              and not line.lstrip().startswith("#")]
    conditions = [line for line in direct if re.match(r"    if\s*:", line)]
    runners = [line for line in direct if re.match(r"    runs-on\s*:", line)]
    if conditions != [HOLD_LINE]:
        raise AssertionError("native job must have exactly one literal job-level false condition")
    if runners != [RUNNER_LINE]:
        raise AssertionError("native job runner must remain explicitly self-hosted and pinned")
    if any(re.match(r"    (<<|uses|strategy)\s*:", line) for line in direct):
        raise AssertionError("native job has unreviewed YAML merge/reuse/matrix semantics")
