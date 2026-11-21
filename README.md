# axuz_office_ds

Espelho de fonte e de releases do **Document Server** do Axuz (ONLYOFFICE Docs CE compilado do fonte, AGPL-3.0, modificado; "Editor de
documentos"). Repo privado da org `axuzme`.

| O que | Onde |
|---|---|
| Fonte correspondente (AGPL secao 13) e como reconstruir | `SOURCE.md` |
| Aviso de modificacao | `NOTICE-AXUZ.txt` |
| Pins (SHAs de cada repo/dependencia) | `PINS.md` e `recipe/office/blobs.lock` |
| Patches nossos | `recipe/office/patches/` |
| Receita de build (estagios, Dockerfiles, run-build.sh com `DEPOT_TOOLS_METRICS=0`, release.sh) | `recipe/office/` |
| Gates (`check-no-blob.sh`, `check-agpl-notices.sh`) | `recipe/security/office/`, `check-agpl-notices.sh` |
| Releases (tar.zst + SBOM + SHA256SUMS + version.json) | aba Releases; tags `v<versao>-axuz.<n>` |

A receita e mantida no `axuzme/axuz_ops` (pasta `office/`); `recipe/` e a copia do commit em `recipe/RECIPE_COMMIT`.
Nada aqui e instalado a mao: o `axuz_ops` (na VPS) baixa o release por tag e verifica o sha256 fixado em `modules/office-ds.yaml`.
Build so na maquina de build dev/hml, a partir de commit pushado; nunca na VPS.
