"""Reconhece o perfil da sessão atual; nunca deduz LXQt apenas por pacote antigo."""
from __future__ import annotations
import os
import re


def is_plasma(env=None):
    env = os.environ if env is None else env
    text = ' '.join(str(env.get(k, '')) for k in
                    ('XDG_CURRENT_DESKTOP', 'XDG_SESSION_DESKTOP', 'DESKTOP_SESSION'))
    tokens = set(t.lower() for t in re.split(r'[:;\s/]+', text) if t)
    return 'kde' in tokens or 'plasma' in tokens


def needs_libfm_guard(env=None):
    # KDE/Dolphin não utiliza a libfm-qt Wolf; perfis desconhecidos conservam
    # o bloqueio de segurança antigo até a migração ser confirmada.
    return not is_plasma(env)
