# frozen_string_literal: true
# Adversarial source-only tests of parsed GitHub Actions workflow semantics.
require 'tempfile'
require 'open3'
require 'rbconfig'

abort 'usage: ruby test-trusted-workflow-yaml-contract.rb WORKFLOW.yml forward|reverse' unless ARGV.length == 2
workflow, side = ARGV
verifier = File.join(__dir__, 'trusted-workflow-yaml-contract.rb')
original = File.read(workflow)

def run_validator(verifier, body, side)
  Tempfile.create(['trusted-workflow-test-', '.yml']) do |file|
    file.write(body)
    file.flush
    out, err, status = Open3.capture3(RbConfig.ruby, verifier, file.path, side)
    [status.success?, out + err]
  end
end

def replace_once(text, before, after, label)
  abort "AMBIGUOUS_MUTATION_ANCHOR: #{label}" unless text.scan(before).length == 1
  text.sub(before, after)
end

unless run_validator(verifier, original, side).first
  abort 'VALID_WORKFLOW_REJECTED: expected original semantic workflow to pass'
end
repo_id, sha = case side
when 'forward' then ['1429955596', 'fe46a4cac8c3cbedfaa5d872bc0e6348974141b5']
when 'reverse' then ['1429954649', '1a667fcd4481e3511e0cfa1008e855d96540c200']
else abort 'unknown side'
end
cases = {
  'pr-trigger' => ->(s) { replace_once(s, '  workflow_dispatch:', '  pull_request:', 'trigger') },
  'pr-target' => ->(s) { replace_once(s, '  workflow_dispatch:', '  pull_request_target:', 'trigger') },
  'added-trigger' => ->(s) { replace_once(s, '  workflow_dispatch:', "  workflow_dispatch:\n  pull_request:", 'trigger') },
  'duplicate-on' => ->(s) { s + "\non:\n  workflow_dispatch:\n" },
  'permission-write' => ->(s) { replace_once(s, '  contents: read', '  contents: write', 'permission') },
  'token-write' => ->(s) { replace_once(s, '  contents: read', "  contents: read\n  id-token: write", 'token') },
  'duplicate-permissions' => ->(s) { s + "\npermissions:\n  contents: read\n" },
  'unreviewed-job' => ->(s) { replace_once(s, 'jobs:', "jobs:\n  unexpected:\n    runs-on: ubuntu-24.04\n    steps: []", 'jobs') },
  'job-permissions' => ->(s) { replace_once(s, '  native-contracts:', "  native-contracts:\n    permissions:\n      id-token: write", 'job') },
  'job-env-preload' => ->(s) { replace_once(s, '  native-contracts:', "  native-contracts:\n    env:\n      LD_PRELOAD: /tmp/evil.so", 'job') },
  'wrong-native-runner-group' => ->(s) { replace_once(s, 'group: oreslang-trusted-native', 'group: default', 'runner') },
  'wrong-runner-label' => ->(s) { replace_once(s, 'oreslang-jdk25]', 'unreviewed-label]', 'runner') },
  'missing-protection-guard' => ->(s) { s.sub('github.ref_protected == true', 'github.ref_protected == false') },
  'guard-bypass' => ->(s) { s.sub('github.ref_protected == true', 'github.ref_protected == true || true') },
  'wrong-repo' => ->(s) { s.sub("github.repository_id == '#{repo_id}'", "github.repository_id == '0'") },
  'conditional-skip' => ->(s) { s.sub('      - name: ', "      - continue-on-error: true\n        name: ") },
  'unreviewed-action' => ->(s) { replace_once(s, 'uses: actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09', 'uses: actions/checkout@v5', 'uses') },
  'floating-source' => ->(s) { replace_once(s, "ref: #{sha}", 'ref: main', 'ref') },
  'persist-checkout-token' => ->(s) { replace_once(s, 'persist-credentials: false', 'persist-credentials: true', 'with') },
  'preload-root' => ->(s) { replace_once(s, "  LD_PRELOAD: ''", '  LD_PRELOAD: /tmp/evil.so', 'env') },
  'extra-root-env' => ->(s) { replace_once(s, "  LD_PRELOAD: ''", "  LD_PRELOAD: ''\n  EXTRA_LD_PRELOAD: /tmp/evil.so", 'env') },
  'step-env-overrides' => ->(s) { s.sub('          GH_READ_TOKEN:', "          LD_PRELOAD: /tmp/evil.so\n          GH_READ_TOKEN:") },
  'unsafe-alias' => ->(s) { replace_once(s, '  contents: read', '  contents: &scope read', 'anchor') },
  'explicit-tag' => ->(s) { replace_once(s, '  contents: read', '  contents: !!str read', 'tag') },
  'second-document' => ->(s) { s + "\n---\npermissions: {}\n" },
  'duplicate-checkout-key' => ->(s) { replace_once(s, 'persist-credentials: false', "persist-credentials: false\n          persist-credentials: true", 'with') }
}
count = 0
cases.each do |name, mutate|
  candidate = mutate.call(original)
  abort "Vacuous mutation: #{name}" if candidate == original
  accepted, detail = run_validator(verifier, candidate, side)
  abort "UNSAFE_WORKFLOW_ACCEPTED: #{name} #{detail}" if accepted
  count += 1
end
puts "SOURCE_FREE_TRUSTED_YAML_NEGATIVE_TESTS_PASS side=#{side} negative=#{count} native_guest=NOT_EXECUTED"
