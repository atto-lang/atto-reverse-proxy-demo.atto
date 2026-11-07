#!/usr/bin/env bash
# Hermetic format-contract tests; never treat synthetic receipts as native evidence.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp="$(/usr/bin/mktemp -d)"
trap '/usr/bin/rm -rf -- "$tmp"' EXIT
make_valid() {
  local repo source tree compiler contracts
  case "$1" in
    forward)
      repo=1429955596 source=fe46a4cac8c3cbedfaa5d872bc0e6348974141b5
      tree=42052135ffd0ed6db5f4d1031fbbc2234824b81a compiler=31 contracts=15 ;;
    reverse)
      repo=1429954649 source=1a667fcd4481e3511e0cfa1008e855d96540c200
      tree=5937599df00b6122dccaf22bcdebdaf836f6d3ee compiler=28 contracts=13 ;;
    *) exit 1 ;;
  esac
  /usr/bin/jq -n --argjson repo "$repo" --arg source "$source" --arg tree "$tree" \
    --argjson compiler "$compiler" --argjson contracts "$contracts" '
    {schema:"atto.proxy.native-evidence.v1", repository_id:$repo,
     source_sha:$source, source_tree:$tree, control_sha:("a" * 40),
     runtime_manifest_sha256:("b" * 64), jdk_major:25,
     run_id:101, run_attempt:1, job_id:102, runner_id:103,
     status:"completed", conclusion:"success", compiler_checks:$compiler,
     standalone_contracts:$contracts, wire_tests:1, native_negative_mutations:1,
     source_free:false, host_only:false, release_authorized:false,
     steps:[
       {role:"compiler", number:1, status:"completed", conclusion:"success"},
       {role:"contracts", number:2, status:"completed", conclusion:"success"},
       {role:"wire", number:3, status:"completed", conclusion:"success"}
     ]}
  ' > "$tmp/base.json"
}
negative=0
reject() {
  if /bin/bash "$root/ci/native-release-evidence-v1.sh" "$tmp/candidate.json" >/dev/null 2>&1; then
    echo 'TEST_FAILURE: invalid or untrusted receipt accepted' >&2
    exit 1
  fi
  negative=$((negative+1))
}
for side in forward reverse; do
  make_valid "$side"
  /bin/bash "$root/ci/native-release-evidence-v1.sh" "$tmp/base.json" | /usr/bin/grep -Fq 'NOT_RELEASE_AUTHORITY'
  /usr/bin/cp "$tmp/base.json" "$tmp/candidate.json"
  for mutation in \
    '.schema="wrong"' '.repository_id=0' '.source_sha="stale"' \
    '.source_tree="stale"' '.control_sha="short"' \
    '.runtime_manifest_sha256="unknown"' '.jdk_major=24' \
    '.run_id=0' '.run_attempt=0' '.job_id=0' '.runner_id=0' \
    '.status="queued"' '.conclusion="cancelled"' \
    '.steps=[]' '.steps=null' \
    '.steps[0].conclusion="failure"' '.steps[1].status="queued"' \
    '.steps[2].role="compiler"' '.steps[0].number=2' \
    '.compiler_checks=0' '.standalone_contracts=0' \
    '.wire_tests=0' '.native_negative_mutations=0' \
    '.source_free=true' '.host_only=true' '.release_authorized=true'; do
    /usr/bin/jq "$mutation" "$tmp/base.json" > "$tmp/candidate.json"
    reject
  done
  # These raw-text mutations bypass ordinary jq's last-key-wins parsing.
  # A separate process could interpret a different source, verdict or step.
  /usr/bin/sed 's/"source_free": false,/"source_free": true, "source_free": false,/' "$tmp/base.json" > "$tmp/candidate.json"
  reject
  /usr/bin/sed 's/"role": "compiler",/"role": "wire", "role": "compiler",/' "$tmp/base.json" > "$tmp/candidate.json"
  reject
  /usr/bin/sed 's/"steps": \[/"steps": [], "steps": [/' "$tmp/base.json" > "$tmp/candidate.json"
  reject
  /usr/bin/cat "$tmp/base.json" "$tmp/base.json" > "$tmp/candidate.json"
  reject
  /usr/bin/printf '{}\n' > "$tmp/candidate.json"
  /usr/bin/cat "$tmp/base.json" >> "$tmp/candidate.json"
  reject
  /usr/bin/cp "$tmp/base.json" "$tmp/candidate.json"
  /usr/bin/printf '%*s' 66000 '' >> "$tmp/candidate.json"
  reject
  # A jq-positive integer can exceed the exact range of JS/JSON consumers.
  # Reject identity collisions from rounding, oversized counts and steps.
  for mutation in \
    '.run_id=9007199254740992' \
    '.run_attempt=9007199254740992' \
    '.job_id=1e30' \
    '.runner_id=1e308' \
    '.wire_tests=1e30' \
    '.native_negative_mutations=9007199254740992' \
    '.steps[0].number=9007199254740992' \
    '.steps[1].number=1e30'; do
    /usr/bin/jq "$mutation" "$tmp/base.json" > "$tmp/candidate.json"
    reject
  done
  # Closed schema: do not let speculative approval/provenance keys bypass
  # the explicitly non-authoritative result or conflict with checked roles.
  for mutation in \
    '.release_approved_by_admin=true' \
    '.independent_review="APPROVED"' \
    '.verified_guest_execution=true' \
    '.extra_source_tree="ffffffffffffffffffffffffffffffffffffffff"' \
    '.steps[0].native_execution_proven=true' \
    '.steps[1].runner_id=999'; do
    /usr/bin/jq "$mutation" "$tmp/base.json" > "$tmp/candidate.json"
    reject
  done
  # JSON number syntax matters even when jq's floating-point evaluation
  # rounds the token back into an integer. A second receipt parser may not
  # agree about a run ID, attempt or step number. Exercise both receipt types.
  for token in 101.0 101e0 101.0000000000000001 1.01e2 101E+0 0101 00101 +101 .101 101. 101e00; do
    /usr/bin/sed "s/\"run_id\": 101,/\"run_id\": $token,/" "$tmp/base.json" > "$tmp/candidate.json"
    reject
  done
  for token in 1.0 1e0 1.0000000000000001 1E+0 01 001 +1 .1 1. 1e00; do
    /usr/bin/sed "s/\"number\": 1,/\"number\": $token,/" "$tmp/base.json" > "$tmp/candidate.json"
    reject
  done
  # jq may silently ignore a NUL suffix; another parser may treat it as a
  # boundary or consume a second contradictory document. Fail before jq.
  /usr/bin/cp "$tmp/base.json" "$tmp/candidate.json"
  /usr/bin/printf '\000' >> "$tmp/candidate.json"
  reject
  /usr/bin/cp "$tmp/base.json" "$tmp/candidate.json"
  /usr/bin/printf '\000{"release_authorized":true}\n' >> "$tmp/candidate.json"
  reject
  /usr/bin/cp "$tmp/base.json" "$tmp/candidate.json"
  /usr/bin/printf '\377' >> "$tmp/candidate.json"
  reject
  /usr/bin/cp "$tmp/base.json" "$tmp/candidate.json"
  /usr/bin/printf '\033[31m' >> "$tmp/candidate.json"
  reject
  /usr/bin/cp "$tmp/base.json" "$tmp/candidate.json"
  /usr/bin/printf '\302\240' >> "$tmp/candidate.json"
  reject
  { /usr/bin/printf '\357\273\277'; /usr/bin/cat "$tmp/base.json"; } > "$tmp/candidate.json"
  reject
done
printf 'SOURCE_FREE_NATIVE_EVIDENCE_FORMAT_TESTS_PASS positive_fixtures=2 negative_mutations=%s; native_guest=NOT_EXECUTED\n' "$negative"
