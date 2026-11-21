#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""build_inner.py — compila sdkjs/common/libfont/engine/{fonts.wasm,fonts.js,fonts_ie.js} do FONTE C++ do ONLYOFFICE core.

O QUE: reproduz, sem o build_tools/Common/js/make.py (removidos do core upstream em 2026-05), o build emscripten do
  motor de fontes (FreeType 2.10.4 + HarfBuzz + hyphen + zlib + raster + metafile) descrito em libfont.json.
ONDE: roda DENTRO do container emscripten (imagem fixada por digest em emsdk.lock), chamado por build.sh.
  Entradas (env): CORE_PIN (sha do core com a receita), JOBS. Montagens: /core (ro, git), /sdkjs (ro), /recipe (ro), /out.
FLUXO: git archive do core@CORE_PIN -> /w/tree; aplica before.py (patches FreeType); compila cada .c/.cpp em
  paralelo; link; monta fonts.js a partir de engine/module_js.js; (asm.js) fonts_ie.js; copia para /out.
DETERMINISMO: caminhos fixos (/w/tree), SOURCE_DATE_EPOCH fixo, ordem de link fixa, jobs so paralelizam compilacao.
"""
import json, os, re, shutil, subprocess, sys, concurrent.futures as cf

TREE = "/w/tree"
WORK = TREE + "/DesktopEditor/fontengine/js"
PATHS = ["DesktopEditor", ":(glob)Common/*", "Common/js", "Common/license", "Common/3dParty/harfbuzz", "Common/3dParty/hyphen",
         "Common/3dParty/brotli", "OfficeUtils"]


def sh(args, cwd=None, env=None):
    """O que: executa um comando e aborta se falhar. Onde: todo passo externo deste script."""
    r = subprocess.run(args, cwd=cwd, env=env)
    if r.returncode != 0:
        sys.exit("FALHOU (%d): %s" % (r.returncode, " ".join(args[:6])))


def read(p):
    """O que: le arquivo como texto utf-8. Onde: patches e templates."""
    with open(p, encoding="utf-8", newline="") as f:
        return f.read()


def write(p, s):
    """O que: grava texto utf-8 sem conversao de EOL. Onde: patches e saida."""
    with open(p, "w", encoding="utf-8", newline="") as f:
        f.write(s)


def replace_in_file(p, old, new):
    """O que: substitui TODAS as ocorrencias (como base.replaceInFile). Aborta se `old` nao existe (patch silencioso e proibido)."""
    s = read(p)
    if old not in s:
        sys.exit("PATCH_NAO_CASOU: %s :: %r" % (p, old[:60]))
    write(p, s.replace(old, new))


def apply_patch(f, patch):
    """O que: aplica patch no formato <<<<<<< velho ======= novo >>>>>>> (Common/js/common.py: trechos com strip)."""
    c = read(patch)
    i1, i2, i3 = c.find("<<<<<<<"), c.find("======="), c.find(">>>>>>>")
    replace_in_file(f, c[i1 + 7:i2].strip(), c[i2 + 7:i3].strip())


def extract_tree():
    """O que: extrai do git do core, no sha fixado, so os diretorios necessarios. Onde: passo 1."""
    pin = os.environ["CORE_PIN"]
    shutil.rmtree("/w", ignore_errors=True)
    os.makedirs(TREE)
    sh(["git", "config", "--global", "--add", "safe.directory", "*"])
    g = ["git", "-C", "/core"]
    sh(g + ["cat-file", "-e", pin + "^{commit}"])
    p = subprocess.Popen(g + ["archive", pin] + PATHS, stdout=subprocess.PIPE)
    t = subprocess.run(["tar", "-x", "-C", TREE], stdin=p.stdout)
    p.stdout.close()
    if p.wait() != 0 or t.returncode != 0:
        sys.exit("git archive falhou")


def fetch_3p():
    """O que: materializa harfbuzz e brotli (checkouts de terceiros, fora do git do core) a partir dos clones pinados do --core,
    no MESMO sha que o make.py de cada um (core@pin) exige; aplica o patch hb-ft.cc da casa. Onde: logo apos extract_tree."""
    for name, sub in (("harfbuzz", "src"), ("brotli", "c")):
        mk = read("%s/Common/3dParty/%s/make.py" % (TREE, name))
        sha = re.search(r'checkout",\s*"([0-9a-f]{40})"', mk).group(1)
        dst = "%s/Common/3dParty/%s/%s" % (TREE, name, name)
        os.makedirs(dst)
        g = ["git", "-C", "/core/Common/3dParty/%s/%s" % (name, name)]
        sh(g + ["cat-file", "-e", sha + "^{commit}"])
        p = subprocess.Popen(g + ["archive", sha, sub], stdout=subprocess.PIPE)
        t = subprocess.run(["tar", "-x", "-C", dst], stdin=p.stdout)
        p.stdout.close()
        if p.wait() != 0 or t.returncode != 0:
            sys.exit("git archive %s falhou" % name)
    hs = os.environ["HYPHEN_PIN"]
    hdst = TREE + "/Common/3dParty/hyphen/hyphen"
    os.makedirs(hdst)
    g = ["git", "-C", "/core/Common/3dParty/hyphen/hyphen"]
    sh(g + ["cat-file", "-e", hs + "^{commit}"])
    p = subprocess.Popen(g + ["archive", hs], stdout=subprocess.PIPE)
    t = subprocess.run(["tar", "-x", "-C", hdst], stdin=p.stdout)
    p.stdout.close()
    if p.wait() != 0 or t.returncode != 0:
        sys.exit("git archive hyphen falhou")
    pf = TREE + "/Common/3dParty/harfbuzz/patch/hb-ft.cc.patch"
    c = read(pf)
    i1, i2, i3 = c.find("<<<<<<<"), c.find("======="), c.find(">>>>>>>")
    old = c[i1 + 7:i2]
    new = "\n#if 0" + old + "#else" + c[i2 + 7:i3] + "#endif\n"
    replace_in_file(TREE + "/Common/3dParty/harfbuzz/harfbuzz/src/hb-ft.cc", old, new)


def before():
    """O que: equivale a graphics/pro/js/before.py — copia o FreeType e aplica os patches da casa ONLYOFFICE."""
    js = TREE + "/DesktopEditor/graphics/pro/js"
    ft = js + "/freetype-2.10.4"
    shutil.copytree(TREE + "/DesktopEditor/freetype-2.10.4", ft)
    shutil.copy(ft + "/src/smooth/ftgrays.c", ft + "/src/smooth/ftgrays.cpp")
    for n in ("ftgrays1", "ftgrays2", "ftgrays3"):
        apply_patch(ft + "/src/smooth/ftgrays.cpp", js + "/wasm/patches/%s.patch" % n)
    shutil.copy(ft + "/src/smooth/smooth.c", ft + "/src/smooth/smooth.cpp")
    apply_patch(ft + "/src/smooth/smooth.cpp", js + "/wasm/patches/smooth.patch")
    for n in ("ftobjs1", "ftobjs2"):
        apply_patch(ft + "/src/base/ftobjs.c", js + "/wasm/patches/%s.patch" % n)
    shutil.copy(ft + "/src/sfnt/ttcmap.c", ft + "/src/sfnt/ttcmap.cpp")
    apply_patch(ft + "/src/sfnt/ttcmap.cpp", js + "/wasm/patches/ttcmap.patch")
    shutil.copy(ft + "/src/sfnt/sfnt.c", ft + "/src/sfnt/sfnt.cpp")
    apply_patch(ft + "/src/sfnt/sfnt.cpp", js + "/wasm/patches/sfnt.patch")
    apply_patch(ft + "/builds/unix/ftsystem.c", js + "/wasm/patches/ftsystem.patch")
    replace_in_file(TREE + "/DesktopEditor/cximage/png/pnglibconf.h", "#define PNG_CONSOLE_IO_SUPPORTED",
                    "//#define PNG_CONSOLE_IO_SUPPORTED")


def resolve_ci(folder, item):
    """O que: o upstream compila em FS case-insensitive (Windows/mac) e a lista cita 'CWmfInterpretator.cpp' onde o git tem
    'cwmfinterpretator.cpp'. Resolve cada segmento sem diferenciar maiusculas; exato primeiro. Aborta se ambiguo/ausente."""
    cur = os.path.join(WORK, folder)
    for seg in item.split("/"):
        cand = os.path.join(cur, seg)
        if not os.path.exists(cand):
            ms = [e for e in os.listdir(cur) if e.lower() == seg.lower()] if os.path.isdir(cur) else []
            if len(ms) != 1:
                sys.exit("ARQUIVO_NAO_ENCONTRADO: %s/%s" % (folder, item))
            cand = os.path.join(cur, ms[0])
        cur = cand
    return os.path.relpath(cur, WORK)


def flags_for(data, base_flags, wasm):
    """O que: monta a lista de flags do emcc como Common/js/make.py (includes, defines, extras). Onde: compile e link."""
    f = list(base_flags)
    f += ["-I" + i for i in data["include_path"]]
    f += ["-D" + d for d in data["define"]]
    if not wasm:
        f += ["-DBUILDING_ASMJS_MODULE", "-D_ARM_ALIGN_"]
    f += ["-Wno-deprecated-non-prototype", "-Wno-deprecated-register", "-Wno-register", "-fvisibility=hidden"]
    return f


def emcc_split(flags):
    """O que: expande flags do tipo '-s X=Y' em argv (o make.py passava por shell, que separava por espaco)."""
    out = []
    for fl in flags:
        out += fl.split(" ") if fl.startswith("-s ") or fl.startswith("--") else [fl]
    return out


def build_variant(data, wasm):
    """O que: compila todos os objetos (paralelo), faz o link e devolve o conteudo do <name>.js emscripten.
    Onde: uma vez para wasm e outra para asm.js (IE)."""
    base_flags = list(data["compiler_flags"])
    if wasm:
        base_flags.append("-s WASM=1")
    else:
        base_flags += ["-s WASM=0", "--closure 0", "-s MIN_IE_VERSION=11"]
        if data.get("embed_mem_file"):
            base_flags.append("--memory-init-file 0")
    flags = emcc_split(flags_for(data, base_flags, wasm))
    odir = WORK + ("/o_wasm" if wasm else "/o_asm")
    shutil.rmtree(odir, ignore_errors=True)
    jobs, libs = [], []
    for gi, grp in enumerate(data["compile_files_array"]):
        os.makedirs("%s/%d" % (odir, gi))
        extra = ["-I" + i for i in grp.get("include_path") or []] + ["-D" + d for d in grp.get("define") or []]
        objs = []
        for item in grp["files"]:
            stem = os.path.splitext(os.path.basename(item))[0]
            obj = "%s/%d/%s.o" % (odir, gi, stem)
            objs.append(obj)
            jobs.append(["emcc", "-o", obj, "-c"] + flags + extra + [resolve_ci(grp["folder"], item)])
        if len(grp["files"]) > 10:
            allo = "%s/%d/all_%d.o" % (odir, gi, gi)
            jobs.append(("LINK", ["emcc", "-o", allo, "-r"] + flags + extra + objs))
            libs.append(allo)
        else:
            libs += objs
    plain = [j for j in jobs if not isinstance(j, tuple)]
    n = int(os.environ.get("JOBS", "4"))
    with cf.ThreadPoolExecutor(n) as ex:
        res = list(ex.map(lambda a: subprocess.run(a, cwd=WORK, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True), plain))
    bad = [(a, r) for a, r in zip(plain, res) if r.returncode != 0]
    for a, r in bad[:5]:
        print("ERRO em", a[-1], "\n", "\n".join([l[:300] for l in r.stdout.splitlines() if "error" in l][:4]), file=sys.stderr)
    if bad:
        sys.exit("compilacao falhou em %d arquivo(s)" % len(bad))
    for j in jobs:
        if isinstance(j, tuple):
            sh(j[1], cwd=WORK)
    exp = "[" + ",".join("'%s'" % e for e in data["exported_functions"]) + "]"
    name = data["name"]
    sh(["emcc", "-o", name + ".js"] + flags + ["-s", "EXPORTED_FUNCTIONS=" + exp] + libs, cwd=WORK)
    return read(WORK + "/" + name + ".js")


def assemble(data, module_js, wasm):
    """O que: finalize do make.py — injeta o glue emscripten no template engine/module_js.js. Onde: gera fonts.js/fonts_ie.js."""
    cj = TREE + "/Common/js"
    t = read(WORK + "/" + data["base_js_content"])
    t = t.replace("//module", module_js)
    t = t.replace("//string_utf8", read(cj + "/string_utf8.js"))
    t = t.replace("//desktop_fetch", read(cj + "/desktop_fetch.js"))
    if not wasm:
        t = t.replace("//polyfill", read(cj + "/polyfill.js"))
    # after.py
    for a in ("__ATPOSTRUN__=[];", "__ATPOSTRUN__ = [];"):
        t = t.replace(a, '__ATPOSTRUN__=[function(){window["AscFonts"].onLoadModule();}];')
    t = t.replace("function getBinaryPromise(", "function getBinaryPromise2(")
    return t


def minify(path, sdkjs):
    """O que: min.py (Closure WHITESPACE_ONLY + cabecalho de licenca) quando o compiler.jar do sdkjs existe; senao so o cabecalho.
    Onde: fim do build. Sem jar o glue fica sem minificar (funcionalmente identico)."""
    jar = sdkjs + "/build/node_modules/google-closure-compiler-java/compiler.jar"
    hdr = read(TREE + "/Common/license/header.license")
    body = read(path)
    if os.path.isfile(jar):
        sh(["java", "-jar", jar, "--compilation_level", "WHITESPACE_ONLY", "--language_out", "ECMASCRIPT5_STRICT",
            "--js_output_file", path + ".min", "--js", path])
        body = read(path + ".min")
        os.remove(path + ".min")
    write(path, hdr + body)


def main():
    """O que: orquestra o build completo e copia as saidas para /out. Onde: ponto de entrada do container."""
    os.environ["SOURCE_DATE_EPOCH"] = "1765929600"
    extract_tree()
    # patches da casa ONLYOFFICE vem do proprio core@pin (graphics/pro/js/wasm/patches)
    fetch_3p()
    before()
    data = json.loads(read(WORK + "/libfont.json"))
    out = "/out"
    os.makedirs(out, exist_ok=True)
    want_asm = os.environ.get("WITH_ASM", "0") == "1"
    glue = build_variant(data, True)
    shutil.copy(WORK + "/fonts.wasm", out + "/fonts.wasm")
    write(out + "/fonts.js", assemble(data, glue, True))
    minify(out + "/fonts.js", "/sdkjs")
    shutil.copy(WORK + "/engine/module_native.js", out + "/fonts_native.js")
    if want_asm:
        glue = build_variant(data, False)
        write(out + "/fonts_ie.js", assemble(data, glue, False))
        minify(out + "/fonts_ie.js", "/sdkjs")
        if os.path.isfile(WORK + "/fonts.js.mem"):
            shutil.copy(WORK + "/fonts.js.mem", out + "/fonts_ie.js.mem")
    print("OK fonts build")


if __name__ == "__main__":
    main()
