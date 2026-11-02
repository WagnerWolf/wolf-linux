# Preview 4 — resumão

**Status:** preparador de pacote experimental; não é uma versão liberada para instalação.

- Base: Wolf Linux DevKit 2.2.0 + Integrações Wolf 0.3.6 Preview 3, com Fusion escuro mantido.
- Alvo estrito: libfm-qt 2.4.0-4 / pcmanfm-qt 2.4.1-1 do hardware de teste.
- Ação C++: menu de dispositivos em `PlacesView`, envia `--device` ao formatador Wolf.
- O patch C++ foi conferido contra assinaturas/âncoras da tag upstream 2.4.0 disponíveis publicamente. O pacote completo **não foi compilado** neste ambiente.
- O gerador só aceita fonte local com Git HEAD etiquetado 2.4.0, placesview.cpp limpo, `git apply --check` aprovado e receita oficial PKGBUILD 2.4.0-4.
- Cópia experimental do formatador com `--device` existe apenas no repositório: instalar/validar o backend apropriado em VM antes de testar a ação do menu.
- A auditoria do Wolf Package Manager permanece como **Pendente**, de propósito. Manifesto validado será produzido somente após testes de empacotamento, ABI, menu, segurança e rollback.
- Instruções completas: `EXPERIMENTO-INTEGRACOES-WOLF-PREVIEW4.md`.
