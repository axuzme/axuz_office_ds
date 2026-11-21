#!/usr/bin/env python3
"""axuz_ops/office/lib/relativize-symlinks.py — troca symlink ABSOLUTO do sysroot por RELATIVO ao proprio sysroot.

O que: `docker export` do rootfs xenial traz symlinks como /lib/x86_64-linux-gnu/libgcc_s.so.1. O tarball upstream os tinha
  relativos. Com absoluto, o ld resolve o alvo no HOST (ubuntu 24.04, glibc 2.35) e o link falha com
  `pthread_key_create@GLIBC_2.34` (build real do v8, estagio server).
Onde: stages/10-sysroot.sh, depois do tar -x. Uso: relativize-symlinks.py <raiz-do-sysroot>
Efeito: so reescreve link absoluto cujo alvo existe DENTRO do sysroot; imprime a contagem. Alvo ausente = mantem (pendurado).
"""
import os
import sys


def relativize(root):
    """Reescreve os symlinks absolutos sob root; devolve quantos mudou. Chamada por main()."""
    root = os.path.abspath(root)
    n = 0
    for d, dirs, files in os.walk(root):
        for name in dirs + files:
            p = os.path.join(d, name)
            if not os.path.islink(p):
                continue
            t = os.readlink(p)
            if not t.startswith("/"):
                continue
            dest = os.path.join(root, t.lstrip("/"))
            if not os.path.lexists(dest):
                continue
            rel = os.path.relpath(dest, d)
            os.remove(p)
            os.symlink(rel, p)
            n += 1
    return n


def main():
    """Entrada de linha de comando."""
    if len(sys.argv) != 2 or not os.path.isdir(sys.argv[1]):
        sys.exit("uso: relativize-symlinks.py <raiz-do-sysroot>")
    print("symlinks absolutos -> relativos: %d" % relativize(sys.argv[1]))


if __name__ == "__main__":
    main()
