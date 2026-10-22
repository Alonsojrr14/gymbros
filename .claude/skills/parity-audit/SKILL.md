---
name: parity-audit
description: Executa a fase I do GymBros - auditoria de paridade iOS × Android por requisito, separando paridade de negócio e visual, com status por requisito e revisão independente. Use quando o dono pedir /parity-audit ou antes do portão 5.
disable-model-invocation: true
---

# /parity-audit — fase I (portão 5)

1. Para cada requisito em `engenharia/requisitos/matriz-requisitos.md`, preencha em `engenharia/paridade/matriz-ios-android.md`: referência iOS (arquivo/símbolo), referência Android, testes (dos dois lados), evidência, diferença restante, motivo de diferença intencional, e um status:
   `IMPLEMENTED_AND_VERIFIED`, `IMPLEMENTED_BUT_UNVERIFIED`, `PARTIALLY_IMPLEMENTED`, `NOT_IMPLEMENTED`, `INTENTIONALLY_PLATFORM_SPECIFIC`, `BLOCKED`.
2. `IMPLEMENTED_AND_VERIFIED` exige teste rodado ou execução observada no aparelho, citada em `engenharia/plano/resultados-validacao.md`.
3. Regras calculadas no cliente e vistas por outras pessoas (pontuação, suíço, X1, campeões, XP): exija os vetores compartilhados passando nos dois lados.
4. Separe paridade de negócio de paridade visual. Diferença de plataforma só com justificativa documentada.
5. Delegue a conferência por amostragem ao `independent-reviewer` (pelo menos os requisitos críticos).
6. Nunca declare paridade total com requisito crítico pendente, não verificado ou bloqueado. Relate limitações.
