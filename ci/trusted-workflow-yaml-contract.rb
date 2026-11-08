# frozen_string_literal: true
# Source-only, fail-closed structural admission for an independently reviewed
# privileged workflow. NOT live GitHub governance or release authority.
require 'psych'
require 'digest'

abort 'usage: ruby trusted-workflow-yaml-contract.rb WORKFLOW.yml forward|reverse' unless ARGV.length == 2
file, side = ARGV
identity = {
  'forward' => ['1429955596', 'fe46a4cac8c3cbedfaa5d872bc0e6348974141b5'],
  'reverse' => ['1429954649', '1a667fcd4481e3511e0cfa1008e855d96540c200']
}[side]
abort 'unknown proxy side' unless identity
repo_id, source_sha = identity

def refuse(reason)
  warn "TRUSTED_YAML_REJECTED: #{reason}"
  exit 1
end

def scalar(node, where)
  refuse("non-scalar #{where}") unless node.is_a?(Psych::Nodes::Scalar) && node.anchor.nil? && node.tag.nil?
  node.value
end

def mapping(node, where)
  refuse("non-mapping #{where}") unless node.is_a?(Psych::Nodes::Mapping) && node.anchor.nil? && node.tag.nil?
  refuse("odd mapping at #{where}") unless node.children.length.even?
  result = {}
  node.children.each_slice(2) do |key, value|
    k = scalar(key, "#{where} key")
    refuse("duplicate or merge key #{where}.#{k}") if k == '<<' || result.key?(k)
    result[k] = value
  end
  result
end

def sequence(node, where)
  refuse("non-sequence #{where}") unless node.is_a?(Psych::Nodes::Sequence) && node.anchor.nil? && node.tag.nil?
  node.children
end

def keys_eq(hash, allowed, where)
  refuse("unexpected/missing keys in #{where}: #{hash.keys.inspect}") unless hash.keys.sort == allowed.sort
end

def equals(node, expected, where)
  actual = scalar(node, where)
  refuse("mismatched #{where}") unless actual == expected
end

begin
  bytes = File.binread(file).force_encoding('UTF-8')
  refuse('oversized or missing YAML') unless bytes.bytesize.between?(1, 100_000)
  refuse('unexpected encoding') unless bytes.valid_encoding? && !bytes.include?("\0")
  doc = Psych.parse(bytes, filename: file)
  refuse('no YAML document') unless doc&.root
  # Reject aliases, tags, anchors and YAML merges: no ambiguous validation.
  reject_unsafe = lambda do |node|
    refuse('alias/anchor/tag not permitted') if node.is_a?(Psych::Nodes::Alias) ||
      (node.respond_to?(:anchor) && node.anchor) || (node.respond_to?(:tag) && node.tag)
    node.children.each { |child| reject_unsafe.call(child) } if node.respond_to?(:children) && node.children
  end
  reject_unsafe.call(doc)
  stream = Psych.parse_stream(bytes)
  refuse('multiple YAML documents') unless stream.children.length == 1
rescue Psych::SyntaxError, SystemCallError, ArgumentError => e
  refuse("parse error #{e.class}")
end

root = mapping(doc.root, 'root')
keys_eq(root, %w[name on permissions env defaults jobs], 'root')
equals(root.fetch('name'), "Trusted Frozen #{side.capitalize} Native Admission", 'workflow name')
trigger = mapping(root.fetch('on'), 'on')
keys_eq(trigger, ['workflow_dispatch'], 'trigger')
refuse('workflow_dispatch takes inputs') unless scalar(trigger['workflow_dispatch'], 'dispatch') == ''
permission = mapping(root.fetch('permissions'), 'permissions')
keys_eq(permission, ['contents'], 'workflow permissions')
equals(permission.fetch('contents'), 'read', 'contents permission')

safe_env = {
  'LD_PRELOAD'=>'', 'LD_LIBRARY_PATH'=>'', 'LD_AUDIT'=>'', 'LD_DEBUG'=>'',
  'LD_ORIGIN_PATH'=>'', 'BASH_ENV'=>'', 'ENV'=>'', 'JAVA_TOOL_OPTIONS'=>'',
  'JDK_JAVA_OPTIONS'=>'', '_JAVA_OPTIONS'=>'', 'CLASSPATH'=>'',
  'NODE_OPTIONS'=>'', 'NODE_PATH'=>'', 'NODE_EXTRA_CA_CERTS'=>'',
  'NODE_TLS_REJECT_UNAUTHORIZED'=>'1', 'GIT_CONFIG_COUNT'=>'0',
  'GIT_CONFIG_PARAMETERS'=>'', 'GIT_CONFIG_GLOBAL'=>'/dev/null',
  'GIT_CONFIG_SYSTEM'=>'/dev/null'
}
env = mapping(root.fetch('env'), 'env')
keys_eq(env, safe_env.keys, 'root env')
safe_env.each { |key, value| equals(env[key], value, "env.#{key}") }

shell = '/bin/bash --noprofile --norc -p -e -o pipefail {0}'
defaults = mapping(root.fetch('defaults'), 'defaults')
keys_eq(defaults, ['run'], 'defaults')
run_defaults = mapping(defaults.fetch('run'), 'defaults.run')
keys_eq(run_defaults, ['shell'], 'defaults.run')
equals(run_defaults.fetch('shell'), shell, 'default shell')

jobs = mapping(root.fetch('jobs'), 'jobs')
keys_eq(jobs, %w[protected-main-preflight native-contracts], 'jobs')
expected_if = "github.event_name == 'workflow_dispatch' && github.repository_id == '#{repo_id}' && github.ref == 'refs/heads/main' && github.ref_protected == true"
checkout = 'actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09'
# Reviewed ordered step names. An added shell step or reordered execution
# is not admitted by merely preserving the runner and trigger guards.
reviewed_steps = {
  'forward' => {
    'protected-main-preflight' => [
      "Verify live protected default branch and control-plane SHA",
    ],
    'native-contracts' => [
      "Recheck protected private main before frozen checkout",
      "Checkout exact frozen release candidate tree",
      "Verify exact frozen source HEAD, JDK25 and administrator-approved runtime",
      "Compile complete frozen Oreslang source inventory",
      "Execute every standalone contract in frozen tree",
      "Compiler-check entrypoint",
      "Compiler-check configuration path admission",
      "Compiler-check YAML parser",
      "Compiler-check routing policy",
      "Compiler-check middleware policy",
      "Compiler-check generation coordinator",
      "Compiler-check native YAML contract",
      "Compiler-check native generation contract",
      "Compiler-check native middleware contract",
      "Compiler-check canonical path contract",
      "Execute canonical configuration path contract",
      "Execute YAML / routing / policy contract",
      "Execute generation epoch / rollback contract",
      "Execute independent middleware snapshot contract",
      "Compiler-check HTTP metadata admission and header filtering",
      "Compiler-check symbolic service and CONNECT actor gate",
      "Execute symbolic service and CONNECT actor-gate contracts",
      "Compiler-check native slot lifecycle, middleware manifest and data layouts",
      "Compiler-check all security and slot regression vectors",
      "Execute complete Oreslang safety contracts",
      "Compiler-check lexical admission regression",
      "Execute lexical admission regression",
      "Compiler-check and execute native policy performance workload",
    ],
  },
  'reverse' => {
    'protected-main-preflight' => [
      "Verify live protected default branch and control-plane SHA",
    ],
    'native-contracts' => [
      "Recheck protected private main before frozen checkout",
      "Checkout exact frozen release candidate tree",
      "Verify exact frozen source HEAD, JDK25 and administrator-approved runtime",
      "Compile complete frozen Oreslang source inventory",
      "Execute every standalone contract in frozen tree",
      "Compiler-check entrypoint",
      "Compiler-check configuration path admission",
      "Compiler-check YAML parser",
      "Compiler-check routing policy",
      "Compiler-check middleware policy",
      "Compiler-check generation coordinator",
      "Compiler-check native YAML contract",
      "Compiler-check native generation contract",
      "Compiler-check native middleware contract",
      "Compiler-check canonical path contract",
      "Execute canonical configuration path contract",
      "Execute YAML / routing / policy contract",
      "Execute generation epoch / rollback contract",
      "Execute independent middleware snapshot contract",
      "Compiler-check HTTP metadata admission and header filtering",
      "Compiler-check native slot lifecycle, middleware manifest and data layouts",
      "Compiler-check all security and slot regression vectors",
      "Compiler-check opt-in reverse ingress and TCP smoke",
      "Execute loopback ingress status and framing smoke",
      "Fail closed if reverse ingress configuration vanishes",
      "Execute complete Oreslang safety contracts",
      "Compiler-check lexical admission regression",
      "Execute lexical admission regression",
      "Compiler-check and execute native policy performance workload",
    ],
  },
}
uses_count = 0
jobs.each do |job_name, job_node|
  job = mapping(job_node, "jobs.#{job_name}")
  expected_keys = %w[if runs-on timeout-minutes steps]
  expected_keys << 'needs' if job_name == 'native-contracts'
  keys_eq(job, expected_keys, job_name)
  condition = scalar(job['if'], "#{job_name}.if").gsub(/\s+/, ' ').strip
  refuse("unsafe if for #{job_name}") unless condition == expected_if
  equals(job['timeout-minutes'], job_name == 'native-contracts' ? '20' : '3', "#{job_name}.timeout")
  if job_name == 'native-contracts'
    equals(job['needs'], 'protected-main-preflight', 'native needs')
    runs_on = mapping(job.fetch('runs-on'), 'native runs-on')
    keys_eq(runs_on, %w[group labels], 'native runs-on')
    equals(runs_on['group'], 'oreslang-trusted-native', 'runner group')
    labels = sequence(runs_on['labels'], 'native labels').map { |item| scalar(item, 'runner label') }
    refuse('runner labels drift') unless labels == %w[self-hosted linux x64 oreslang-jdk25]
  else
    equals(job['runs-on'], 'ubuntu-24.04', 'preflight runner')
  end
  steps = sequence(job.fetch('steps'), "#{job_name}.steps")
  refuse('empty steps') if steps.empty?
  expected_names = reviewed_steps.fetch(side).fetch(job_name)
  refuse('privileged step count drift') unless steps.length == expected_names.length
  steps.each_with_index do |step_node, idx|
    step = mapping(step_node, "#{job_name}.step[#{idx}]")
    refuse('unexpected step keys') unless (step.keys - %w[name shell env run uses with]).empty?
    refuse('missing step name') unless step.key?('name')
    equals(step['name'], expected_names.fetch(idx), "reviewed step order #{idx}")
    equals(step['shell'], shell, 'step shell') if step.key?('shell')
    has_run = step.key?('run')
    has_uses = step.key?('uses')
    refuse('step must be run XOR uses') unless has_run != has_uses
    if has_run
      refuse('blank run') if scalar(step['run'], 'step run').strip.empty?
      refuse('run step with action inputs') if step.key?('with')
    else
      uses_count += 1
      refuse('unreviewed action') unless job_name == 'native-contracts' && scalar(step['uses'], 'uses') == checkout
      refuse('action with executable shell') if step.key?('shell') || step.key?('env')
      with = mapping(step.fetch('with'), 'checkout with')
      keys_eq(with, %w[persist-credentials set-safe-directory ref], 'checkout with')
      equals(with['persist-credentials'], 'false', 'persist credentials')
      equals(with['set-safe-directory'], 'false', 'safe directory')
      equals(with['ref'], source_sha, 'frozen source ref')
    end
    if step.key?('env')
      step_env = mapping(step['env'], 'step env')
      (step_env.keys & safe_env.keys).each { |name| refuse("step override #{name}") }
      step_env.each { |name, value| scalar(value, "step env #{name}") }
    end
  end
end
refuse('missing or duplicated checkout') unless uses_count == 1
# Fail closed on changes to any executable run body, action input or comment
# within the reviewed trusted workflow. A matching step name is NOT a code pin.
# This is a source-only Git blob identity check, not a live GitHub API verdict.
reviewed_blobs = {
  'forward' => 'a1d1af6bd6786b2abc456ae9fd30ee892775f969',
  'reverse' => '46b07f2ca60b742e03b0a28ac5736a5be1df68ff'
}
actual_blob = Digest::SHA1.hexdigest("blob #{bytes.bytesize}\0".b + bytes.b)
refuse('unreviewed trusted workflow blob or command drift') unless actual_blob == reviewed_blobs.fetch(side)
puts "SOURCE_FREE_TRUSTED_YAML_SEMANTICS_PASS side=#{side} native_guest=NOT_EXECUTED live_protection=NOT_VERIFIED"
