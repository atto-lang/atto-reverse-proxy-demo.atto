#!/usr/bin/env python3
"""Source-free mutation regression for the native runner security hold."""
from __future__ import annotations

import unittest
from pathlib import Path
import runpy

verify_quarantined_job = runpy.run_path(
    str(Path(__file__).with_name("workflow_quarantine.py"))
)["verify_quarantined_job"]

JOB = "native-contracts"
VALID = """name: Native contracts
on:
  pull_request:
permissions:
  contents: read
jobs:
  native-contracts:
    # Do not schedule PR code on privileged self-hosted runners.
    if: ${{ false }}
    runs-on: [self-hosted, linux, x64, oreslang-jdk25]
    timeout-minutes: 20
    steps:
      - name: Example
        run: |
          echo hello
"""

class QuarantineMutationTests(unittest.TestCase):
    def assert_rejected(self, source: str):
        with self.assertRaises(AssertionError):
            verify_quarantined_job(source, JOB)

    def test_valid(self):
        verify_quarantined_job(VALID, JOB)

    def test_comment_only_false(self):
        self.assert_rejected(VALID.replace('    if: ${{ false }}', '    # if: ${{ false }}'))

    def test_live_job_with_false_comment(self):
        self.assert_rejected(VALID.replace('    if: ${{ false }}',
                                           '    if: ${{ true }}\n    # if: ${{ false }}'))

    def test_step_level_false(self):
        self.assert_rejected(VALID.replace('    if: ${{ false }}',
                                           '      - name: Hidden\n        if: ${{ false }}'))

    def test_duplicate_false_then_true(self):
        self.assert_rejected(VALID.replace('    if: ${{ false }}',
                                           '    if: ${{ false }}\n    if: ${{ true }}'))

    def test_duplicate_true_then_false(self):
        self.assert_rejected(VALID.replace('    if: ${{ false }}',
                                           '    if: ${{ true }}\n    if: ${{ false }}'))

    def test_expression_instead_of_false(self):
        self.assert_rejected(VALID.replace('    if: ${{ false }}',
                                           '    if: ${{ github.actor == \'admin\' }}'))

    def test_multiline_condition(self):
        self.assert_rejected(VALID.replace('    if: ${{ false }}',
                                           '    if: >-\n      false'))

    def test_missing_job(self):
        self.assert_rejected(VALID.replace('  native-contracts:', '  different-job:'))

    def test_extra_job(self):
        self.assert_rejected(VALID + '\n  bypass:\n    runs-on: [self-hosted, linux, x64, oreslang-jdk25]\n    steps: []\n')

    def test_duplicate_jobs_section(self):
        self.assert_rejected(VALID + '\njobs:\n  bypass:\n    runs-on: ubuntu-latest\n')

    def test_second_jobs_key_with_comment(self):
        self.assert_rejected(VALID + '\njobs: # alternate active jobs\n  bypass:\n    runs-on: ubuntu-latest\n')

    def test_job_yaml_alias(self):
        self.assert_rejected(VALID.replace('  native-contracts:', '  native-contracts: *active_job'))

    def test_job_yaml_merge(self):
        self.assert_rejected(VALID.replace('    if: ${{ false }}', '    <<: *unsafe\n    if: ${{ false }}'))

    def test_wrong_runner(self):
        self.assert_rejected(VALID.replace('self-hosted, linux, x64, oreslang-jdk25', 'ubuntu-24.04'))

    def test_duplicate_runner(self):
        self.assert_rejected(VALID.replace('    runs-on: [self-hosted, linux, x64, oreslang-jdk25]',
                                           '    runs-on: ubuntu-latest\n    runs-on: [self-hosted, linux, x64, oreslang-jdk25]'))

    def test_false_appears_only_in_run_scalar(self):
        self.assert_rejected(VALID.replace('    if: ${{ false }}', '    # no condition').replace('          echo hello', '          echo if: ${{ false }}'))

    def test_overindented_false(self):
        self.assert_rejected(VALID.replace('    if: ${{ false }}', '      if: ${{ false }}'))

    def test_extra_matrix_strategy(self):
        self.assert_rejected(VALID.replace('    if: ${{ false }}', '    strategy:\n      matrix: {}\n    if: ${{ false }}'))

    def test_other_workflow_id(self):
        with self.assertRaises(AssertionError):
            verify_quarantined_job(VALID, 'actor-ingress')

if __name__ == '__main__':
    unittest.main()
