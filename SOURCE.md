# Fonte correspondente — Editor de documentos (ONLYOFFICE Docs Community Edition, modificado)

Este repositorio e o ESPELHO DE FONTE E DE RELEASES do Document Server que o Axuz opera (`office_ds`, em `office.<DOMAIN>`).
O Document Server e o **ONLYOFFICE Docs Community Edition** (Ascensio System SIA, https://github.com/ONLYOFFICE), licenciado sob a
**GNU Affero General Public License v3.0** com os termos adicionais do projeto (arquivo `LICENSE`). O Axuz o **modificou**:
o aviso de modificacao esta em `NOTICE-AXUZ.txt`. No Axuz o produto se chama "Editor de documentos"; ONLYOFFICE e o desenvolvedor
original e e identificado como tal na tela "Sobre" do editor e no rodape do wrapper.

## Como obter o fonte correspondente (AGPL-3.0, secao 13) de um release

1. `version.json` (no release e em `documentserver/AXUZ/version.json` dentro do tar) lista cada repositorio ONLYOFFICE usado com o
   commit EXATO e o `recipe_commit` (commit da receita de build no `axuzme/axuz_ops`).
2. Os repositorios ONLYOFFICE (core, sdkjs, web-apps, server, document-formats, core-fonts, dictionaries, ...) estao fixados por commit em
   `recipe/office/blobs.lock` (resumo legivel em `PINS.md`). Os demais componentes (V8, Node.js, Qt, ICU, libxml2, boost, ...) tambem
   estao ali, com repo+commit ou tarball+sha256.
3. As nossas modificacoes sao patches versionados em `recipe/office/patches/` (cada arquivo patchado carrega o aviso "Modified by Axuz"
   com data; patches de dado/json sao citados em `NOTICE-AXUZ.txt`). Os 5 `.wasm` do sdkjs e o glue do libheif sao COMPILADOS por nos
   do fonte do `core` (receitas em `recipe/office/wasm/`, emsdk fixado por digest).
4. A receita de build (estagios, Dockerfiles por digest, `run-build.sh`, `release.sh`) esta em `recipe/office/` e os gates em
   `recipe/security/office/` (`check-no-blob.sh`: todo binario do artefato tem origem rastreada; `check-agpl-notices.sh`).
   `recipe/RECIPE_COMMIT` e o commit do `axuzme/axuz_ops` de onde esta copia foi tirada.
5. O SBOM (`sbom.cdx.json`) e o `SHA256SUMS` do release provam o conteudo, arquivo a arquivo.

O build NUNCA roda na VPS: e feito na maquina de build a partir de commit pushado, publicado como release deste repositorio e o ops
da VPS baixa por tag e VERIFICA o sha256 fixado no git (`axuz_ops/modules/office-ds.yaml`) antes de instalar.

## Acesso

Este repositorio e PRIVADO por ora. Antes de o editor ser oferecido a usuarios externos, o fonte correspondente tem de estar acessivel a
eles: tornar este repositorio publico ou oferecer o fonte por escrito a quem pedir (decisao operacional do dono; ADR
2026-11-13-docs-online-editor, secao 4). O link "Codigo-fonte" do wrapper e `office.<DOMAIN>/source`.

Nao e parecer juridico; revisao juridica prevista na onda O4 do plano.
