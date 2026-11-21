"""Mocked providers: no external connections, quota, account, or downloads."""
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest.mock import patch

import backend


class FakeLanguage:
    @classmethod
    def fromietf(cls, tag):
        return tag


class FakeVideo:
    @classmethod
    def fromname(cls, name):
        obj = cls()
        obj.title = 'Avengers' if 'avengers' in name.lower() else 'Filme'
        obj.year = None
        obj.external_ids = {}
        obj.hashes = {}
        return obj


class FakeSubtitle:
    def __init__(self, title, ident, provider_name):
        self.title = title
        self.id = ident
        self.year = 2012 if '2012' in title else 2019
        self.provider_name = provider_name
        self.info = f'{title} BluRay 1080p'
        self.content = None
        self.moviehash_match = False

    def get_matches(self, video):
        return {'title'} if 'Avengers' in self.title else set()

    @property
    def text(self):
        return self.content.decode('utf-8')


class FakePodnapisiProvider:
    calls = []

    def __init__(self, **kwargs):
        self.initialized = False

    def initialize(self):
        self.initialized = True

    def terminate(self):
        self.initialized = False

    def query(self, language, keyword, **kwargs):
        self.calls.append((keyword, kwargs))
        return [FakeSubtitle('The Avengers 2012', 'p1', 'podnapisi'),
                FakeSubtitle('Avengers Endgame', 'p2', 'podnapisi'),
                FakeSubtitle('Os Vingadores 2012', 'p3', 'podnapisi')]

    def list_subtitles(self, video, languages):
        self.calls.append(('list', {}))
        return [FakeSubtitle('Avengers Endgame', 'p2', 'podnapisi')]

    def download_subtitle(self, subtitle):
        subtitle.content = b'1\n00:00:00,000 --> 00:00:01,000\nOla!\n'


class FakeOSProvider(FakePodnapisiProvider):
    def __init__(self, username=None, password=None, apikey=None, **kwargs):
        super().__init__(**kwargs)
        self.username = username
        self.password = password
        self.apikey = apikey

    def query(self, languages, **kwargs):
        self.calls.append((kwargs.get('query'), kwargs))
        return [FakeSubtitle('Avengers Infinity War', 'o1', 'opensubtitlescom')]

    def list_subtitles(self, video, languages):
        return self.query(languages, query=video.title)

    def download_subtitle(self, subtitle):
        super().download_subtitle(subtitle)


class BackendTests(unittest.TestCase):
    def setUp(self):
        self.fake_babel = types.ModuleType('babelfish')
        self.fake_babel.Language = FakeLanguage
        self.fake_sub = types.ModuleType('subliminal')
        self.fake_sub.region = types.SimpleNamespace(configure=lambda *args, **kwargs: None)
        self.fake_sub.Video = FakeVideo
        self.fake_sub.scan_video = lambda path: FakeVideo.fromname(path)
        self.fake_sub.compute_score = lambda sub, vid: 850
        self.fake_pkg = types.ModuleType('subliminal.providers')
        self.fake_pkg.__path__ = []
        self.fake_pod = types.ModuleType('subliminal.providers.podnapisi')
        self.fake_pod.PodnapisiProvider = FakePodnapisiProvider
        self.fake_os = types.ModuleType('subliminal.providers.opensubtitlescom')
        self.fake_os.OpenSubtitlesComProvider = FakeOSProvider
        self.patch = patch.dict(sys.modules, {'babelfish': self.fake_babel,
            'subliminal': self.fake_sub, 'subliminal.providers': self.fake_pkg,
            'subliminal.providers.podnapisi': self.fake_pod,
            'subliminal.providers.opensubtitlescom': self.fake_os})
        self.patch.start()
        FakePodnapisiProvider.calls = []
        FakeOSProvider.calls = []

    def tearDown(self):
        self.patch.stop()

    def test_title_without_year_is_direct_keyword_query_both_providers(self):
        engine = backend.SubtitleEngine()
        with tempfile.TemporaryDirectory() as tmp:
            result = engine.search({'source': 'title', 'title': 'avengers',
                                    'output_dir': tmp, 'language': 'pt-BR'})
            self.assertEqual(FakePodnapisiProvider.calls[0][0], 'avengers')
            self.assertEqual(FakeOSProvider.calls[0][0], 'avengers')
            self.assertEqual(len(result['entries']), 4)
            self.assertIn('Os Vingadores 2012', [row['title'] for row in result['entries']])
        engine.close()

    def test_year_is_not_required_or_used_as_strict_filter(self):
        engine = backend.SubtitleEngine()
        with tempfile.TemporaryDirectory() as tmp:
            result = engine.search({'source': 'title', 'title': 'Avengers 2012',
                                    'provider': 'podnapisi', 'output_dir': tmp})
            self.assertEqual(FakePodnapisiProvider.calls[0][0], 'Avengers')
            self.assertNotIn('year', FakePodnapisiProvider.calls[0][1])
            self.assertEqual(len(result['entries']), 3)
        engine.close()

    def test_file_search_and_download_and_refuse_overwrite(self):
        engine = backend.SubtitleEngine()
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'Avengers Endgame.mkv'
            path.write_bytes(b'placeholder video file')
            result = engine.search({'source': 'file', 'path': str(path), 'language': 'pt-BR',
                                    'provider': 'podnapisi'})
            self.assertEqual(len(result['entries']), 1)
            saved = Path(engine.download({'index': 0}))
            self.assertEqual(saved.name, 'Avengers Endgame.pt-BR.srt')
            self.assertIn('Ola!', saved.read_text())
            with self.assertRaises(FileExistsError):
                engine.download({'index': 0})
        engine.close()

    def test_os_requires_login_for_download_not_for_search(self):
        engine = backend.SubtitleEngine()
        with tempfile.TemporaryDirectory() as tmp:
            result = engine.search({'source': 'title', 'title': 'avengers',
                                    'provider': 'opensubtitlescom', 'output_dir': tmp})
            self.assertEqual(len(result['entries']), 1)
            with self.assertRaisesRegex(ValueError, 'usuário e senha'):
                engine.download({'index': 0})
        engine.close()

    def test_os_logged_in_can_download(self):
        engine = backend.SubtitleEngine()
        with tempfile.TemporaryDirectory() as tmp:
            result = engine.search({'source': 'title', 'title': 'avengers',
                                    'provider': 'opensubtitlescom', 'output_dir': tmp,
                                    'username': 'usuario_teste', 'password': 'segredo_teste'})
            self.assertEqual(len(result['entries']), 1)
            saved = engine.download({'index': 0})
            self.assertTrue(Path(saved).is_file())
            self.assertEqual(Path(saved).name, 'Avengers Infinity War 2019.pt-BR.srt')
        engine.close()

    def test_saved_login_used_automatically_for_opensubtitles(self):
        engine = backend.SubtitleEngine()
        with tempfile.TemporaryDirectory() as tmp:
            with patch('backend.load_credentials', return_value={
                'username': 'usuario_salvo', 'password': 'senha_salva', 'apikey': 'chave_teste'
            }):
                result = engine.search({'source': 'title', 'title': 'avengers',
                    'provider': 'opensubtitlescom', 'output_dir': tmp})
            self.assertEqual(len(result['entries']), 1)
            provider = engine.providers['opensubtitlescom']
            self.assertEqual(provider.username, 'usuario_salvo')
            self.assertEqual(provider.password, 'senha_salva')
            self.assertEqual(provider.apikey, 'chave_teste')
            self.assertTrue(Path(engine.download({'index': 0})).exists())
        engine.close()

    def test_temporary_credentials_override_saved_login(self):
        engine = backend.SubtitleEngine()
        with tempfile.TemporaryDirectory() as tmp:
            with patch('backend.load_credentials', side_effect=AssertionError('Não deve ler o chaveiro')):
                engine.search({'source': 'title', 'title': 'avengers',
                    'provider': 'opensubtitlescom', 'output_dir': tmp,
                    'username': 'temporario', 'password': 'senhatemporaria'})
            self.assertEqual(engine.providers['opensubtitlescom'].username, 'temporario')
        engine.close()

    def test_quick_uses_both_providers_when_login_is_saved(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'Avengers Endgame.mkv'
            path.write_bytes(b'placeholder')
            with patch('backend.load_credentials', return_value={
                'username': 'wolf', 'password': 'secreto', 'apikey': ''
            }), patch('backend.alert'):
                code = backend.quick(str(path))
            self.assertEqual(code, 0)
            self.assertTrue(FakeOSProvider.calls)
            self.assertTrue(FakePodnapisiProvider.calls)
            self.assertTrue(Path(tmp, 'Avengers Endgame.pt-BR.srt').exists())

    def test_quick_falls_back_when_opensubtitles_download_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'Avengers Endgame.mkv'
            path.write_bytes(b'placeholder')
            with patch('backend.load_credentials', return_value={
                'username': 'wolf', 'password': 'secreto', 'apikey': ''
            }), patch.object(FakeOSProvider, 'download_subtitle',
                side_effect=RuntimeError('download rejected')), patch('backend.alert'):
                code = backend.quick(str(path))
            self.assertEqual(code, 0)
            self.assertTrue(Path(tmp, 'Avengers Endgame.pt-BR.srt').exists())

    def test_quick_without_credentials_uses_only_podnapisi(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'Avengers Endgame.mkv'
            path.write_bytes(b'placeholder')
            with patch('backend.load_credentials', return_value=None), patch('backend.alert'):
                code = backend.quick(str(path))
            self.assertEqual(code, 0)
            self.assertFalse(FakeOSProvider.calls)

    def test_provider_errors_preserve_other_results(self):
        engine = backend.SubtitleEngine()
        with tempfile.TemporaryDirectory() as tmp:
            with patch.object(FakeOSProvider, 'query', side_effect=ConnectionError('offline')):
                result = engine.search({'source': 'title', 'title': 'avengers',
                                        'output_dir': tmp, 'provider': 'all'})
            self.assertEqual(len(result['entries']), 3)
            self.assertTrue(any('OpenSubtitles.com' in warning for warning in result['warnings']))
        engine.close()


if __name__ == '__main__':
    unittest.main()
