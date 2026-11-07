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
# Check size before copying, then parse only a private immutable-by-convention
# snapshot. Independent jq reads of a caller-writable path can see different
# files, creating parser/identity disagreement between admission passes.
source_bytes="$(/usr/bin/stat -c %s -- "$1")" || exit 2
[[ "$source_bytes" =~ ^[0-9]+$ ]] && (( source_bytes > 0 && source_bytes <= 65536 )) || {
  echo 'EVIDENCE_REJECTED: source receipt exceeds bounded JSON budget' >&2
  exit 2
}
umask 077
snapshot_dir="$(/usr/bin/mktemp -d)" || exit 2
trap '/usr/bin/rm -rf -- "$snapshot_dir"' EXIT
receipt="$snapshot_dir/receipt.json"
/usr/bin/cp -- "$1" "$receipt" || {
  echo 'EVIDENCE_REJECTED: unable to snapshot receipt' >&2
  exit 2
}
receipt_bytes="$(/usr/bin/stat -c %s -- "$receipt")" || exit 2
[[ "$receipt_bytes" =~ ^[0-9]+$ ]] && (( receipt_bytes > 0 && receipt_bytes <= 65536 )) || {
  echo 'EVIDENCE_REJECTED: snapshotted receipt exceeds bounded JSON budget' >&2
  exit 2
}
# jq accepts a NUL after valid JSON and may ignore trailing data. Reject all
# non-ASCII/control octets before parsing so other JSON consumers cannot see
# a different byte stream. The fixed schema uses only ASCII keys and values;
# JSON \u escapes remain permissible.
allowed_bytes="$(LC_ALL=C /usr/bin/tr -cd '\011\012\015\040-\176' < "$receipt" | /usr/bin/wc -c)" || exit 2
[[ "$allowed_bytes" -eq "$receipt_bytes" ]] || {
  echo 'EVIDENCE_REJECTED: receipt contains non-ASCII or disallowed control bytes' >&2
  exit 2
}
# jq accepts non-JSON numeric spellings (+101, 0101, .101, 101.)
# and rounds high-precision fractions (101.0000000000000001) into integers.
# A second parser can bind a different run/job/step identity. Strip quoted
# strings as whole tokens, then reject every noncanonical unquoted token.
# The bounded ASCII snapshot is checked before jq's permissive JSON parser.
# This is still format-only evidence, not native or release authorization.
if ! /usr/bin/jq -Rse '
  gsub("\"(?:\\\\.|[^\"\\\\])*\""; " ")
  | gsub("[\\[\\]{}:,[:space:]]"; " ")
  | split(" ")
  | map(select(length > 0))
  | all(.[]; . == "true" or . == "false" or . == "null" or test("^(0|[1-9][0-9]*)$"))
' "$receipt" >/dev/null; then
  echo 'EVIDENCE_REJECTED: noncanonical or floating-point numeric JSON token' >&2
  exit 2
fi
if ! /usr/bin/jq -s -e 'length == 1' "$receipt" >/dev/null; then
  echo 'EVIDENCE_REJECTED: require exactly one valid JSON document' >&2
  exit 2
fi
# Streaming retains duplicate-key events that ordinary jq object parsing
# discards. Track repeated leaf paths and reopened object/array parent paths.
if ! (
  /usr/bin/jq --stream -c . "$receipt" |
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
  # Explicit vocabulary: no unreviewed, contradictory claims may ride along.
  # In particular, fields suggesting approval or native proof must not be
  # interpreted by downstream consumers of a mere format-only candidate.
  def exact_fields($expected): type == "object" and (keys == ($expected | sort));
  # Bound identity/count values to the IEEE-754 exact-integer range so
  # downstream JSON consumers cannot silently round run/job/step IDs.
  def positive_int: type == "number" and . >= 1 and . <= 9007199254740991 and . == floor;
  def complete_step: .status == "completed" and .conclusion == "success" and (.number | positive_int);
  def complete_roles:
    type == "array" and length == 3 and
    (map(.role) | sort) == ["compiler", "contracts", "wire"] and
    all(.[]; exact_fields(["role", "number", "status", "conclusion"]) and complete_step) and
    ([.[].number] | unique | length) == 3;
  exact_fields([
    "schema", "repository_id", "source_sha", "source_tree", "control_sha",
    "runtime_manifest_sha256", "jdk_major", "run_id", "run_attempt",
    "job_id", "runner_id", "status", "conclusion", "compiler_checks",
    "standalone_contracts", "wire_tests", "native_negative_mutations",
    "source_free", "host_only", "release_authorized", "steps"
  ]) and
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
' "$receipt" >/dev/null; then
  echo 'EVIDENCE_REJECTED: native candidate schema, exact identity or executed-step claims invalid' >&2
  exit 2
fi
printf '%s\n' 'NATIVE_EVIDENCE_FORMAT_VALID_UNTRUSTED: no live GitHub API, signature, independent approval, protected-main or guest execution was verified; NOT_RELEASE_AUTHORITY'
