#!/usr/bin/env bash
# Hermetic, source-free mutation-sensitivity tests for native receipt validation.
# Mutants must preserve the valid format baseline and expose one invalid receipt.
# No synthetic fixture is GitHub Actions or AttoLang guest-execution proof.
set -euo pipefail
if (( $# != 1 )); then echo 'usage: test-evidence-mutation-sensitivity.sh forward|reverse' >&2; exit 2; fi
root="$(cd "$(dirname "$0")/.." && pwd -P)"
validator="$root/ci/native-release-evidence-v1.sh"
tmp="$(/usr/bin/mktemp -d)"
trap '/usr/bin/rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/ci"
case "$1" in
  forward)
    repository_id=1429955596
    source_sha=fe46a4cac8c3cbedfaa5d872bc0e6348974141b5
    source_tree=42052135ffd0ed6db5f4d1031fbbc2234824b81a
    compiler_checks=31 standalone_contracts=15 ;;
  reverse)
    repository_id=1429954649
    source_sha=1a667fcd4481e3511e0cfa1008e855d96540c200
    source_tree=5937599df00b6122dccaf22bcdebdaf836f6d3ee
    compiler_checks=28 standalone_contracts=13 ;;
  *) echo 'invalid side' >&2; exit 2 ;;
esac
test -f "$validator" && test ! -L "$validator" && test -x /usr/bin/jq
/usr/bin/jq -n \
  --argjson repository_id "$repository_id" \
  --arg source_sha "$source_sha" --arg source_tree "$source_tree" \
  --argjson compiler_checks "$compiler_checks" \
  --argjson standalone_contracts "$standalone_contracts" '
  {
    schema:"atto.proxy.native-evidence.v1",
    repository_id:$repository_id, source_sha:$source_sha, source_tree:$source_tree,
    control_sha:("a"*40), runtime_manifest_sha256:("b"*64), jdk_major:25,
    run_id:101, run_attempt:1, job_id:102, runner_id:103,
    status:"completed", conclusion:"success",
    compiler_checks:$compiler_checks, standalone_contracts:$standalone_contracts,
    wire_tests:1, native_negative_mutations:1,
    source_free:false, host_only:false, release_authorized:false,
    steps:[
      {role:"compiler", number:1, status:"completed", conclusion:"success"},
      {role:"contracts", number:2, status:"completed", conclusion:"success"},
      {role:"wire", number:3, status:"completed", conclusion:"success"}
    ]
  }
' > "$tmp/valid.json"
/bin/bash "$validator" "$tmp/valid.json" | /usr/bin/grep -Fq NOT_RELEASE_AUTHORITY
original="$(/usr/bin/cat -- "$validator")"
killed=0
check_mutant() {
  local label="$1" needle="$2" replacement="$3" tamper="$4"
  local tail mutated
  if [[ "$original" != *"$needle"* ]]; then
    echo "MUTATION_TEST_FAILURE: missing anchor $label" >&2; exit 1
  fi
  tail="${original#*"$needle"}"
  if [[ "$tail" == *"$needle"* ]]; then
    echo "MUTATION_TEST_FAILURE: ambiguous anchor $label" >&2; exit 1
  fi
  mutated="${original/"$needle"/"$replacement"}"
  test "$mutated" != "$original" || exit 1
  /usr/bin/printf '%s\n' "$mutated" > "$tmp/ci/native-release-evidence-v1.sh"
  /bin/bash -n "$tmp/ci/native-release-evidence-v1.sh"
  /usr/bin/jq "$tamper" "$tmp/valid.json" > "$tmp/invalid.json"
  # The ORIGINAL must reject the tampered fixture.
  if /bin/bash "$validator" "$tmp/invalid.json" >/dev/null 2>&1; then
    echo "MUTATION_TEST_FAILURE: original accepted invalid $label" >&2; exit 1
  fi
  # Prevent vacuous kills: a mutant must still accept the unmodified valid
  # fixture, with an explicit NOT_RELEASE_AUTHORITY disclaimer.
  if ! /bin/bash "$tmp/ci/native-release-evidence-v1.sh" "$tmp/valid.json" |
    /usr/bin/grep -Fq NOT_RELEASE_AUTHORITY; then
    echo "MUTATION_TEST_FAILURE: mutant broke positive control $label" >&2; exit 1
  fi
  # Discriminating counterexample: weakening a predicate admits the tamper.
  if ! /bin/bash "$tmp/ci/native-release-evidence-v1.sh" "$tmp/invalid.json" |
    /usr/bin/grep -Fq NOT_RELEASE_AUTHORITY; then
    echo "MUTATION_TEST_FAILURE: mutation was not exposed $label" >&2; exit 1
  fi
  killed=$((killed + 1))
  echo "EVIDENCE_MUTANT_EXPOSED name=$label"
}
check_mutant repo-id ".repository_id == $repository_id and" 'true and' '.repository_id=999'
check_mutant source-sha ".source_sha == \"$source_sha\" and" 'true and' '.source_sha=("f"*40)'
check_mutant source-tree ".source_tree == \"$source_tree\" and" 'true and' '.source_tree=("f"*40)'
check_mutant compiler-count ".compiler_checks == $compiler_checks and" 'true and' '.compiler_checks=0'
check_mutant contract-count ".standalone_contracts == $standalone_contracts and" 'true and' '.standalone_contracts=0'
check_mutant control-sha '(.control_sha | sha40) and' 'true and' '.control_sha="short"'
check_mutant runtime-digest '(.runtime_manifest_sha256 | sha64) and' 'true and' '.runtime_manifest_sha256="short"'
check_mutant jdk-major '.jdk_major == 25 and' 'true and' '.jdk_major=24'
check_mutant run-id '(.run_id | positive_int) and' 'true and' '.run_id=0'
check_mutant native-negative '(.native_negative_mutations | positive_int) and' 'true and' '.native_negative_mutations=0'
check_mutant wire-count '(.wire_tests | positive_int) and' 'true and' '.wire_tests=0'
check_mutant source-free '.source_free == false and .host_only == false and' 'true and .host_only == false and' '.source_free=true'
check_mutant host-only '.source_free == false and .host_only == false and' '.source_free == false and true and' '.host_only=true'
check_mutant release-authority '.release_authorized == false and' 'true and' '.release_authorized=true'
check_mutant closed-schema 'def exact_fields($expected): type == "object" and (keys == ($expected | sort));' 'def exact_fields($expected): type == "object";' '.unreviewed_extra_key=true'
check_mutant step-completeness '(.steps | complete_roles)' 'true' '.steps=[]'
check_mutant step-role-set '(map(.role) | sort) == ["compiler", "contracts", "wire"] and' 'true and' '.steps[1].role="compiler"'
check_mutant step-outcome 'def complete_step: .status == "completed" and .conclusion == "success" and (.number | positive_int);' 'def complete_step: (.number | positive_int);' '.steps[1].conclusion="failure"'
check_mutant step-uniqueness '([.[].number] | unique | length) == 3;' 'true;' '.steps[1].number=1'
test "$killed" -eq 19
echo "SOURCE_FREE_EVIDENCE_MUTATION_SENSITIVITY_PASS mutants=$killed native_guest=NOT_EXECUTED release_authority=NONE"
