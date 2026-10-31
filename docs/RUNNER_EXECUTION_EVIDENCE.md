# Native reverse-proxy runner and wire-evidence admission (source-free)

**Status at 2026-10-31:** no exact-head native compiler or actor TCP wire pass.
This document is an operator checklist and **not an execution receipt**.

## Exact source and required execution

PR #11: https://github.com/ores-truffle-oreslang/oreslang-reverse-proxy-demo.ores/pull/11

Pinned PR head at audit: `aa88404cc08ec6092a93e42d2d8e9a58970c755a`.
The native contracts workflow is ID `393589123`, with required job
`native-contracts`. The real-wire workflow is ID `394408723`,
with required job `actor-ingress`. Both require a trusted
`self-hosted, linux, x64, oreslang-jdk25` runner.

Run `ci/verify_runner_execution.py` on independently retrieved *raw* REST
JSON from GitHub, not PR text, copied check names, synthetic fixtures,
or self-reported workflow output:

```sh
gh api repos/ores-truffle-oreslang/oreslang-reverse-proxy-demo.ores/pulls/11 > /tmp/reverse-pr.json
gh api repos/ores-truffle-oreslang/oreslang-reverse-proxy-demo.ores/actions/runs/RUN_ID > /tmp/reverse-run.json
gh api repos/ores-truffle-oreslang/oreslang-reverse-proxy-demo.ores/actions/runs/RUN_ID/jobs?per_page=100 > /tmp/reverse-jobs.json
python3 -I ci/verify_runner_execution.py \
  --pr-json /tmp/reverse-pr.json \
  --run-json /tmp/reverse-run.json --jobs-json /tmp/reverse-jobs.json \
  --profile wire --expected-head aa88404cc08ec6092a93e42d2d8e9a58970c755a \
  --expected-run-id RUN_ID
```

For native contracts, change `--profile wire` to `--profile native`
and use its *own* run ID. Do not combine acceptance across runs.
If GitHub paginates jobs, fetch all pages; the checker rejects an
incomplete payload missing the required job, but a first-page successful
job alone is not a complete audit of every required job. If any other
required job failed, inspect it and keep the gate blocked.

The checker requires exact source SHA, numeric source repository ID,
immutable workflow ID, matching run/job/attempt, successful assigned
runner and all reviewed mandatory step names with non-skipped success.
`runner_id=0`, no jobs, an empty step list, or queued/cancelled runs
cannot qualify. The script prints `NOT_GUEST_WIRE_OR_BACKEND_ACCEPTANCE`
even on valid workflow-step metadata.

Then independently review the **executed job log** for the checked-out
source head AND root tree, JDK 25, reviewed launcher SHA-256 and repeated
wrapper probes. Native contract evidence additionally requires the
reviewed inventory, every Oreslang compiler check, and all 17 pure
contracts. Wire evidence requires server readiness, an actual separate
native client socket exchange, HTTP 200/403/400/404/501/503 cases as
present in the fixture, streaming framing, disconnect recovery and
bounded cleanup. A passing job metadata record does not substitute for
those logs; a log does not substitute for separate Java/Graal/LLVM
acceptance or source security/governance reviews.

## Latest inspected source-free capacity

These are harmless standalone workflows with no checkout, no source
copy, no secrets, no artifacts or caches. They only test if an Actions
job can actually execute a shell step, not whether Oreslang is runnable.

| Destination | Run | Result | Executed steps |
| --- | --- | --- | --- |
| sonus-auris-test/clients-api-contract | [41233377911](https://github.com/sonus-auris-test/clients-api-contract/actions/runs/41233377911) | failed, runner_id=0 | 0 |
| ores-otel-test/next-loggers-runtime-conformance | [41233416648](https://github.com/ores-otel-test/next-loggers-runtime-conformance/actions/runs/41233416648) | failed, runner_id=0 | 0 |
| honeypot-r-us-test/hnpt-e2e | [41231112018](https://github.com/honeypot-r-us-test/hnpt-e2e/actions/runs/41231112018) | failed, runner_id=0 | 0 |
| akrion-sim/akrion-sim-e2e | [41126204171](https://github.com/akrion-sim/akrion-sim-e2e/actions/runs/41126204171) | failed, runner_id=0 | 0 |
| scintilla-run/scintilla-run-e2e | [41217749367](https://github.com/scintilla-run/scintilla-run-e2e/actions/runs/41217749367) | failed, runner_id=0 | 0 |
| benefactor-cc/benefactor-e2e | [41162044959](https://github.com/benefactor-cc/benefactor-e2e/actions/runs/41162044959) | failed, runner_id=0 | 0 |

Zero-step failures **do not diagnose billing**: inspect billing, org
policy, runner registration/labels, runner-group admission and plan
restrictions with an administrator. A previously successful run proves
only past execution, not current available capacity.

## Private source mirror deny-by-default

No Oreslang source has been transferred by these canaries.

The Java compiler source publisher's security contract at
`oreslang-source.java/docs/security/CI_PRIVATE_SOURCE_MIRRORING.md`
requires protected source `main`, an approved immutable destination
identity in protected policy, separately pinned carrier contract and
workflow/test-plan digests, independent security review and exact-tree
attestation. Its checked source allowlist contains no approved
destination; an example candidate comment is **not approval**.
This policy is not itself authorization to transfer the **reverse-proxy
repository**: its owner must additionally review and approve that
source's destination and execution boundary. The existing proxy
workflow's repository-ID gate cannot simply be bypassed on a
different organization.

Do not perform a cross-org private-source mirror until destination
authorization is independently established. Continue only source-free
canaries and static local/offline tests meanwhile. Keep PR #11 draft.

## 2026-10-31 hardened exact-PR proof update

The proof verifier now requires the run to identify the immutable workflow path,
a fresh GitHub REST PR #11 snapshot, the same head branch, exactly one PR #11
association with the matching head SHA and source/base repository identity,
and the complete jobs page set (`total_count == len(jobs)`). Incomplete
pagination, a missing head-repository identity, unrelated PR runs, unexpected extra jobs, ambiguous
job names, duplicated step numbers, and skipped or unassigned jobs all fail closed. The verifier does
not generate a release-approval receipt; it only reports API-level step
execution metadata, and a live JDK25 compiler digest/tree check still requires
independent job-log inspection.

`ci/test_runner_execution.py` contains **27 synthetic unittest methods**.
Local verification on the reviewed branch passed 27/27, and tested Git
blob SHA readback matched:
- `ci/verify_runner_execution.py`: `62c98818f583a1f52e1b7f7d09069c0a33c07fea`.
- `ci/test_runner_execution.py`: `c33595487c0ea2ace7e3dd5daa42b4783333a2ed`.

The source-free workflow's pull-request and push filters now include the
actor-ingress base and the review branch, so the tests are eligible for CI.
However, the first new source-free execution [run 41234501457](https://github.com/ores-truffle-oreslang/oreslang-reverse-proxy-demo.ores/actions/runs/41234501457)
was **failure with zero executed steps and `runner_id=0`**. Workflow
eligibility is not a running runner. Leave the CI gate blocked.

Both this repository and `oreslang-source.java` currently report
`main.protected=false`; the Java V3 mirroring policy therefore denies
source-bearing export, and **no proxy-specific approved private source
carrier exists**. Do not weaken the original repository-ID guard in
`native-contracts.yml` or `actor-ingress-wire.yml` to force an
unapproved cross-org execution.
