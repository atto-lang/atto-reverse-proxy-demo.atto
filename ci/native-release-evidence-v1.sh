#!/usr/bin/env bash
# FORMAT-ONLY review of a candidate native receipt. JSON is untrusted input.
# A passing check is NOT release authorization, independently authenticated
# GitHub Actions evidence, or proof that a compiler/guest actually executed.
set -euo pipefail
if (( $# != 1 )) || [[ ! -f "$1" || -L "$1" ]]; then
  echo 'EVIDENCE_REJECTED: expected exactly one regular JSON receipt file' >&2
  exit 2
fi
test -x /usr/bin/jq || { echo 'EVIDENCE_REJECTED: jq unavailable' >&2; exit 2; }
# A format-only receipt must still have an unambiguous single JSON encoding.
# jq normally accepts multiple top-level JSON texts and keeps the last value
# of duplicate object keys. Another consumer can bind a different identity.
# Refuse oversized, multi-document, or duplicate-key inputs before schema checks.
receipt_bytes="$(/usr/bin/stat -c %s -- "$1")" || exit 2
[[ "$receipt_bytes" =~ ^[0-9]+$ ]] && (( receipt_bytes > 0 && receipt_bytes <= 65536 )) || {
  echo 'EVIDENCE_REJECTED: candidate receipt exceeds bounded JSON budget' >&2
  exit 2
}
if ! /usr/bin/jq -s -e 'length == 1' "$1" >/dev/null; then
  echo 'EVIDENCE_REJECTED: require exactly one valid JSON document' >&2
  exit 2
fi
# Streaming retains duplicate-key events that ordinary jq object parsing
# discards. Track repeated leaf paths and reopened object/array parent paths.
if ! (
  /usr/bin/jq --stream -c . "$1" |
  /usr/bin/jq -s -e '
    reduce .[] as $event (
      {seen: [], closed: [], valid: true};
      if (.valid | not) then .
      elif ($event | length) == 2 then
        ($event[0] | tojson) as $leaf
        | [range(1; ($event[0] | length) + 1) | $event[0][0:.] | tojson] as $prefixes
        | .closed as $closed
        | .seen as $seen
        | if (($seen | index($leaf)) != null)
          or any($prefixes[]; . as $p | ($closed | index($p)) != null)
          or any($prefixes[0:-1][]; . as $p | ($seen | index($p)) != null)
          then .valid = false
          else .seen += [$leaf]
          end
      else
        .closed += [($event[0][0:-1] | tojson)]
      end
    ) | .valid
  ' >/dev/null
); then
  echo 'EVIDENCE_REJECTED: duplicate or reopened JSON object key' >&2
  exit 2
fi
if ! /usr/bin/jq -e '
  def sha40: type == "string" and test("^[0-9a-f]{40}$");
  def sha64: type == "string" and test("^[0-9a-f]{64}$");
  def positive_int: type == "number" and . >= 1 and . == floor;
  def complete_step: .status == "completed" and .conclusion == "success" and (.number | positive_int);
  def complete_roles:
    type == "array" and length == 3 and
    (map(.role) | sort) == ["compiler", "contracts", "wire"] and
    all(.[]; complete_step) and
    ([.[].number] | unique | length) == 3;
  type == "object" and
  .schema == "atto.proxy.native-evidence.v1" and
  (
    (.repository_id == 1429955596 and
     .source_sha == "fe46a4cac8c3cbedfaa5d872bc0e6348974141b5" and
     .source_tree == "42052135ffd0ed6db5f4d1031fbbc2234824b81a" and
     .compiler_checks == 31 and .standalone_contracts == 15)
    or
    (.repository_id == 1429954649 and
     .source_sha == "1a667fcd4481e3511e0cfa1008e855d96540c200" and
     .source_tree == "5937599df00b6122dccaf22bcdebdaf836f6d3ee" and
     .compiler_checks == 28 and .standalone_contracts == 13)
  ) and
  (.control_sha | sha40) and
  (.runtime_manifest_sha256 | sha64) and
  .jdk_major == 25 and
  (.run_id | positive_int) and
  (.run_attempt | positive_int) and
  (.job_id | positive_int) and
  (.runner_id | positive_int) and
  .status == "completed" and .conclusion == "success" and
  (.wire_tests | positive_int) and
  (.native_negative_mutations | positive_int) and
  .source_free == false and .host_only == false and
  .release_authorized == false and
  (.steps | complete_roles)
' "$1" >/dev/null; then
  echo 'EVIDENCE_REJECTED: native candidate schema, exact identity or executed-step claims invalid' >&2
  exit 2
fi
printf '%s\n' 'NATIVE_EVIDENCE_FORMAT_VALID_UNTRUSTED: no live GitHub API, signature, independent approval, protected-main or guest execution was verified; NOT_RELEASE_AUTHORITY'
