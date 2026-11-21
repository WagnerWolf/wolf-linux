"""Safe names and output locations for Wolf Subtitle Downloader."""
from __future__ import annotations

import re
from pathlib import Path

VIDEO_SUFFIXES = {'.mkv', '.mp4', '.avi', '.mov', '.webm', '.m4v', '.wmv', '.mpg', '.mpeg', '.ts'}
LANGUAGE_CODES = {'pt-BR', 'pt-PT', 'en'}


def clean_title(title: str) -> str:
    """Clean a typed title for local use without path traversal."""
    value = re.sub(r'[\\/:*?"<>|\x00-\x1f]+', ' ', title).strip().strip('.')
    value = re.sub(r'\s+', ' ', value)
    value = value.lstrip(' .')
    if not value or value in {'.', '..'}:
        raise ValueError('Informe um título válido.')
    return value[:150].rstrip(' .')


def language_tag(language: str) -> str:
    if language not in LANGUAGE_CODES:
        raise ValueError('Idioma não suportado.')
    return language


def movie_guess_name(title: str) -> str:
    """Provide a plausible extension so the video name parser can infer movie metadata."""
    value = clean_title(title)
    if Path(value).suffix.lower() in VIDEO_SUFFIXES:
        return value
    return f'{value}.mkv'


def output_path(source: str, value: str, language: str, output_dir: str = '') -> Path:
    tag = language_tag(language)
    if source == 'file':
        path = Path(value).expanduser()
        if not path.is_file():
            raise ValueError('O arquivo de vídeo não existe.')
        if path.suffix.lower() not in VIDEO_SUFFIXES:
            raise ValueError('Selecione um arquivo de vídeo compatível.')
        return path.with_name(f'{path.stem}.{tag}.srt')
    if source == 'title':
        folder = Path(output_dir).expanduser()
        if not folder.is_dir():
            raise ValueError('Escolha uma pasta existente para salvar a legenda.')
        name = clean_title(value)
        if Path(name).suffix.lower() in VIDEO_SUFFIXES:
            name = Path(name).stem
        return folder / f'{name}.{tag}.srt'
    raise ValueError('Modo de busca desconhecido.')
