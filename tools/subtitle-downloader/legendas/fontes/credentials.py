#!/usr/bin/env python3
"""Armazenamento de credenciais APENAS no Secret Service do usuário.

`secret-tool` recebe o segredo via stdin (nunca por argumento de processo).
Nenhuma alternativa em texto simples é criada quando o chaveiro falha.
"""
from __future__ import annotations

import json
import shutil
import subprocess

LABEL = 'Wolf Subtitle Downloader — conta OpenSubtitles.com'
ATTRIBUTES = ('application', 'wolf-subtitle-downloader', 'provider', 'opensubtitlescom')


class CredentialStoreError(RuntimeError):
    """Falha segura no acesso ao chaveiro do usuário."""


def _secret_tool(operation: str, value: str | None = None) -> str:
    binary = shutil.which('secret-tool')
    if binary is None:
        raise CredentialStoreError('O comando secret-tool não está instalado (pacote libsecret).')
    if operation not in ('lookup', 'store', 'clear'):
        raise ValueError('Operação de credenciais inválida.')
    cmd = [binary, operation]
    if operation == 'store':
        cmd += ['--label', LABEL]
    cmd += list(ATTRIBUTES)
    try:
        proc = subprocess.run(cmd, input=value if operation == 'store' else None,
                              capture_output=True, text=True, timeout=25, check=False)
    except subprocess.TimeoutExpired as exc:
        raise CredentialStoreError('O chaveiro não respondeu. Verifique se está desbloqueado.') from exc
    except OSError as exc:
        raise CredentialStoreError('Não foi possível comunicar com o chaveiro do sistema.') from exc
    if operation == 'lookup' and proc.returncode == 1 and not proc.stdout and not proc.stderr:
        # libsecret's secret-tool exits 1 when no matching entry exists.
        return ''
    if proc.returncode != 0:
        # Don't surface arbitrary command output: some implementations may print secrets.
        raise CredentialStoreError('Falha no chaveiro. Verifique o serviço Secret Service e desbloqueie-o.')
    return proc.stdout


def save_credentials(username: str, password: str, apikey: str = '') -> None:
    username = str(username).strip()
    password = str(password)
    apikey = str(apikey).strip()
    if not username or not password:
        raise ValueError('Informe usuário e senha do OpenSubtitles.com antes de salvar.')
    if '\x00' in username + password + apikey:
        raise ValueError('Caracteres inválidos nas credenciais.')
    payload = json.dumps({'version': 1, 'username': username, 'password': password,
                          'apikey': apikey}, ensure_ascii=False)
    # Stdin, never argv, env or files.
    _secret_tool('store', payload)
    # Verify persistence without writing the secret anywhere else.
    loaded = load_credentials()
    if loaded != {'username': username, 'password': password, 'apikey': apikey}:
        raise CredentialStoreError('O chaveiro não confirmou o armazenamento. Tente novamente.')


def load_credentials() -> dict[str, str] | None:
    raw = _secret_tool('lookup')
    if not raw:
        return None
    try:
        data = json.loads(raw)
    except (ValueError, TypeError) as exc:
        raise CredentialStoreError('O registro no chaveiro está em formato inválido.') from exc
    if not isinstance(data, dict) or data.get('version') != 1:
        raise CredentialStoreError('Versão de credenciais do chaveiro não reconhecida.')
    username, password, apikey = data.get('username'), data.get('password'), data.get('apikey', '')
    if not isinstance(username, str) or not isinstance(password, str) or not isinstance(apikey, str):
        raise CredentialStoreError('Registro de credenciais incompleto no chaveiro.')
    if not username or not password:
        raise CredentialStoreError('O registro de credenciais não contém usuário e senha.')
    return {'username': username, 'password': password, 'apikey': apikey}


def clear_credentials() -> None:
    _secret_tool('clear')
    if load_credentials() is not None:
        raise CredentialStoreError('Não foi possível excluir as credenciais do chaveiro.')


def safe_status() -> dict:
    """Nunca exponha senha ou chave da API na resposta da interface."""
    try:
        data = load_credentials()
        return {'stored': bool(data), 'username': data['username'] if data else '', 'error': ''}
    except CredentialStoreError as exc:
        return {'stored': False, 'username': '', 'error': str(exc)}
