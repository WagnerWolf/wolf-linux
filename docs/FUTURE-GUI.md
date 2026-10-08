# Futuro frontend gráfico do Wolf Installer

O backend 2.0 já aceita presets e stacks por linha de comando. Uma futura GUI deve apenas coletar escolhas e chamar o mesmo instalador.

Exemplo conceitual:

```text
[✓] Uso diário
[✓] Gaming
[✓] Desenvolvimento
[ ] Android + Flutter
[ ] Containers
[✓] Extras

[ Instalar ]
```

A GUI não deve duplicar lógica de pacotes, particionamento, drivers ou helpers. Ela deve serializar as opções para algo equivalente a:

```bash
wolf-install --install --stacks daily,gaming,development,extras
```

Para a primeira versão, uma interface Qt/Kirigami é a opção natural por o Wolf Linux ter KDE Plasma como único desktop suportado.
