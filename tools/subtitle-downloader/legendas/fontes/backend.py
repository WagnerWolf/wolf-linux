#!/usr/bin/env python3
"""Worker JSON lines for Wolf Subtitle Downloader 0.3 preview3.

Title searches are genuinely fuzzy/substring provider queries, not video-file
lookups. Providers are isolated so a single offline/failed service does not
silently erase results from another service.
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
import traceback
import unicodedata
from pathlib import Path

from helpers import VIDEO_SUFFIXES, clean_title, language_tag, movie_guess_name, output_path
from credentials import (CredentialStoreError, clear_credentials, load_credentials,
                         safe_status, save_credentials)

PROVIDER_LABELS = {'podnapisi': 'Podnapisi', 'opensubtitlescom': 'OpenSubtitles.com'}


def say(event: str, **values) -> None:
    print(json.dumps({'event': event, **values}, ensure_ascii=False), flush=True)


def comparable(value: str) -> str:
    """Comparison only: keep originals intact for provider queries and UI."""
    value = unicodedata.normalize('NFKD', str(value or '')).casefold()
    value = ''.join(char for char in value if not unicodedata.combining(char))
    return ' '.join(re.findall(r'[a-z0-9]+', value))


def title_matches(query: str, title: str) -> bool:
    needle = comparable(query)
    return bool(needle) and needle in comparable(title)


def title_parts(value: str) -> tuple[str, int | None, int | None, int | None]:
    """Extract optional year and SxxExx without requiring either one."""
    value = clean_title(value)
    ep = re.search(r'\bS(\d{1,2})\s*E(\d{1,3})\b', value, re.I)
    year_match = re.search(r'(?<!\d)(19\d{2}|20\d{2})(?!\d)', value)
    year = int(year_match.group()) if year_match else None
    if ep:
        main = value[:ep.start()].strip(' -._')
        return main or value, year, int(ep.group(1)), int(ep.group(2))
    if year_match:
        name = (value[:year_match.start()] + value[year_match.end():]).strip(' -._')
        return name or value, year, None, None
    return value, None, None, None


class SubtitleEngine:
    def __init__(self):
        from subliminal import region
        try:
            region.configure('dogpile.cache.memory')
        except Exception:
            pass
        self.video = None
        self.entries = []  # (subtitle, provider key)
        self.selection = {}
        self.providers = {}
        self.warnings = []
        self.reliable_filename = False

    @staticmethod
    def lang(tag):
        from babelfish import Language
        return Language.fromietf(language_tag(tag))

    def close(self):
        for provider in self.providers.values():
            try:
                provider.terminate()
            except Exception:
                pass
        self.providers.clear()

    def get_provider(self, name: str, request: dict):
        if name in self.providers:
            return self.providers[name]
        if name == 'podnapisi':
            from subliminal.providers.podnapisi import PodnapisiProvider
            provider = PodnapisiProvider(timeout=13)
        elif name == 'opensubtitlescom':
            from subliminal.providers.opensubtitlescom import OpenSubtitlesComProvider
            username = str(request.get('username') or '').strip()
            password = str(request.get('password') or '')
            apikey = str(request.get('apikey') or '').strip()
            if username or password or apikey:
                # Credentials typed for this search are temporary; don't save silently.
                if not username or not password:
                    raise ValueError('OpenSubtitles.com: preencha usuário e senha juntos.')
            else:
                # Read automatically on every new search, including context actions.
                try:
                    saved = load_credentials()
                except CredentialStoreError as exc:
                    self.warnings.append(f'Chaveiro: {exc} Usando busca sem login.')
                    saved = None
                if saved:
                    username, password, apikey = (saved['username'],
                                                  saved['password'], saved['apikey'])
            # Subliminal provides an app key. User can override with their own key.
            provider = OpenSubtitlesComProvider(
                username=username, password=password, apikey=apikey,
                timeout=15, max_result_pages=2,
            )
        else:
            raise ValueError('Fonte desconhecida.')
        provider.initialize()
        self.providers[name] = provider
        return provider

    @staticmethod
    def provider_keys(request):
        selected = request.get('provider', 'all')
        if selected == 'all':
            return ('podnapisi', 'opensubtitlescom')
        if selected in PROVIDER_LABELS:
            return (selected,)
        raise ValueError('Selecione um provedor válido.')

    def search(self, request: dict) -> dict:
        from subliminal import Video, scan_video, compute_score
        self.close()
        self.entries = []
        self.warnings = []
        mode = request.get('source')
        language = language_tag(request.get('language', 'pt-BR'))
        value = str(request.get('path') if mode == 'file' else request.get('title') or '').strip()
        lang = self.lang(language)
        if mode == 'file':
            path = Path(value).expanduser()
            if not path.is_file() or path.suffix.lower() not in VIDEO_SUFFIXES:
                raise ValueError('Selecione um vídeo existente e compatível.')
            try:
                video = scan_video(str(path))
            except Exception as exc:
                print(f'Video sem análise técnica: {exc}', file=sys.stderr)
                video = Video.fromname(str(path))
            needle = str(getattr(video, 'title', '') or getattr(video, 'series', '') or path.stem)
            self.reliable_filename = True
            value = str(path)
        elif mode == 'title':
            value = clean_title(value)
            video = Video.fromname(movie_guess_name(value))
            needle, _, _, _ = title_parts(value)
            self.reliable_filename = False
            if not Path(request.get('output_dir') or '').expanduser().is_dir():
                raise ValueError('Selecione uma pasta existente para salvar a legenda.')
        else:
            raise ValueError('Escolha um arquivo ou digite um título.')
        self.video = video
        self.selection = {'source': mode, 'value': value, 'language': language,
                          'output_dir': request.get('output_dir', '')}
        title_query, year, season, episode = title_parts(needle)
        if mode == 'file':
            year = getattr(video, 'year', None)
            season = getattr(video, 'season', None)
            episode = getattr(video, 'episode', None)
        all_items = []
        successful_providers = 0
        for provider_name in self.provider_keys(request):
            try:
                provider = self.get_provider(provider_name, request)
                # Search precisely for file mode; title mode searches provider's
                # keyword API *directly*, so 'avengers' may return the franchise.
                if mode == 'file':
                    subtitles = provider.list_subtitles(video, {lang})
                    if not subtitles:
                        if provider_name == 'podnapisi':
                            subtitles = provider.query(lang, title_query,
                                **({'season': season, 'episode': episode} if season and episode else {}))
                        else:
                            subtitles = provider.query({lang}, query=title_query)
                elif provider_name == 'podnapisi':
                    # Year intentionally not filtered; a year entered by the
                    # user affects ranking, not completeness of broad results.
                    subtitles = provider.query(lang, title_query,
                        **({'season': season, 'episode': episode} if season and episode else {}))
                else:
                    # Query directly preserves partial match searches.
                    subtitles = provider.query({lang}, query=title_query,
                        **({'season': season, 'episode': episode} if season and episode else {}))
                successful_providers += 1
                for sub in subtitles:
                    all_items.append((provider_name, sub))
            except Exception as exc:
                warning = f'{PROVIDER_LABELS[provider_name]}: {str(exc) or type(exc).__name__}'
                self.warnings.append(warning)
                print(f'[provider] {warning}', file=sys.stderr)
        if not successful_providers:
            raise RuntimeError('Não foi possível consultar os provedores. ' + ' | '.join(self.warnings))

        results = []
        seen = set()
        for provider_name, sub in all_items:
            sid = str(getattr(sub, 'id', '') or '')
            unique = (provider_name, sid)
            if unique in seen:
                continue
            seen.add(unique)
            title = str(getattr(sub, 'movie_title', '') or getattr(sub, 'title', '') or
                        getattr(sub, 'series_title', '') or getattr(sub, 'file_name', '') or needle)
            year_value = getattr(sub, 'movie_year', None) or getattr(sub, 'year', None)
            release = str(getattr(sub, 'info', None) or getattr(sub, 'release_info', '') or
                          getattr(sub, 'file_name', '') or sid or 'Sem detalhes')
            release = ' '.join(release.split())[:240]
            try:
                score_raw = compute_score(sub, video)
                score = int(score_raw[0] if isinstance(score_raw, tuple) else score_raw)
            except Exception:
                score = 0
            hash_match = bool(getattr(sub, 'moviehash_match', False))
            try:
                hash_match = hash_match or ('hash' in sub.get_matches(video))
            except Exception:
                pass
            name_match = title_matches(title_query, title)
            # Partial title should rank matches above unrelated titles.
            # In file mode prefer hash/technical match from Subliminal.
            priority = ((30000 if hash_match else 0) + (2000 if name_match else 0)
                        + (300 if year and str(year) == str(year_value) else 0)
                        + score + min(int(getattr(sub, 'download_count', 0) or 0), 300) // 100)
            # Never discard a provider result merely because the displayed
            # movie title is translated (e.g. Avengers -> Os Vingadores).
            results.append({'provider': provider_name, 'subtitle': sub,
                            'title': title, 'year': str(year_value or ''),
                            'release': release, 'score': score, 'priority': priority,
                            'hash_match': hash_match})
        results.sort(key=lambda row: row['priority'], reverse=True)
        results = results[:120]
        self.entries = [(row['subtitle'], row['provider']) for row in results]
        return {'entries': [dict(index=index,
                                 provider=PROVIDER_LABELS[row['provider']],
                                 provider_key=row['provider'], title=row['title'],
                                 year=row['year'], release=row['release'],
                                 language=language, score=row['score'],
                                 hash_match=row['hash_match'])
                            for index, row in enumerate(results)],
                'warnings': self.warnings}

    def download(self, request: dict) -> str:
        if not self.entries:
            raise ValueError('Pesquise legendas antes de baixar.')
        index = request.get('index')
        if not isinstance(index, int) or not (0 <= index < len(self.entries)):
            raise ValueError('Selecione uma legenda válida da lista.')
        sub, provider_name = self.entries[index]
        provider = self.providers.get(provider_name)
        if provider is None:
            raise RuntimeError('O provedor não está mais disponível. Pesquise novamente.')
        if provider_name == 'opensubtitlescom' and not (provider.username and provider.password):
            raise ValueError('Para baixar do OpenSubtitles.com, informe usuário e senha na seção Conta.\n'
                             'A busca pode ser feita sem login, mas o Subliminal exige autenticação para baixar.')
        sel = self.selection
        if sel['source'] == 'title':
            # A generic query such as 'avengers' can return many films. Save
            # using the SELECTED movie, not an ambiguous search keyword.
            selected_title = (getattr(sub, 'movie_title', None) or
                              getattr(sub, 'title', None) or
                              getattr(sub, 'series_title', None) or sel['value'])
            selected_title = str(selected_title)
            season = getattr(sub, 'series_season', None) or getattr(sub, 'season', None)
            episode = getattr(sub, 'series_episode', None) or getattr(sub, 'episode', None)
            if season is not None and episode is not None:
                selected_title = f'{selected_title} S{int(season):02d}E{int(episode):02d}'
            else:
                year = getattr(sub, 'movie_year', None) or getattr(sub, 'year', None)
                if year and str(year) not in selected_title:
                    selected_title += f' {year}'
            target = output_path('title', selected_title, sel['language'], sel['output_dir'])
        else:
            target = output_path(sel['source'], sel['value'], sel['language'], sel['output_dir'])
        if target.exists():
            raise FileExistsError(f'Já existe uma legenda em {target}. Nada foi sobrescrito.')
        provider.download_subtitle(sub)
        content = getattr(sub, 'content', None)
        if not content:
            raise RuntimeError('O provedor não devolveu dados da legenda.')
        try:
            txt = sub.text
            if not txt or not txt.strip():
                raise ValueError('Legenda vazia.')
            raw = txt.encode('utf-8')
        except Exception:
            raw = content if isinstance(content, bytes) else str(content).encode('utf-8')
        with target.open('xb') as file:
            file.write(raw)
        return str(target)


def rpc() -> int:
    engine = SubtitleEngine()
    say('ready')
    try:
        for line in sys.stdin:
            try:
                request = json.loads(line)
                action = request.get('action')
                if action == 'search':
                    say('results', **engine.search(request))
                elif action == 'download':
                    say('saved', path=engine.download(request))
                elif action == 'credentials_status':
                    say('credentials_status', **safe_status())
                elif action == 'credentials_save':
                    save_credentials(request.get('username', ''),
                                     request.get('password', ''), request.get('apikey', ''))
                    say('credentials_saved', **safe_status())
                elif action == 'credentials_remove':
                    clear_credentials()
                    say('credentials_removed', **safe_status())
                else:
                    say('error', message='Ação desconhecida.')
            except Exception as exc:
                print(traceback.format_exc(), file=sys.stderr)
                say('error', message=str(exc) or type(exc).__name__)
    finally:
        engine.close()
    return 0


def alert(title: str, message: str, error=False):
    try:
        subprocess.run(['notify-send', '-a', 'Wolf Subtitle Downloader',
                        '-i', 'dialog-error' if error else 'dialog-information',
                        title, message[:450]], check=False, timeout=5)
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass


def quick(path: str) -> int:
    engine = SubtitleEngine()
    try:
        # If saved credentials are available, consult BOTH providers; otherwise
        # use Podnapisi alone, so a guest OpenSubtitles result isn't selected
        # even though it cannot be downloaded without a login.
        try:
            has_login = load_credentials() is not None
        except CredentialStoreError as exc:
            print(f'[chaveiro] {exc}', file=sys.stderr)
            has_login = False
        result = engine.search({'source': 'file', 'path': path, 'language': 'pt-BR',
                                'provider': 'all' if has_login else 'podnapisi'})
        entries = result['entries']
        if not entries:
            alert('Nenhuma legenda encontrada', Path(path).name, error=True)
            print('Nenhuma legenda encontrada para esse arquivo.', file=sys.stderr)
            return 2
        # A failed provider must not stop a valid Podnapisi result.
        failures = []
        for entry in entries:
            try:
                dest = engine.download({'index': entry['index']})
                alert('Legenda baixada', Path(dest).name)
                print(dest)
                return 0
            except FileExistsError:
                raise  # Never replace an existing subtitle.
            except Exception as exc:
                failures.append(f"{entry['provider']}: {type(exc).__name__}")
                print(f"[download] {entry['provider']}: {type(exc).__name__}", file=sys.stderr)
        alert('Falha ao baixar legenda', 'Nenhum provedor conseguiu baixar a legenda.', error=True)
        print('Downloads não concluídos: ' + ', '.join(failures), file=sys.stderr)
        return 1
    except Exception as exc:
        alert('Erro ao baixar legenda', str(exc), error=True)
        print(f'Erro: {exc}', file=sys.stderr)
        return 1
    finally:
        engine.close()


if __name__ == '__main__':
    if len(sys.argv) == 2 and sys.argv[1] == '--rpc':
        sys.exit(rpc())
    if len(sys.argv) == 3 and sys.argv[1] == '--quick':
        sys.exit(quick(sys.argv[2]))
    print('Uso: backend.py --rpc | --quick ARQUIVO', file=sys.stderr)
    sys.exit(2)
