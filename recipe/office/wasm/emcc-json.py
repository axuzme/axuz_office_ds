#!/usr/bin/env python3
"""emcc-json.py — reimplementa, sem o build_tools, o laco de build do `Common/js/make.py` do core upstream
(removido em b77b3dc7e2): le o .json de modulo (mesmo formato do upstream) e produz <name>.wasm via emcc.

O QUE: compila cada fonte para .o (emcc -c), funde em all_N.o grupos com mais de 10 fontes (emcc -r) e linka
  com EXPORTED_FUNCTIONS. Mesma ordem/flags do make.py upstream => saida byte-identica com o mesmo emsdk.
ONDE: roda DENTRO do container emsdk, chamado pelos build.sh de office/wasm/{engine,zlib,spell}/inner.sh.
USO: emcc-json.py <modulo.json> <workdir> <outdir> [--asm] [--legacy]
  workdir = pasta de onde os caminhos relativos do json valem (ex.: core/OfficeUtils/js); outdir recebe
  <name>.wasm (ou <name>.js + .js.mem com --asm). Determinismo: sem timestamps, ordem fixa de arquivos.
"""
import json, os, shlex, subprocess, sys

# run — executa um comando e aborta com o rc dele. Onde: todas as etapas de compilacao abaixo.
def run(cmd, cwd):
    print("+ " + cmd, flush=True)
    r = subprocess.run(cmd, shell=True, cwd=cwd)
    if r.returncode != 0:
        sys.exit("emcc-json: falhou (rc=%d): %s" % (r.returncode, cmd[:300]))

# resolve_ci — acha `rel` (relativo a work) ignorando caixa, so no ultimo componente. O upstream compilava em FS
# insensivel a caixa (Windows/macOS): o json lista `CWmfInterpretator.cpp` e o arquivo e `cwmfinterpretator.cpp`.
# Onde: build, para cada fonte listada. Devolve o caminho como existe em disco (ou o original se nao achar).
def resolve_ci(work, rel):
    full = os.path.join(work, rel)
    if os.path.isfile(full):
        return rel
    d, b = os.path.split(full)
    if os.path.isdir(d):
        for n in sorted(os.listdir(d)):
            if n.lower() == b.lower():
                return os.path.join(os.path.dirname(rel), n)
    return rel

# build — compila o modulo `data` (dict do json) em workdir e copia o resultado para outdir.
# Onde: main. Replica make.py:exec_wasm (flags, -I/-D globais, ordem dos .o, merge >10 fontes).
def build(data, work, outdir, wasm, legacy=False):
    flags = list(data["compiler_flags"]) + (["-s WASM=1"] if wasm else ["-s WASM=0", "--closure 0", "-s MIN_IE_VERSION=11"])
    if not wasm and data.get("embed_mem_file"):
        flags.append("--memory-init-file 0")
    for inc in data["include_path"]: flags.append("-I" + inc)
    for d in data["define"]: flags.append("-D" + d)
    if not wasm:
        flags += ["-DBUILDING_ASMJS_MODULE", "-D_ARM_ALIGN_"]
    # legacy = make.py upstream de 2022-08 (so -Wno-deprecated-register); o atual acrescenta mais 3 flags
    flags += ["-Wno-deprecated-register"] if legacy else ["-Wno-deprecated-non-prototype", "-Wno-deprecated-register", "-Wno-register", "-fvisibility=hidden"]
    args = " ".join(flags) + " "
    objdir = os.path.join(work, "o"); os.makedirs(objdir, exist_ok=True)
    libs = ""
    for idx, grp in enumerate(data["compile_files_array"]):
        key = grp["name"] if legacy else str(idx)
        sub = os.path.join(objdir, key); os.makedirs(sub, exist_ok=True)
        extra = ""
        for inc in grp.get("include_path") or []: extra += "-I" + inc + " "
        for d in grp.get("define") or []: extra += "-D" + d + " "
        tl = ""
        for item in grp["files"]:
            stem = os.path.splitext(os.path.basename(item))[0]
            o = "o/%s/%s.o" % (key, stem)
            if not os.path.isfile(os.path.join(work, o)):
                run("emcc -o %s -c %s%s%s" % (o, args, extra, shlex.quote(resolve_ci(work, os.path.join(grp["folder"], item)))), work)
            tl += o + " "
        if len(grp["files"]) > 10:
            allo = "o/%s/%s.o" % (key, grp["name"]) if legacy else "o/%d/all_%d.o" % (idx, idx)
            if not os.path.isfile(os.path.join(work, allo)):
                run("emcc -o %s -r %s%s%s" % (allo, args, extra, tl), work)
            libs += allo + " "
        else:
            libs += tl
    exp = "-s EXPORTED_FUNCTIONS=\"[" + ",".join("'%s'" % f for f in data["exported_functions"]) + "]\" "
    srcs = "".join(s + " " for s in (data.get("sources") or []))
    run("emcc -o %s.js %s%s%s%s" % (data["name"], args, exp, srcs, libs), work)
    os.makedirs(outdir, exist_ok=True)
    for ext in ((".wasm",) if wasm else (".js", ".js.mem")):
        p = os.path.join(work, data["name"] + ext)
        if os.path.isfile(p):
            os.replace(p, os.path.join(outdir, data["name"] + ("" if wasm else "_ie") + ext if ext == ".js" and not wasm else data["name"] + ext))
    if wasm and os.path.isfile(os.path.join(work, data["name"] + ".js")):
        # runtime emscripten cru: o inner.sh o compoe com o wrapper do sdkjs (glue.js) para gerar o <name>.js final
        os.replace(os.path.join(work, data["name"] + ".js"), os.path.join(outdir, data["name"] + ".emcc.js"))

# main — parse de argumentos e dispatch. Onde: linha de comando dos inner.sh.
def main():
    if len(sys.argv) < 4: sys.exit(__doc__)
    spec, work, out = sys.argv[1:4]
    data = json.load(open(spec))
    build(data, os.path.abspath(work), os.path.abspath(out), "--asm" not in sys.argv, "--legacy" in sys.argv)

if __name__ == "__main__":
    main()
