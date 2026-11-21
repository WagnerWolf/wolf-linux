import tempfile
import unittest
from pathlib import Path
from helpers import clean_title, movie_guess_name, output_path


class HelpersTests(unittest.TestCase):
    def test_no_directory_traversal_in_title(self):
        with tempfile.TemporaryDirectory() as temp:
            dest = output_path('title', '../../Filme: 2014', 'pt-BR', temp)
            self.assertEqual(dest.parent, Path(temp))
            self.assertEqual(dest.name, 'Filme 2014.pt-BR.srt')

    def test_file_source_uses_stem(self):
        with tempfile.TemporaryDirectory() as temp:
            video = Path(temp) / 'Filme 2014.mkv'
            video.touch()
            self.assertEqual(output_path('file', str(video), 'pt-BR').name, 'Filme 2014.pt-BR.srt')

    def test_invalid_language_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaises(ValueError):
                output_path('title', 'Filme', '../bad', temp)

    def test_guess_name_adds_extension_only_when_needed(self):
        self.assertEqual(movie_guess_name('Interstellar 2014'), 'Interstellar 2014.mkv')
        self.assertEqual(movie_guess_name('Serie S01E01.mp4'), 'Serie S01E01.mp4')

    def test_empty_title_rejected(self):
        with self.assertRaises(ValueError):
            clean_title('////')

    def test_nonexistent_file_rejected(self):
        with self.assertRaises(ValueError):
            output_path('file', '/unlikely/nope.mkv', 'pt-BR')


if __name__ == '__main__':
    unittest.main()
