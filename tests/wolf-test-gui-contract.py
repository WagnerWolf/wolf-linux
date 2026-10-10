#!/usr/bin/env python3
"""Regressões do contrato read-only GUI->Bash sem acesso a discos reais."""
from __future__ import annotations
import copy
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("wolf_plan", ROOT / "live-gui/wolf_plan.py")
wp = importlib.util.module_from_spec(spec)
assert spec.loader
spec.loader.exec_module(wp)

raw = json.dumps({"blockdevices": [
    {"type":"disk", "path":"/dev/nvme0n1", "size":200000000000, "maj:min":"259:0", "model":"SSD",
     "children":[{"type":"part","path":"/dev/nvme0n1p1","size":536870912,"fstype":"vfat"},
                 {"type":"part","path":"/dev/nvme0n1p2","size":100000000000,"fstype":"ext4"}]},
    {"type":"disk", "path":"/dev/sdb", "size":32000000000, "maj:min":"8:16", "model":"USB",
     "children":[{"type":"part","path":"/dev/sdb1","size":10000000000,"fstype":"ext4"}]}]})
disks = wp.inventory(raw)
assert len(disks) == 2
kwargs = dict(disks=disks, disk_path="/dev/nvme0n1", mode="reuse", preset="test",
              stacks=wp.PRESETS["test"], hostname="wolf-linux", username="wolf",
              keyboard={"layout":"br","model":"abnt2","variant":"thinkpad"}, boot_mode="UEFI",
              roles={"root":"/dev/nvme0n1p2", "esp":"/dev/nvme0n1p1", "home":None},
              formats={"root":True, "esp":False, "home":False})
doc = wp.build_preview(**kwargs)
assert doc["execution"] == "disabled"
assert "read-only" in wp.text_summary(doc).lower() or "SOMENTE LEITURA" in wp.text_summary(doc)
assert wp.validate_document(doc, disks=disks) == doc
with tempfile.TemporaryDirectory() as tmp:
    path = Path(tmp) / "preview.json"
    wp.write_private(doc, path)
    assert path.stat().st_mode & 0o777 == 0o600
    assert wp.review_file(path, disks=disks).startswith("WOLF LINUX")
    assert "formatar" in wp.review_file(path, disks=disks).lower()

    def rejected(change, inventory=None):
        evil = copy.deepcopy(doc)
        change(evil)
        path.write_text(json.dumps(evil))
        try:
            wp.review_file(path, disks=disks if inventory is None else inventory)
        except (wp.PlanError, ValueError, TypeError, KeyError):
            return
        raise AssertionError("Plano inválido aceito")

    rejected(lambda d: d.update(execution="install"))
    rejected(lambda d: d.update(schema="wolf.install.execute.v1"))
    rejected(lambda d: d["storage"].update(home_layout="unknown"))
    rejected(lambda d: d["storage"].update(home_layout="separate"))
    # Simulação declarativa SEM executar o instalador real.
    result = wp.simulate_document(doc, disks=disks)
    assert "SIMULAÇÃO" in result and "EXECUÇÃO: DESABILITADA" in result
    assert "diretório dentro de /" in result
    assert "INCOMPLETO" in result  # reutilização executável exige /home separada
    separated = wp.build_preview(**(kwargs | {"home_layout": "separate", "roles": {"root":"/dev/nvme0n1p2", "esp":"/dev/nvme0n1p1", "home":None}}))
    assert "BLOQUEIO: Selecione a partição dedicada a /home" in wp.simulate_document(separated, disks=disks)
    without_format = wp.build_preview(**(kwargs | {"formats": {"root":False,"esp":False,"home":False}}))
    assert "Bash atual sempre formata a raiz" in wp.simulate_document(without_format, disks=disks)
    manual = wp.build_preview(**(kwargs | {"mode":"manual"}))
    assert "Raiz /: formatada ext4" in wp.simulate_document(manual, disks=disks)
    with tempfile.TemporaryDirectory() as d:
        sim_path = Path(d) / "plan.json"
        wp.write_private(doc, sim_path)
        fakebin = Path(d) / "bin"
        fakebin.mkdir()
        fake_lsblk = fakebin / "lsblk"
        fake_lsblk.write_text("#!/usr/bin/env bash\ncat <<'FAKE_LSBLK'\n" + raw + "\nFAKE_LSBLK\n")
        fake_lsblk.chmod(0o755)
        mock_env = dict(os.environ, PATH=f"{fakebin}:{os.environ.get('PATH', '')}")
        sim_cli = subprocess.run(["bash", str(ROOT / "install/wolf-install.sh"), "--simulate-gui-plan", str(sim_path)],
                                 capture_output=True, text=True, timeout=10, env=mock_env)
        assert sim_cli.returncode == 0, sim_cli.stderr
        assert "SIMULAÇÃO" in sim_cli.stdout
        assert "Nenhum processo de instalação" in sim_cli.stdout
        bad_cli = subprocess.run(["bash", str(ROOT / "install/wolf-install.sh"), "--simulate-gui-plan", str(sim_path), "--install"],
                                 capture_output=True, text=True, timeout=10, env=mock_env)
        assert bad_cli.returncode != 0

    rejected(lambda d: d.update(command="wipefs /dev/sda"))
    rejected(lambda d: d["storage"]["disk"].update(size=1))
    rejected(lambda d: d["storage"]["partitions"].update(root="/dev/sdb1"))
    rejected(lambda d: d["software"].update(stacks=["daily"]))
    rejected(lambda d: d["storage"]["format"].update(home=True))
    rejected(lambda d: d["identity"].update(username="wolf;rm -rf /"))
    rejected(lambda d: None, inventory=disks[1:])
    # Bash deve finalizar este modo sem criar /tmp/wolf-linux-installer ou solicitar entrada
    null_doc = wp.build_preview(disks=[], disk_path="", mode="manual", preset="minimal", stacks=(),
                                hostname="wolf", username="wolf", keyboard={"layout":"br","model":"abnt2","variant":""},
                                boot_mode="unknown")
    path.write_text(json.dumps(null_doc))
    result = subprocess.run(["bash", str(ROOT / "install/wolf-install.sh"), "--review-gui-plan", str(path)],
                            capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, result.stderr
    assert "SOMENTE LEITURA" in result.stdout, result.stdout
    assert "JSON: não concede permissão de execução" in result.stdout
    invalid = subprocess.run(["bash", str(ROOT / "install/wolf-install.sh"), "--review-gui-plan", str(path), "--install"],
                             capture_output=True, text=True, timeout=10)
    assert invalid.returncode != 0
print("[OK] Contrato GUI->Bash v3: /home integrado/separado, simulacao, recusas, guardas CLI")
