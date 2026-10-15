# Wolf Linux 2.0.0-alpha34 — Limites seguros para partições

- GUI 1.4: barras QSlider + campos QSpinBox sincronizados para `/` e `/home` no modo Apagar disco inteiro; disco selecionado define limites máximos reais, não mais 16384 GiB arbitrários.
- Cálculo único no módulo `wolf_plan.erase_usable_gib`: ESP UEFI 1 GiB + folga de 1 GiB; BIOS com folga de 1 GiB e sem ESP. Recalcula ao trocar disco ou layout da /home.
- `/home` separada: mínimo 20 GiB para raiz, 10 GiB para /home; 0 em /home significa restante; tamanho fixo não pode ultrapassar capacidade disponível. Campos ficam desabilitados quando disco não é selecionado/é pequeno demais.
- Revalidação de capacidade também ocorre na geração de plano JSON/na validação do backend. Testes de regressão dedicados ao dimensionamento para BIOS/UEFI.
- Continua restrito a **VM QEMU/KVM + VirtIO** para instalação; Live e diagnósticos podem ser validados em hardware físico sem alterar discos.
- Instalação física em multidisco/LVM permanece fora do escopo desta revisão.
