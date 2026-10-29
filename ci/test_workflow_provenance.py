#!/usr/bin/env python3
"""Execute workflow provenance Bash against synthetic tools, never guest code."""
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest

ROOT = Path(__file__).resolve().parent.parent


def provenance_script():
    workflow = (ROOT / '.github/workflows/native-contracts.yml').read_text()
    section = workflow.split('      - name: Fail closed on exact source and approved native runner provenance\n', 1)[1]
    block = section.split('        run: |\n', 1)[1].split('      - name:', 1)[0]
    return textwrap.dedent(block)


class ProvenanceChecks(unittest.TestCase):
    def execute(self, launcher_text, digest=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary = root / 'bin'
            binary.mkdir()
            runner = root / 'runner'
            runner.mkdir()
            launcher = binary / 'oreslang'
            launcher.write_text(launcher_text)
            launcher.chmod(0o700)
            java = binary / 'java'
            java.write_text('#!/bin/bash\necho "java.specification.version = 25" >&2\n')
            java.chmod(0o700)
            git = binary / 'git'
            git.write_text('#!/bin/bash\ncase "$*" in\n "rev-parse HEAD") echo fixture-head;;\n "rev-parse HEAD^{tree}") echo fixture-tree;;\n *) exit 1;;\nesac\n')
            git.chmod(0o700)
            marker = root / 'unapproved-execution'
            env = dict(os.environ, PATH=str(binary) + ':/usr/bin:/bin',
                       APPROVED_REPOSITORY_ID='1429954649',
                       EVENT_REPOSITORY_ID='1429954649', EVENT_NAME='pull_request',
                       EVENT_PR_HEAD_REPO_ID='1429954649',
                       EVENT_PR_BASE_REPO_ID='1429954649',
                       EXPECTED_SHA='fixture-head', RUNNER_OS='Linux',
                       RUNNER_ARCH='X64', RUNNER_NAME='synthetic-fixture',
                       RUNNER_TEMP=str(runner), GITHUB_RUN_ID='1',
                       GITHUB_RUN_ATTEMPT='1', MUTATION_MARKER=str(marker),
                       APPROVED_ORESLANG_SHA256=digest if digest is not None else
                       hashlib.sha256(launcher.read_bytes()).hexdigest())
            result = subprocess.run(['bash', '-c', provenance_script()], env=env,
                                    capture_output=True, text=True, timeout=10)
            return result, marker.exists()

    def test_approved_launcher(self):
        result, marker = self.execute('#!/bin/bash\nexit 0\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(marker)

    def test_wrong_digest(self):
        result, _ = self.execute('#!/bin/bash\nexit 0\n', '0' * 64)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('unapproved Oreslang launcher', result.stderr)

    def test_malformed_digest(self):
        result, _ = self.execute('#!/bin/bash\nexit 0\n', 'missing')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('administrator-approved', result.stderr)

    def test_probe_mutation_cannot_authorize_fallback(self):
        # An approved first probe replaces its executable and asks for fallback.
        # The old direct-launcher fallback would execute the changed bytes.
        launcher = '''#!/bin/bash
cat > "$0.next" <<'CHANGED'
#!/bin/bash
touch "$MUTATION_MARKER"
exit 0
CHANGED
chmod 700 "$0.next"
mv "$0.next" "$0"
exit 1
'''
        result, marker = self.execute(launcher)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertFalse(marker, 'unapproved fallback executable ran')
        self.assertIn('approved Oreslang launcher changed', result.stderr)


if __name__ == '__main__':
    unittest.main()
