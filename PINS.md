# PINS — fontes e dependencias do Document Server (gerado de recipe/office/blobs.lock)

Fonte da verdade: `recipe/office/blobs.lock` (id, classe, destino, origem, pin, licenca, fonte, status, nota). Todo item do build e rastreado a repo+SHA ou a download/tarball com sha256 fixado; `check-no-blob.sh` reprova qualquer binario fora disto. Nenhuma linha em `[~]` (on-hold).

## Repositorios ONLYOFFICE (tag base v10.0.0.176; cada repo na maior tag <= esta que ele possui)

| id | commit/pin | origem |
|---|---|---|
| node-src | `sha256:2026f9ff52c286d7c7d99932b21be313d1736aea524c5aff1748d41ab0bd9a20` | https://nodejs.org/dist/v20.19.6/node-v20.19.6.tar.xz |
| qt-src | `sha256:5ce285209290a157d7f42ec8eb22bf3f1d76f2e03a95fc0b99b553391be01642` | https://github.com/ONLYOFFICE-data/build_tools_data/raw/refs/heads/master/qt/qt-everywhere-opensource-src-5.9.9.tar.xz |
| gn-src | `595e3be7c8381d4eeefce62a63ec12bae9ce5140` | https://gn.googlesource.com/gn |
| ninja-src | `2daa09ba270b0a43e1929d29b073348aa985dfaa` | https://github.com/ninja-build/ninja |
| depot-tools | `b738decbefed1d63cc0238e4f3cac6665574f163` | https://chromium.googlesource.com/chromium/tools/depot_tools.git |
| v8-src | `a2d8eca22ad478a95ca67bb2421a9a2535113925` | https://chromium.googlesource.com/v8/v8.git |
| repo-build_tools | `8cccb383182f45f5171a7c6d62f49ebf37aab400` | https://github.com/ONLYOFFICE/build_tools.git |
| repo-core | `76af764fcb777291098c73728044249b6893af6a` | https://github.com/ONLYOFFICE/core.git |
| repo-sdkjs | `c1a29cc83824661d799711be14ef12b6125302f3` | https://github.com/ONLYOFFICE/sdkjs.git |
| repo-sdkjs-forms | `0148c8ed3f799136431be49d4d83b4064fbafd01` | https://github.com/ONLYOFFICE/sdkjs-forms.git |
| repo-web-apps | `493e500c56ec96ccaa0452ab092cbce23b6dcc2e` | https://github.com/ONLYOFFICE/web-apps.git |
| repo-server | `f9a8df6e7c9aa388c0d525965923c803f4cbc071` | https://github.com/ONLYOFFICE/server.git |
| repo-document-formats | `27188bac1f82c6ff0e7f02235cdbca22053a768e` | https://github.com/ONLYOFFICE/document-formats.git |
| repo-document-server-integration | `d57c945a1b971627a35c45709efe7a5167d95199` | https://github.com/ONLYOFFICE/document-server-integration.git |
| repo-document-templates | `0a52fb76fa53fddf7d70da28878537cde3d29421` | https://github.com/ONLYOFFICE/document-templates.git |
| repo-core-fonts | `7030c6681fb5bbed560675cb42422f91df15d5c9` | https://github.com/ONLYOFFICE/core-fonts.git |
| repo-dictionaries | `d3223bbb777883db66ac3cd249f71c6ebdc992c7` | https://github.com/ONLYOFFICE/dictionaries.git |
| repo-onlyoffice.github.io | `309a8850e9a3f56e13600516bbe2c1df1286cf80` | https://github.com/ONLYOFFICE/onlyoffice.github.io.git |
| server-createdb | `sha256:2be46373b8e267141a1fb8fbdeaefe019f4a705202db6d25bf829633f2fcfb0b` | https://github.com/ONLYOFFICE/server.git#e45d6029b057aa17d4206fc61c8638924adf67d9:schema/postgresql/createdb.sql |

## Ressalva 2 do gate O1.0 — createdb.sql
O repo `server` na tag v10.0.0.156 nao tem `schema/postgresql/createdb.sql`; o pipeline o restaura do commit `e45d6029b057aa17d4206fc61c8638924adf67d9` (2026-05-07, fora de qualquer tag v10), conferido por sha256 (linha `server-createdb`). O Document Server CE desta build roda em memoria (sem Postgres), o arquivo e mantido para a suite de smoke e para uma eventual troca de runtime.

## Demais classes (resumo)

| id | classe | destino | status |
|---|---|---|---|
| oci-ubuntu-noble | oci | build | ok |
| apt-noble-snapshot | apt | build | ok |
| oci-ubuntu-xenial | oci | build | ok |
| apt-xenial-archive | apt | build | ok |
| 3p-apple-glm | git | artefato | ok |
| 3p-apple-libetonyek | git | artefato | ok |
| 3p-apple-libodfgen | git | artefato | ok |
| 3p-apple-librevenge | git | artefato | ok |
| 3p-apple-mdds | git | artefato | ok |
| 3p-brotli | git | artefato | ok |
| 3p-googletest | git | artefato | ok |
| 3p-harfbuzz | git | artefato | ok |
| 3p-heif-libde265 | git | artefato | ok |
| 3p-heif-libheif | git | artefato | ok |
| 3p-heif-x265 | git | artefato | ok |
| 3p-html-gumbo-parser | git | artefato | ok |
| 3p-html-katana-parser | git | artefato | ok |
| 3p-hunspell-hunspell | git | artefato | ok |
| 3p-hyphen-hyphen | git | artefato | ok |
| 3p-libxml-libxml2 | git | artefato | ok |
| 3p-md-md4c | git | artefato | ok |
| 3p-openssl-openssl | git | artefato | ok |
| 3p-socketio-socket.io-client-cpp | git | artefato | ok |
| 3p-boost | git | artefato | ok |
| 3p-icu | git | artefato | ok |
| npm-server-Common-npm-shrinkwrap | npm-lock | artefato | ok |
| npm-server-DocService-npm-shrinkwrap | npm-lock | artefato | ok |
| npm-server-FileConverter-npm-shrinkwrap | npm-lock | artefato | ok |
| npm-server-Metrics-npm-shrinkwrap | npm-lock | artefato | ok |
| npm-server-npm-shrinkwrap | npm-lock | artefato | ok |
| npm-web-apps-build-package-lock | npm-lock | build | ok |
| npm-tools-lock | npm-lock | build | ok |
| sharp-libvips | apt | artefato | ok |
| wasm-engine | wasm | artefato | ok |
| wasm-fonts | wasm | artefato | ok |
| wasm-spell | wasm | artefato | ok |
| wasm-zlib | wasm | artefato | ok |
| wasm-drawingfile | wasm | artefato | ok |
| glue-engine | glue | artefato | ok |
| glue-spell | glue | artefato | ok |
| glue-zlib | glue | artefato | ok |
| glue-fonts | glue | artefato | ok |
| glue-fonts-native | glue | artefato | ok |
| glue-drawingfile | glue | artefato | ok |
| glue-libheif-bundle | glue | artefato | ok |
