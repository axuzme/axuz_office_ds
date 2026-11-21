#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# office/wasm/drawingfile/make_wasm.py — compila o drawingfile.wasm (PDF/XPS/DjVu/OFD) do fonte C++ do ONLYOFFICE core.
#
# O QUE: substitui, de forma deterministica e sem rede, o que o core removeu no commit b77b3dc7e2 (2026-05-17):
#   Common/js/make.py + DesktopEditor/graphics/pro/js/{before,after,make}.py. Le o drawingfile.json (lista de fontes,
#   flags, exports), prepara uma arvore de trabalho PATCHADA (o core montado e somente-leitura), compila cada fonte
#   com `emcc -c` em paralelo e linka na ORDEM do json (a ordem fixa e parte do determinismo).
# ONDE: roda DENTRO do container emsdk (imagem por digest em emsdk.lock), chamado por build.sh. Nao usa a rede.
# ENTRADAS: --core (repo core do lock, ro), --icu (checkout do ICU no commit do deps.lock, ro), --recipe (esta pasta, ro),
#   --work (arvore de trabalho, descartavel), --out (saida). SAIDA: <out>/obj-link/drawingfile.{js,wasm} (cru, do emcc).
# EFEITO: so escreve em --work e --out.
import argparse, concurrent.futures as cf, json, os, shlex, shutil, subprocess, sys, time

# DIRS_CORE: subarvores do core que o drawingfile.json referencia (resto do core nao entra: boost, v8, etc).
DIRS_CORE = ["DesktopEditor", "PdfFile", "XpsFile", "DjVuFile", "OfficeUtils", "UnicodeConverter", "DocxRenderer",
             "OFDFile", "OdfFile", "OOXML/Base", "Common/3dParty/openssl", "Common/3dParty/cryptopp",
             "Common/3dParty/icu", "Common/3dParty/libxml"]
NOOP_UPSTREAM = ("ftgrays3.patch", "ftobjs2.patch")
IGNORE = shutil.ignore_patterns(".git", "icubuilds-mac", "*.o", "*.a")


def log(msg):
    """O que: log com carimbo. Onde: todo o driver."""
    print("[make_wasm %s] %s" % (time.strftime("%H:%M:%S"), msg), flush=True)


def read(p):
    """O que: le arquivo texto utf-8 (preserva BOM). Onde: patches e replace_in_file."""
    with open(p, "r", encoding="utf-8", newline="") as f:
        return f.read()


def write(p, s):
    """O que: escreve texto utf-8 sem traduzir fim de linha. Onde: replace_in_file/apply_patch."""
    with open(p, "w", encoding="utf-8", newline="") as f:
        f.write(s)


def replace_in_file(path, old, new):
    """O que: troca exata de trecho; FALHA se o trecho nao existe (patch silencioso e proibido).
    Onde: prepare_tree (equivalente ao base.replaceInFile do build_tools, so que fail-closed)."""
    s = read(path)
    if old not in s:
        raise SystemExit("PATCH_NAO_APLICA: trecho ausente em %s: %r" % (path, old[:80]))
    write(path, s.replace(old, new))


def apply_patch(path, patch):
    """O que: aplica um patch no formato <<<<<<< velho ======= novo >>>>>>> do core (vira #if 0/#else/#endif).
    COMPATIBILIDADE COM O UPSTREAM: o base.replaceInFile do build_tools nao falha quando o trecho nao existe, e dois dos
    patches de freetype (ftgrays3, ftobjs2: `ft_longjmp` -> `ft_longjmp_ex`) nunca casaram com o fonte (indentacao). Para
    gerar o mesmo binario esses viram no-op AQUI TAMBEM, mas logados; qualquer outro patch ausente continua fatal.
    Onde: freetype (ftgrays/smooth/ftobjs/ttcmap/sfnt/ftsystem)."""
    pc = read(patch)
    i1, i2, i3 = pc.find("<<<<<<<"), pc.find("======="), pc.find(">>>>>>>")
    old = pc[i1 + 7:i2]
    new = "\n#if 0" + old + "#else" + pc[i2 + 7:i3] + "#endif\n"
    if old not in read(path) and os.path.basename(patch) in NOOP_UPSTREAM:
        log("patch %s: trecho ausente em %s (no-op identico ao upstream)" % (os.path.basename(patch), path))
        return
    replace_in_file(path, old, new)


def copytree(src, dst):
    """O que: copia arvore (ou arquivo) sem .git. Onde: montagem da arvore de trabalho."""
    if os.path.isdir(src):
        shutil.copytree(src, dst, ignore=IGNORE, symlinks=True)
    else:
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(src, dst)


def run_libxml_fetch(a, libxml_dir):
    """O que: reproduz Common/3dParty/libxml/fetch.py do core sem rede: o `git clone`+`checkout` viram copia do
    checkout pinado (--libxml, ja no commit do fetch.py) e os replaceInFile do script rodam como estao.
    Falha se o commit citado no fetch.py != o que veio em --libxml. Onde: prepare_tree."""
    src = read(os.path.join(libxml_dir, "fetch.py"))
    want = [t for t in __import__("re").findall(r'"checkout", "([0-9a-f]{40})"', src)]
    got = open(os.path.join(a.libxml, ".axuz-commit")).read().strip()
    if want != [got]:
        raise SystemExit("LIBXML_PIN: fetch.py pede %s, recebi %s" % (want, got))

    class FakeBase:
        """Substitui o modulo `base` do build_tools so no que o fetch.py usa."""
        copied = False

        @staticmethod
        def is_dir(p):
            return FakeBase.copied and os.path.isdir(p)

        @staticmethod
        def cmd(prog, args):
            if args[0] == "clone":
                shutil.copytree(a.libxml, "libxml2", ignore=shutil.ignore_patterns(".git", ".axuz-commit"))
                FakeBase.copied = True

        @staticmethod
        def cmd_in_dir(d, prog, args):
            pass

        @staticmethod
        def replaceInFile(p, old, new):
            replace_in_file(p, old, new)

        replaceInFileUtf8 = replaceInFile

    cwd = os.getcwd()
    os.chdir(libxml_dir)
    try:
        sys.modules["base"] = FakeBase
        sys.path.insert(0, "/nonexistent")
        code = src.replace("sys.path.append('../../../../build_tools/scripts')", "")
        exec(compile(code, "fetch.py", "exec"), {"__name__": "__fetch__"})
        if not os.path.isfile("libxml2/xmlIO.c"):
            raise SystemExit("LIBXML: fetch.py nao materializou libxml2")
    finally:
        os.chdir(cwd)
        sys.modules.pop("base", None)


def prepare_tree(a):
    """O que: monta /work/core (copia dos DIRS_CORE + ICU) e aplica o equivalente do before.py (patches de wasm).
    Onde: inicio do build. Retorna o diretorio de trabalho (cwd do json: DesktopEditor/graphics/pro/js)."""
    core = os.path.join(a.work, "core")
    if os.path.isdir(core):
        shutil.rmtree(core)
    for d in DIRS_CORE:
        copytree(os.path.join(a.core, d), os.path.join(core, d))
    # arquivos soltos de Common/ (kernel_config.h, OfficeFileFormatDefines.h, ...): cabecalhos que o codigo inclui por ../../Common/
    src_common = os.path.join(a.core, "Common")
    for fn in sorted(os.listdir(src_common)):
        if os.path.isfile(os.path.join(src_common, fn)):
            copytree(os.path.join(src_common, fn), os.path.join(core, "Common", fn))
    # terceiros buscados pelo build_tools no checkout (libxml2, icu): descartados; entram so os pinados do lock
    for stale in ("Common/3dParty/libxml/libxml2", "Common/3dParty/icu/icu"):
        shutil.rmtree(os.path.join(core, stale), ignore_errors=True)
    # ICU: so source/common (o que o json compila) + LICENSE; o resto (i18n, data, tools, testes) nao entra
    icu_dst = os.path.join(core, "Common/3dParty/icu/icu")
    copytree(os.path.join(a.icu, "icu4c/source/common"), os.path.join(icu_dst, "source/common"))
    shutil.copy2(os.path.join(a.icu, "icu4c/LICENSE"), os.path.join(icu_dst, "LICENSE"))
    wd = os.path.join(core, "DesktopEditor/graphics/pro/js")
    # receita (json, wasm/src, wasm/patches) por cima do core (que ja tem serialize.h, HTMLRendererText, Text.h)
    for sub in ("wasm/src", "wasm/patches"):
        shutil.copytree(os.path.join(a.recipe, sub), os.path.join(wd, sub), dirs_exist_ok=True)
    shutil.copy2(os.path.join(a.recipe, "drawingfile.json"), os.path.join(wd, "drawingfile.json"))
    de = os.path.join(core, "DesktopEditor")
    # --- libxml2 (GNOME, commit do fetch.py do proprio core): executa o fetch.py pinado com um `base` de mentira que
    # copia o checkout (--libxml) em vez de clonar; os replaceInFile do fetch.py rodam de verdade (mesmos patches).
    run_libxml_fetch(a, os.path.join(core, "Common/3dParty/libxml"))
    # --- freetype 2.10.4 (copia + patches setjmp -> excecoes C++)
    ft = os.path.join(wd, "freetype-2.10.4")
    shutil.copytree(os.path.join(de, "freetype-2.10.4"), ft)
    P = os.path.join(wd, "wasm/patches/")
    shutil.copy2(ft + "/src/smooth/ftgrays.c", ft + "/src/smooth/ftgrays.cpp")
    for n in ("ftgrays1", "ftgrays2", "ftgrays3"):
        apply_patch(ft + "/src/smooth/ftgrays.cpp", P + n + ".patch")
    shutil.copy2(ft + "/src/smooth/smooth.c", ft + "/src/smooth/smooth.cpp")
    apply_patch(ft + "/src/smooth/smooth.cpp", P + "smooth.patch")
    apply_patch(ft + "/src/base/ftobjs.c", P + "ftobjs1.patch")
    apply_patch(ft + "/src/base/ftobjs.c", P + "ftobjs2.patch")
    shutil.copy2(ft + "/src/sfnt/ttcmap.c", ft + "/src/sfnt/ttcmap.cpp")
    apply_patch(ft + "/src/sfnt/ttcmap.cpp", P + "ttcmap.patch")
    shutil.copy2(ft + "/src/sfnt/sfnt.c", ft + "/src/sfnt/sfnt.cpp")
    apply_patch(ft + "/src/sfnt/sfnt.cpp", P + "sfnt.patch")
    apply_patch(ft + "/builds/unix/ftsystem.c", P + "ftsystem.patch")
    # --- ICU: sem arquivo de dados (udata devolve NULL); libpng sem console io; openssl sha512 cast
    replace_in_file(core + "/Common/3dParty/icu/icu/source/common/udata.cpp", "\n{\n    UDataMemory tData;",
                    "\n{\n#ifdef BUILDING_WASM_MODULE\nreturn NULL;\n#endif\n    UDataMemory tData;")
    replace_in_file(de + "/cximage/png/pnglibconf.h", "#define PNG_CONSOLE_IO_SUPPORTED", "//#define PNG_CONSOLE_IO_SUPPORTED")
    gen_opensslconf(core + "/Common/3dParty/openssl")
    replace_in_file(core + "/Common/3dParty/openssl/openssl/crypto/sha/sha512.c", "const SHA_LONG64 *W = in;",
                    "const SHA_LONG64 *W = (const SHA_LONG64*)in;")
    return wd


def gen_opensslconf(base):
    """O que: gera include/openssl/opensslconf.h (o build_tools rodava ./config+make do openssl 1.1.1f e apontava o include para
    build/linux_64/include). Aqui so o cabecalho: `perl Configure` + dofile.pl sobre a copia de trabalho, sem make e sem rede.
    Onde: prepare_tree (Decrypt.cc inclui sha512.c, que pede openssl/opensslconf.h)."""
    src = base + "/openssl"
    subprocess.run(["perl", "Configure", "linux-x86_64", "enable-md2", "no-shared", "no-asm"], cwd=src, check=True,
                   stdout=subprocess.DEVNULL)
    dst = base + "/build/linux_64/include/openssl"
    os.makedirs(dst, exist_ok=True)
    r = subprocess.run(["perl", "-I.", "-Mconfigdata", "util/dofile.pl", "-oMakefile", "include/openssl/opensslconf.h.in"],
                       cwd=src, check=True, stdout=subprocess.PIPE)
    if b"OPENSSL_" not in r.stdout:
        raise RuntimeError("opensslconf.h gerado vazio")
    with open(dst + "/opensslconf.h", "wb") as f:
        f.write(r.stdout)


def emcc_args(j, wd, wasm):
    """O que: monta a linha de flags comum (compile e link) a partir do json. Ordem identica a do Common/js/make.py
    do core (flags, -s WASM, -I, -D, supressoes, -fvisibility=hidden). Onde: compile_one e link."""
    f = list(j["compiler_flags"])
    f.append("-s WASM=1" if wasm else "-s WASM=0")
    if not wasm:
        f += ["--closure 0", "-s MIN_IE_VERSION=11", "--memory-init-file 0"]
    f += ["-I" + i for i in j["include_path"]] + ["-D" + d for d in j["define"]]
    if not wasm:
        f += ["-DBUILDING_ASMJS_MODULE", "-D_ARM_ALIGN_"]
    f += ["-Wno-deprecated-non-prototype", "-Wno-deprecated-register", "-Wno-register", "-fvisibility=hidden"]
    # determinismo: nenhum caminho do host nem data no objeto
    toks = []
    for item in f:
        toks += shlex.split(item)
    toks += ["-Wno-builtin-macro-redefined", '-D__DATE__="redacted"', '-D__TIME__="redacted"', '-D__TIMESTAMP__="redacted"']
    return toks


def plan(j, wd):
    """O que: lista ordenada (grupo, fonte, objeto, flags-do-grupo). Onde: compile e link (mesma ordem = mesmo wasm)."""
    out = []
    for gi, g in enumerate(j["compile_files_array"]):
        extra = []
        extra += ["-I" + i for i in (g.get("include_path") or [])]
        extra += ["-D" + d for d in (g.get("define") or [])]
        for f in g["files"]:
            name = os.path.splitext(os.path.basename(f))[0]
            out.append((gi, os.path.normpath(os.path.join(wd, g["folder"], f)), "o/%d/%s.o" % (gi, name), extra))
    return out


def compile_one(job, base_flags, wd, incremental=False):
    """O que: `emcc -c` de um arquivo. Onde: pool de compilacao. Retorna (objeto, rc, stderr)."""
    gi, src, obj, extra = job
    os.makedirs(os.path.dirname(os.path.join(wd, obj)), exist_ok=True)
    if incremental and os.path.isfile(os.path.join(wd, obj)):
        return obj, 0, ""
    cmd = ["emcc", "-o", obj, "-c"] + base_flags + extra + [src]
    r = subprocess.run(cmd, cwd=wd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    return obj, r.returncode, r.stderr


def build(a, wasm):
    """O que: compila todos os objetos e linka. Onde: main (wasm e, opcional, asm.js do IE).
    Efeito: <work>/.../js/drawingfile.{js,wasm|js.mem}. Falha na primeira unidade que nao compila (lista todas)."""
    wd = os.path.join(a.work, "core/DesktopEditor/graphics/pro/js")
    j = json.load(open(os.path.join(wd, "drawingfile.json"), encoding="utf-8"))
    flags = emcc_args(j, wd, wasm)
    jobs = plan(j, wd)
    if not a.incremental:
        shutil.rmtree(os.path.join(wd, "o"), ignore_errors=True)
    log("compilando %d unidades (%s) com %d jobs" % (len(jobs), "wasm" if wasm else "asm", a.jobs))
    fails = []
    with cf.ThreadPoolExecutor(max_workers=a.jobs) as ex:
        futs = [ex.submit(compile_one, jb, flags, wd, a.incremental) for jb in jobs]
        for n, fu in enumerate(futs):
            obj, rc, err = fu.result()
            if rc:
                fails.append((obj, err))
                log("FALHA %s\n%s" % (obj, err[-3000:]))
            elif n % 100 == 0:
                log("  %d/%d" % (n, len(jobs)))
    if fails:
        raise SystemExit("COMPILACAO_FALHOU: %d unidades: %s" % (len(fails), ", ".join(o for o, _ in fails)))
    # link: objetos na ordem do json; grupos grandes viram all_N.o via -r (igual ao make.py do core)
    libs, by_group = [], {}
    for gi, src, obj, extra in jobs:
        by_group.setdefault(gi, []).append(obj)
    for gi in sorted(by_group):
        objs = by_group[gi]
        if len(objs) > 10:
            allo = "o/%d/all_%d.o" % (gi, gi)
            r = subprocess.run(["emcc", "-o", allo, "-r"] + flags + objs, cwd=wd,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            if r.returncode:
                raise SystemExit("LINK_PARCIAL_FALHOU grupo %d:\n%s" % (gi, r.stderr[-3000:]))
            libs.append(allo)
        else:
            libs += objs
    exp = "-sEXPORTED_FUNCTIONS=[" + ",".join("'%s'" % e for e in j["exported_functions"]) + "]"
    for stale in ("drawingfile.js", "drawingfile.wasm", "drawingfile.js.mem"):
        if os.path.exists(os.path.join(wd, stale)):
            os.remove(os.path.join(wd, stale))
    cmd = ["emcc", "-o", "drawingfile.js"] + flags + [exp] + libs
    log("link: %d objetos" % len(libs))
    r = subprocess.run(cmd, cwd=wd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    sys.stderr.write(r.stderr[-6000:])
    if r.returncode:
        raise SystemExit("LINK_FALHOU")
    dst = os.path.join(a.out, "obj-wasm" if wasm else "obj-asm")
    os.makedirs(dst, exist_ok=True)
    for n in ("drawingfile.js", "drawingfile.wasm" if wasm else "drawingfile.js.mem"):
        shutil.copy2(os.path.join(wd, n), os.path.join(dst, n))
    log("ok: %s" % dst)


def main():
    """O que: entrada. Onde: build.sh (docker run ... python3 make_wasm.py)."""
    ap = argparse.ArgumentParser()
    for k in ("core", "icu", "libxml", "recipe", "work", "out"):
        ap.add_argument("--" + k, required=True)
    ap.add_argument("--jobs", type=int, default=os.cpu_count() or 2)
    ap.add_argument("--ie", action="store_true", help="tambem gera o asm.js do IE (drawingfile_ie.js)")
    ap.add_argument("--prepare-only", action="store_true")
    ap.add_argument("--incremental", action="store_true", help="DEV: reaproveita .o existentes e a arvore (nunca no build oficial)")
    ap.add_argument("--reuse-tree", action="store_true", help="DEV: nao remonta a arvore de trabalho")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    os.makedirs(a.work, exist_ok=True)
    if a.reuse_tree:
        log("DEV: reaproveitando a arvore patchada")
    else:
        log("preparando arvore patchada")
        prepare_tree(a)
    if a.prepare_only:
        return
    build(a, True)
    if a.ie:
        build(a, False)


if __name__ == "__main__":
    main()
