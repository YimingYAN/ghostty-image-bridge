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

    def test_plain_mosh_destinations(self):
        with patch.object(transfer, 'HOSTS', {'you@example.com', 'devbox'}):
            for command, expected in (
                ('mosh you@example.com', 'you@example.com'),
                ('/opt/homebrew/bin/mosh-client -# you@example.com | 192.0.2.1 60001', 'you@example.com'),
                ('mosh-client "-# devbox |" 2001:db8::1 60002', 'devbox'),
            ):
                with self.subTest(command=command):
                    self.assertEqual(transfer.target(command), expected)

    def test_reject_unidentified_or_untrusted_mosh(self):
        with patch.object(transfer, 'HOSTS', {'you@example.com', '-bad'}):
            for command in (
                'mosh-client 192.0.2.1 60001',
                'mosh-client -# attacker@example.com | 192.0.2.1 60001',
                'mosh-client -# you@example.com | invalid 60001',
                'mosh-client -# you@example.com | 192.0.2.1 70000',
                'mosh-client -# you@example.com | 192.0.2.1 0',
                'mosh-client -# --ssh=custom you@example.com | 192.0.2.1 60001',
                'mosh-client -# you@example.com command | 192.0.2.1 60001',
                'mosh --ssh=custom you@example.com', 'mosh -bad',
            ):
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

class FileTransferTests(unittest.TestCase):
    def test_upload_preserves_extension_and_uses_safe_unique_name(self):
        with patch.object(transfer, 'HOSTS', {'host'}), patch.object(transfer, 'run', side_effect=['/home/user/.cache/clipboard-images', '']) as run:
            remote = transfer.upload('host', '/tmp/my report;$(bad).pdf')
        self.assertTrue(remote.endswith('-my_report___bad_.pdf'))
        self.assertEqual(run.call_args.args[0][-2], '/tmp/my report;$(bad).pdf')
        self.assertEqual(run.call_args.args[0][-1], 'host:' + remote)

    def test_multiple_original_files_are_never_deleted(self):
        import tempfile
        with tempfile.TemporaryDirectory() as directory:
            paths = [Path(directory) / name for name in ('one.pdf', 'two.zip')]
            for path in paths:
                path.write_bytes(b'original')
            with patch.object(transfer.sys, 'argv', ['transfer.py', '--files', 'pane', '123', *map(str, paths)]), patch.object(transfer, 'context', return_value=('pane', '123')), patch.object(transfer, 'run', return_value='ssh host'), patch.object(transfer, 'target', return_value='host'), patch.object(transfer, 'upload', side_effect=['/remote/one.pdf', '/remote/two.zip']) as upload, patch.object(transfer, 'apple') as apple:
                transfer.main()
            self.assertEqual(upload.call_count, 2)
            self.assertIn('/remote/one.pdf /remote/two.zip ', apple.call_args.args[0])
            for path in paths:
                self.assertEqual(path.read_bytes(), b'original')

    def test_failed_file_upload_keeps_original(self):
        import tempfile
        with tempfile.NamedTemporaryFile() as file:
            with patch.object(transfer.sys, 'argv', ['transfer.py', '--files', 'pane', '123', file.name]), patch.object(transfer, 'context', return_value=('other', '123')), patch.object(transfer, 'apple') as apple:
                with self.assertRaises(RuntimeError):
                    transfer.main()
                self.assertTrue(Path(file.name).exists())
                apple.assert_not_called()

if __name__ == '__main__':
    unittest.main()
