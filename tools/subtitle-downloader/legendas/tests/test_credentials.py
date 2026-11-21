"""Simulated Secret Service: tests no real user credentials."""
import json
import subprocess
import unittest
from unittest.mock import patch

import credentials


class FakeTool:
    def __init__(self):
        self.saved = ''
        self.calls = []
        self.broken = False
        self.absent_returns_one = False

    def run(self, command, input=None, capture_output=True, text=True, timeout=25, check=False):
        operation = command[1]
        self.calls.append((command, input))
        if self.broken:
            return subprocess.CompletedProcess(command, 1, stdout='', stderr='locked service')
        if operation == 'store':
            self.saved = input
            return subprocess.CompletedProcess(command, 0, stdout='', stderr='')
        if operation == 'lookup':
            if not self.saved and self.absent_returns_one:
                return subprocess.CompletedProcess(command, 1, stdout='', stderr='')
            return subprocess.CompletedProcess(command, 0, stdout=self.saved, stderr='')
        if operation == 'clear':
            self.saved = ''
            return subprocess.CompletedProcess(command, 0, stdout='', stderr='')
        raise AssertionError('Unexpected operation')


class CredentialsTests(unittest.TestCase):
    def setUp(self):
        self.tool = FakeTool()
        self.fake_which = patch('credentials.shutil.which', return_value='/usr/bin/secret-tool')
        self.fake_run = patch('credentials.subprocess.run', side_effect=self.tool.run)
        self.fake_which.start()
        self.fake_run.start()

    def tearDown(self):
        self.fake_run.stop()
        self.fake_which.stop()

    def test_save_lookup_and_clear_without_argv_exposure(self):
        credentials.save_credentials('wolf', 'minha senha especial!', 'minha-api')
        self.assertEqual(credentials.load_credentials()['password'], 'minha senha especial!')
        self.assertEqual(credentials.safe_status(), {'stored': True, 'username': 'wolf', 'error': ''})
        for command, contents in self.tool.calls:
            self.assertNotIn('minha senha especial!', ' '.join(command))
            self.assertNotIn('minha-api', ' '.join(command))
            if command[1] == 'store':
                self.assertEqual(json.loads(contents)['password'], 'minha senha especial!')
        credentials.clear_credentials()
        self.assertIsNone(credentials.load_credentials())

    def test_unavailable_secret_service_fails_closed(self):
        self.tool.broken = True
        with self.assertRaises(credentials.CredentialStoreError):
            credentials.save_credentials('wolf', 'minha senha')
        status = credentials.safe_status()
        self.assertFalse(status['stored'])
        self.assertIn('chaveiro', status['error'].lower())

    def test_no_secret_tool_does_not_fallback_to_file(self):
        with patch('credentials.shutil.which', return_value=None):
            with self.assertRaises(credentials.CredentialStoreError):
                credentials.save_credentials('wolf', 'senha')

    def test_no_entry_returns_one_without_error(self):
        self.tool.absent_returns_one = True
        self.assertIsNone(credentials.load_credentials())
        self.assertEqual(credentials.safe_status()['error'], '')
        self.assertFalse(credentials.safe_status()['stored'])

    def test_no_password_rejected(self):
        with self.assertRaisesRegex(ValueError, 'usuário e senha'):
            credentials.save_credentials('wolf', '')

    def test_no_secret_exposed_by_status(self):
        credentials.save_credentials('wolf', 'segredo123', 'apikey123')
        status_dump = repr(credentials.safe_status())
        self.assertNotIn('segredo123', status_dump)
        self.assertNotIn('apikey123', status_dump)


if __name__ == '__main__':
    unittest.main()
