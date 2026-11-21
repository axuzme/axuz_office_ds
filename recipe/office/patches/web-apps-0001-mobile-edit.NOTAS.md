# web-apps-0001-mobile-edit.patch

Religa a edicao no navegador do celular do ONLYOFFICE Community web-apps (tag v10.0.0.176, AGPL-3.0). Patch proprio da Axuz, com aviso "Modified by Axuz" (copyright Ascensio mantido) em cada arquivo.

## O que foi religado
Os `apps/*/mobile/src/lib/patch.jsx` eram stubs (`isSupportEditFeature` => false). Agora:
- documenteditor: `isSupportEditFeature`=true, `getUndoRedo`, `getToolbarOptions` (Editar/Adicionar), `getEditCommentControllers`, `initThemeColors`, `initFonts` (fontes, negrito/italico/sublinhado/tachado, listas), `initEditorStyles` (estilos de paragrafo), `initTableTemplates`, `updateChartStyles`, `initFocusObjects` (store.intf: abas text/paragraph/table/image/shape/chart/header/hyperlink), `ContextMenu.mapMenuItems/handleMenuItemClick` (cortar/copiar/colar, mesclar/dividir, excluir, excluir tabela, editar, adicionar/editar link, comentario).
- presentationeditor: mesma interface; `initEditorStyles` liga temas/layouts de slide (`asc_onInitEditorStyles`, `asc_onUpdateLayout`, `asc_onUpdateThemeIndex`); foco por tipos Slide/Shape/Chart/Image/Table; menu de contexto de edicao.
- spreadsheeteditor: interface propria do SSE (`toolbarOptions.getUndoRedo/getEditOptions`, `initCellInfo` com `asc_onSelectionChanged`, `initEditorStyles`, `initFonts`, `initThemeColors`); menu de contexto: cortar/copiar/colar, celula/editar, wrap/unwrap, mesclar/desmesclar, limpar, link, congelar paineis, inserir/excluir/ocultar linha/coluna, excluir objeto, comentario.
- novo `apps/common/mobile/lib/view/EditToolbarButtons.jsx`: botoes desfazer/refazer e Editar/Adicionar (icones ja existentes em common).

## O que ficou de fora
- visioeditor: nao alterado. Visio e somente leitura por natureza (sem telas de edicao em src/view/edit); `isSupportEditFeature` continua false.
- Nao testado em dispositivo/navegador com documento real (so build). Sem testes automatizados do SDK.
- Itens de menu de contexto de listas numeradas do DE (continuar/separar/iniciar numeracao: chaves `menuJoinList` etc. no locale) nao implementados.
- SSE: "Editar celula no texto" (editar conteudo inline) nao entra no menu; usa-se a barra de formulas. Comportamento exato dos textos "Cell"/"Edit" e aproximado.
- Icones RTL (`*-rtl.svg`) de undo/redo/edit nao usados.
- Bug pre-existente (upstream) em `store/focusObjects.js` do SSE: `setIsLocked` sobrescreve `isLocked` com false para celulas; nao corrigido.

## Origem / licenca do codigo reaproveitado
Nenhum codigo de terceiros/forks. Reaproveitado somente do historico do proprio repo AGPL (mesma licenca, autores ONLYOFFICE/Ascensio), reescrito contra os stores atuais:
- DE `ContextMenu.mapMenuItems` e getters de `focusObjects`: commit `b0c9a1c5d2^` (Apr 2021, "changes for private Editor controller").
- SSE `selections`/`asc_onSelectionChanged`: commit `7c72e8cb1b^` ("[SSE mobile] Changes for code decomposition").
- Registro de callbacks (fontes, estilos, tabelas, graficos, cores): `09102047c1^` (Main.jsx DE).
- Eventos de temas/layouts do PE conforme cliente desktop `apps/presentationeditor/main` (mesma arvore).
O resto e original Axuz.

## Como aplicar
```
cd .build/office/work/web-apps   # (ou outra copia limpa da tag v10.0.0.176)
patch -p1 < ../../patches/web-apps-0001-mobile-edit.patch     # ou: git apply ...
```
(dry-run verificado contra copia limpa; NAO aplicado em work/web-apps.) O webpack usa `../lib/patch` do proprio repo quando `web-apps-mobile/<editor>/patch.jsx` nao existe.

## Build / verificacao feita (em copia, tudo removido depois)
`cd vendor/framework7-react && npm ci` (cache em mobile-work/.npm-cache) e, para cada editor, sob `limitado.sh --perfil build --mem 3G --jobs 1`:
`TARGET_EDITOR=word|cell|slide NODE_ENV=production NODE_OPTIONS=--max-old-space-size=2048 node ./build/build.js`
Resultado: os 3 builds de producao "compiled with 2 warnings" (so limite de tamanho de asset), 0 erros; imports resolvem. (Build dev word tambem OK.)

## Como testar em viewport mobile
Servir o build (apps/<editor>/mobile/ via Document Server/ONLYOFFICE com `type=mobile` ou `embedded`) e abrir no Chrome DevTools > device emulation (ex. Pixel 7 / iPhone 14) ou Playwright `devices['Pixel 7']` / `devices['iPhone 14']` com UA mobile; abrir documento com `editorConfig.mode=edit`. Conferir: botoes Editar/Adicionar/undo-redo na barra, abas do painel Editar por selecao, menu de contexto ao tocar texto/tabela/forma, undo/redo funcionando.
