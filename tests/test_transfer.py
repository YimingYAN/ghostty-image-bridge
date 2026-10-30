import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('transfer', Path(__file__).parents[1] / 'transfer.py')
transfer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(transfer)

class TransferTests(unittest.TestCase):
    def test_plain_allowed_destination(self):
        with patch.object(transfer, 'HOSTS', {'you@example.com'}):
            self.assertEqual(transfer.target('/usr/bin/ssh you@example.com'), 'you@example.com')

    def test_reject_ambiguous_and_untrusted_commands(self):
        with patch.object(transfer, 'HOSTS', {'you@example.com'}):
            for command in ('zsh', 'ssh attacker@example.com', 'ssh host echo you@example.com',
                            'ssh -p 22 you@example.com', 'ssh you@example.com command'):
                with self.subTest(command=command), self.assertRaises(RuntimeError):
                    transfer.target(command)

    def test_untrusted_upload_never_runs_a_command(self):
        with patch.object(transfer, 'HOSTS', set()), patch.object(transfer, 'run') as run:
            with self.assertRaises(RuntimeError):
                transfer.upload('attacker@example.com', '/tmp/test.png')
            run.assert_not_called()

    def test_unsafe_remote_path_never_reaches_scp(self):
        with patch.object(transfer, 'HOSTS', {'you@example.com'}):
            with patch.object(transfer, 'run', return_value='/tmp/a;evil') as run:
                with self.assertRaises(RuntimeError):
                    transfer.upload('you@example.com', '/tmp/test.png')
                self.assertEqual(run.call_count, 1)

if __name__ == '__main__':
    unittest.main()
