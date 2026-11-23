<!-- ESTE ARQUIVO É GERADO de axuz_ops/security/SECURITY.md.template
     — você está olhando `SECURITY.md`, uma CÓPIA. Editar aqui é drift que
     o próximo rollout de `axuz_ops/security/install-everything.sh` apaga
     sem avisar. Mude o TEMPLATE e rode o instalador; o gate `tpldrift`
     compara os dois byte a byte (item P-033).

     Comentário HTML e não texto visível de propósito: este arquivo é
     lido por quem reporta vulnerabilidade, e o aviso é para quem ABRE a
     fonte, não para quem lê a página. -->
# Security Policy

## Ambiente

Este repositório faz parte do stack **axuz** rodando em ambiente
hml/staging. Não é produção customer-facing.

## Reportando vulnerabilidades

Encontrou um problema de segurança? Abra issue privada no repo afetado
ou contate diretamente o time de plataforma.

Inclua:
- Descrição do problema
- Steps to reproduce
- Versão / commit afetado
- Impacto potencial

## Política completa

Framework de 3 camadas (govulncheck gate + Snyk/Dependabot supply chain
+ exceptions documentadas):
- `axuz_archive/docs/SECURITY-POLICY.md` (política principal)
- `axuz_ops/security/exceptions.yml` (registry de exceções com auto-expiry)

CI gates ativos em todos os repos:
- `secscan` — govulncheck (Go) ou npmaudit (Node) em PR + push + nightly 04:00 UTC
- `gitleaks` — secret detection em PR + push
- `dependabot.yml` — bumps semanais agrupados (segunda 04:00 UTC)

## Versões suportadas

| Versão        | Suportada |
| ------------- | --------- |
| `main`/`master` (HEAD) | ✅ |
| Releases anteriores    | ❌ — atualize pro HEAD |
