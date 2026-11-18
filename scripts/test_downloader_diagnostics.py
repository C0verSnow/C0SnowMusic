import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

source = Path(__file__).resolve().parents[1] / 'MusicApp/Resources/Python/c0snow_downloader.py'
spec = importlib.util.spec_from_file_location('downloader', source)
downloader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(downloader)


class DownloaderDiagnosticsTests(unittest.TestCase):
    def test_actual_logger_records_stages_and_redacts_credentials_before_disk_write(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            logger = downloader._DiagnosticLogger(root)
            logger.debug('[youtube] abcdefghijk: Downloading webpage')
            logger.warning('Retrying https://user:password@media.test/audio?signature=private-signature')
            logger.error('Authorization: Bearer device-secret\nCookie: session=cookie-secret')
            raw = (root / 'diagnostics.jsonl').read_text()
            events = [json.loads(line) for line in raw.splitlines()]
            self.assertEqual(len(events), 3)
            self.assertIn('Downloading webpage', events[0]['message'])
            self.assertEqual(events[1]['stage'], 'YouTube warning')
            self.assertGreater(events[0]['timestamp'], 0)
            self.assertIn('media.test', raw)
            for value in ['password', 'private-signature', 'device-secret', 'cookie-secret']:
                self.assertNotIn(value, raw)


if __name__ == '__main__':
    unittest.main()
