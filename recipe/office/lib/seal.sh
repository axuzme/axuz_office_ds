#!/usr/bin/env bash
# axuz_ops/office/lib/seal.sh — "sela" o artefato do DS: poda o que e blob alheio e inutil e registra a origem do que NOS compilamos.
#
# O QUE: duas funcoes, SOURCEAVEIS (nao ligam set -e):
#   seal_prune <artefato>          remove do artefato os binarios opacos de npm que o DocService nao usa (decisao: o Axuz
#                                  usa Postgres/Redis, roda so em Linux x64): oracledb (nenhum codigo do server o requer),
#                                  prebuilds dos bare-* (so valem no runtime Bare, nao no Node), win-ca/roots.exe e
#                                  winser/nssm*.exe (so Windows) e os intermediarios de compilacao do sharp (obj.target/*.o).
#                                  O sharp-linux-x64.node FICA: e compilado por nos (npm rebuild --build-from-source contra
#                                  a libvips do apt do snapshot; ver build_tools-0005) e entra no manifesto abaixo.
#   seal_manifest <artefato> <work> grava <artefato>/built-from-source.tsv (sha256, caminho no artefato, origem em <work>)
#                                  de todo ELF/.node do artefato cujo sha256 bate com um arquivo PRODUZIDO por este build
#                                  (mais novo que <work>/prepare.ok) nas pastas de saida de compilacao. O check-no-blob.sh
#                                  so aceita binario fora da allowlist se estiver neste manifesto E a origem ainda existir
#                                  na arvore com o mesmo hash (--verify-tree). Sem build, sem manifesto, sem aceite.
# ONDE: stages/55-seal.sh (depois do server, antes do verify); tests/unit.d/60-office-seal-artefato.sh.
# POR QUE: 61 binarios reprovaram o verify; 23 sao saida do nosso C++/node-gyp (hash registrado, nao allowlist manual)
#   e o resto e blob de terceiro sem uso (removido, nunca afrouxando o gate).

# SEAL_BUILT_DIRS — pastas (relativas a <work>) onde o build deposita binarios que ele proprio compilou.
SEAL_BUILT_DIRS=(core/build/bin/linux_64 core/build/lib/linux_64 core/Common/3dParty/icu/linux_64/build)

# seal_prune <artefato> — apaga os blobs opacos nao usados. Efeito: remove arquivos/pastas dentro do artefato.
# Onde: stages/55-seal.sh.
seal_prune() {
  local a="$1" d
  [[ -d "$a" ]] || { echo "AXUZ-SEAL: artefato ausente: $a" >&2; return 2; }
  while IFS= read -r d; do rm -rf -- "$d"; done < <(find "$a" -type d -path '*/node_modules/oracledb' -prune)
  while IFS= read -r d; do rm -rf -- "$d"; done < <(find "$a" -type d -name prebuilds -path '*/node_modules/bare-*/prebuilds' -prune)
  find "$a" -type f \( -path '*/node_modules/win-ca/lib/roots.exe' -o -path '*/node_modules/winser/bin/nssm*.exe' \) -delete
  while IFS= read -r d; do rm -rf -- "$d"; done < <(find "$a" -type d -path '*/node_modules/sharp/build/Release/obj.target' -prune)
  return 0
}

# seal_manifest <artefato> <work> [ws] — escreve <artefato>/built-from-source.tsv. Efeito: cria o arquivo; rc 0 sempre
# (o veredito e do check-no-blob). Onde: stages/55-seal.sh.
seal_manifest() {
  local a="$1" w="$2" ws="${3:-/ws}" idx d f m sha src rel
  idx="$(mktemp)"
  local roots=()
  for d in "${SEAL_BUILT_DIRS[@]}"; do [[ -d "$w/$d" ]] && roots+=("$w/$d"); done
  while IFS= read -r d; do roots+=("$d"); done < <(find "$w/server" -maxdepth 6 -type d -path '*/node_modules/sharp/build/Release' 2>/dev/null)
  # indice sha256 -> origem, so de arquivos MAIS NOVOS que o prepare.ok (produzidos neste build, nao trazidos de fora)
  if ((${#roots[@]})); then
    find "${roots[@]}" -type f -newer "$w/prepare.ok" 2>/dev/null | while IFS= read -r f; do
      m="$(head -c4 "$f" 2>/dev/null | od -An -tx1 | tr -d ' \n')"
      if [[ "$m" == 7f454c46 ]]; then printf '%s\t%s\n' "$(sha256sum "$f" | cut -d' ' -f1)" "${f#"$w"/}"; fi
    done > "$idx"
  fi
  # node: compilado do tarball pinado (lock node-src) pelo stage node em <ws>/toolchain/node; origem = caminho absoluto
  if [[ -f "$ws/toolchain/node/bin/node" ]]; then
    printf '%s\t%s\n' "$(sha256sum "$ws/toolchain/node/bin/node" | cut -d' ' -f1)" "$ws/toolchain/node/bin/node" >> "$idx"
  fi
  : > "$a/built-from-source.tsv"
  find "$a" -type f -not -name '*.map' | while IFS= read -r f; do
    m="$(head -c4 "$f" 2>/dev/null | od -An -tx1 | tr -d ' \n')"
    [[ "$m" == 7f454c46 ]] || continue
    sha="$(sha256sum "$f" | cut -d' ' -f1)"
    src="$(awk -F'\t' -v s="$sha" '$1==s {print $2; exit}' "$idx")"
    [[ -n "$src" ]] || continue
    rel="${f#"$a"/}"
    printf '%s\t%s\t%s\n' "$sha" "$rel" "$src" >> "$a/built-from-source.tsv"
  done
  rm -f "$idx"
  echo "built-from-source: $(wc -l < "$a/built-from-source.tsv") binarios com origem no build"
  return 0
}
