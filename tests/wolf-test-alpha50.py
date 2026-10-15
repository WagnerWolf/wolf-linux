#!/usr/bin/env python3
"""Alpha50: dotfiles raiz do usuário, prévia e backup opcional, SEM discos reais."""
import json
import os
from types import SimpleNamespace
from pathlib import Path
import sys
import tempfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'live-gui'))
import wolf_home_cleanup as hc


def root_owned_manifest(manifest: Path):
    """Simula exclusivamente st_uid=0 no teste sem relaxar a segurança real.

    A execução física e _read_manifest continuam exigindo proprietário root
    e permissões 0600. No smoke test, o arquivo é escrito pelo usuário comum.
    """
    real_lstat = Path.lstat

    def simulated_lstat(path, *args, **kwargs):
        st = real_lstat(path, *args, **kwargs)
        if path == manifest:
            return SimpleNamespace(st_mode=st.st_mode, st_uid=0)
        return st

    return patch.object(Path, 'lstat', new=simulated_lstat)


def assert_manifest_protection(manifest: Path, names: list[str]):
    """Verifica proprietário root e recusa permissões inseguras."""
    assert (manifest.stat().st_mode & 0o777) == 0o600
    if os.geteuid() != 0:
        try:
            hc._read_manifest(manifest)
        except hc.CleanupDenied:
            pass
        else:
            raise AssertionError('Manifesto de usuário não root foi aceito')
    with root_owned_manifest(manifest):
        assert hc._read_manifest(manifest) == names
        manifest.chmod(0o644)
        try:
            hc._read_manifest(manifest)
        except hc.CleanupDenied:
            pass
        else:
            raise AssertionError('Manifesto com modo 0644 foi aceito')
        manifest.chmod(0o600)
    assert (manifest.stat().st_mode & 0o777) == 0o600


assert hc.validate_spec({'enabled':False, 'backup':False}) == {'enabled':False,'backup':False}
assert hc.validate_spec({'enabled':True, 'backup':True}) == {'enabled':True,'backup':True}
for invalid in [
    {'enabled': True, 'backup':'no'}, {'enabled':'yes','backup':False},
    {'enabled':False,'backup':True}, {'enabled':True,'backup':False,'items':[]},
    {'enabled':True}, {'enabled':1,'backup':False}
]:
    try: hc.validate_spec(invalid)
    except hc.CleanupDenied: pass
    else: raise AssertionError('Contrato inseguro aceito: '+repr(invalid))

with tempfile.TemporaryDirectory(prefix='wolf50-test-') as tmp:
    base=Path(tmp); user=base/'wolf';user.mkdir()
    (user/'Documents').mkdir(); (user/'Documents'/'important.txt').write_text('SEGURO')
    (user/'foto.jpg').write_text('PERMANECER')
    (user/'.config').mkdir(); (user/'.config'/'xfce.conf').write_text('old')
    (user/'.local'/'share'/'Steam'/'steamapps').mkdir(parents=True)
    (user/'.local'/'share'/'Steam'/'steamapps'/'game').write_text('JOGO')
    (user/'.ssh').mkdir(); (user/'.ssh'/'id_ed25519').write_text('CHAVE')
    (user/'.steam').symlink_to(user/'Documents',target_is_directory=True)
    (user/'.bashrc').write_text('config')
    names=hc.root_dotfiles(base,'wolf')
    assert names==['.bashrc','.config','.local','.ssh','.steam'],names
    infos=hc.root_dotfile_info(base,'wolf')
    assert set(v['path'] for v in infos)==set(names)
    assert any(v['path']=='.local' and v['bytes']>0 for v in infos)
    manifest=base/'confirmed.json'; hc._write_manifest(manifest,names)
    assert_manifest_protection(manifest,names)
    with root_owned_manifest(manifest), patch.object(hc,'_mount_guard'), patch.object(hc,'_no_nested_mounts'):
        count, backup=hc.perform_root(base,'/dev/test','wolf',{'enabled':True,'backup':False},manifest)
    assert count==5 and not backup
    assert hc.root_dotfiles(base,'wolf')==[]
    assert (user/'Documents'/'important.txt').read_text()=='SEGURO'
    assert (user/'foto.jpg').read_text()=='PERMANECER'
    assert (base/'Documents').exists() is False

with tempfile.TemporaryDirectory(prefix='wolf50-backup-') as tmp:
    base=Path(tmp); user=base/'wolf';user.mkdir()
    (user/'.local'/'share').mkdir(parents=True)
    (user/'.local'/'share'/'state.dat').write_text('VALOR')
    (user/'.env').write_text('VAR=secret')
    (user/'keep').write_text('safe')
    manifest=base/'confirmed.json';hc._write_manifest(manifest,hc.root_dotfiles(base,'wolf'))
    assert_manifest_protection(manifest,hc.root_dotfiles(base,'wolf'))
    with root_owned_manifest(manifest), patch.object(hc,'_mount_guard'), patch.object(hc,'_no_nested_mounts'):
        count, backup=hc.perform_root(base,'/dev/test','wolf',{'enabled':True,'backup':True},manifest)
    assert count==2 and backup
    assert (Path(backup)/'wolf'/'.local'/'share'/'state.dat').read_text()=='VALOR'
    assert (Path(backup)/'wolf'/'.env').read_text()=='VAR=secret'
    assert (user/'keep').read_text()=='safe'
    assert not (user/'.local').exists()

with tempfile.TemporaryDirectory(prefix='wolf50-unchanged-') as tmp:
    base=Path(tmp); user=base/'wolf';user.mkdir()
    (user/'.config').mkdir()
    manifest=base/'confirmed.json';hc._write_manifest(manifest,hc.root_dotfiles(base,'wolf'))
    assert_manifest_protection(manifest,hc.root_dotfiles(base,'wolf'))
    (user/'.steam').mkdir() # novo alvo: não estava autorizado
    with root_owned_manifest(manifest), patch.object(hc,'_mount_guard'), patch.object(hc,'_no_nested_mounts'):
        try: hc.perform_root(base,'/dev/test','wolf',{'enabled':True,'backup':False},manifest)
        except hc.CleanupDenied: pass
        else: raise AssertionError('Apagou entradas alteradas após a prévia')
    assert (user/'.config').exists() and (user/'.steam').exists()
    hc._write_manifest(manifest,hc.root_dotfiles(base,'wolf'))
    with root_owned_manifest(manifest),patch.object(hc,'_mount_guard'),patch.object(hc,'_no_nested_mounts',side_effect=hc.CleanupDenied('submontagem')):
        try: hc.perform_root(base,'/dev/test','wolf',{'enabled':True,'backup':False},manifest)
        except hc.CleanupDenied: pass
        else: raise AssertionError('Não bloqueou submontagem')
    assert (user/'.config').exists() and (user/'.steam').exists()

bash=(ROOT/'install/wolf-install.sh').read_text()
ui=(ROOT/'live-gui/main.py').read_text()
assert "'scan-root'" in ui
assert 'self.home_cleanup_check' in ui and 'self.toggle_home_cleanup' in ui
assert "'LIMPAR'" in bash
assert 'HOME_CLEAN_LIST_FILE' in bash and 'PHYSICAL_PLAN_SHA256' in bash
assert 'revalidate_gui_physical_target\n        mkfs.ext4 -F "$ROOT_DEVICE"' in bash
assert 'stage "22-limpar-home" clean_preserved_home_dotfiles' in bash
assert (ROOT/'VERSION').read_text().strip() in ('2.0.0-alpha50','2.0.0-alpha51', '2.0.0-alpha52', '2.0.0-alpha53', '2.0.0-alpha54', '2.0.0-alpha55', '2.0.0-alpha56', '2.0.0-alpha57', '2.0.0-alpha58', '2.0.0-alpha59', '2.0.0')
print('[OK] alpha50: checkbox único e prévia integral, backup optativo')
print('[OK] alpha50: diretórios aninhados (.local/Steam), links, visíveis e credenciais')
print('[OK] alpha50/51: backup, manifesto e bloqueios de alterações/submontagens')
print('[OK] alpha51: manifesto root-only simulado em testes não privilegiados, sem relaxar produção')
