#!/usr/bin/env python3
"""office/wasm/glue.py — regenera o glue JS (<modulo>.js) de um wasm do sdkjs a partir do runtime emscripten NOSSO.

O QUE: o <modulo>.js que o sdkjs distribui = wrapper escrito a mao (texto, versionado no sdkjs) + UMA linha com o runtime que o
  emcc gerou, com 2 ajustes do after.py (hook de inicializacao em __ATPOSTRUN__ e getBinaryPromise -> getBinaryPromise2).
  Aqui pegamos o wrapper do arquivo do sdkjs, trocamos SO a linha do runtime pela saida do NOSSO emcc (mesmos ajustes) e
  gravamos. Nao ha binario/minificado versionado: o runtime e gerado a cada build. Fail-closed: aborta se a estrutura nao casa.
ONDE: chamado por hzs_glue (_hzs-common.sh) apos o container emsdk de engine/spell/zlib; test.sh usa o glue gerado (par).
USO: glue.py <emcc.js> <glue-do-sdkjs.js> <saida.js>
PROVA: com o mesmo emsdk do upstream (engine, spell) a saida e byte-identica a do sdkjs (verificado por test.sh/tests do gate).
"""
import re, sys


def die(msg):
    """O que: erro fatal rc 3. Onde: toda validacao estrutural."""
    sys.exit("AXUZ-GLUE: " + msg)


def main():
    """O que: troca a linha do runtime emcc no wrapper do sdkjs pelo runtime novo (com os ajustes do after.py). Onde: CLI."""
    if len(sys.argv) != 4:
        die("uso: glue.py <emcc.js> <glue-sdkjs.js> <saida.js>")
    emcc_p, up_p, out_p = sys.argv[1:]
    emcc = open(emcc_p, encoding="utf-8", newline="").read().rstrip("\n")
    up = open(up_p, encoding="utf-8", newline="").read()
    m = re.search(r'^([ \t]*)(var Module=typeof Module[^\n]*)$', up, re.M)
    if not m or len(re.findall(r'^[ \t]*var Module=typeof Module', up, re.M)) != 1:
        die("wrapper sem exatamente 1 linha de runtime emcc (var Module=typeof Module...)")
    hook = re.search(r'__ATPOSTRUN__=\[(function\(\)\{[^\n]*?\})\];', m.group(2))
    if not hook:
        die("wrapper sem hook __ATPOSTRUN__=[function(){...}]")
    n = 0
    for old in ("__ATPOSTRUN__=[];", "__ATPOSTRUN__ = [];"):
        n += emcc.count(old)
        emcc = emcc.replace(old, "__ATPOSTRUN__=[" + hook.group(1) + "];")
    if n != 1:
        die("runtime emcc sem __ATPOSTRUN__ vazio unico (achou %d)" % n)
    if "function getBinaryPromise(" not in emcc:
        die("runtime emcc sem getBinaryPromise()")
    emcc = emcc.replace("function getBinaryPromise(", "function getBinaryPromise2(")
    out = up[:m.start(2)] + emcc + up[m.end(2):]
    open(out_p, "w", encoding="utf-8", newline="").write(out)
    print("glue: %s -> %s (%d bytes, %s)" % (up_p.split("/")[-1], out_p, len(out), "identico ao sdkjs" if out == up else "runtime novo"))


main()
