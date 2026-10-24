# Checklist de pré-lançamento

Itens a fazer **antes do primeiro lançamento público** (hoje o app só roda em aparelhos de teste).

## Dados e schema (SwiftData)
- [ ] **Colapsar o histórico de migração** do `ios/GymBros/Models/Schema.swift` para um único `SchemaV1`
      com todos os modelos atuais, removendo `SchemaV2…V7` e o `AppMigrationPlan` (ou deixando um estágio só).
      Só é seguro antes do lançamento, porque os stores dos aparelhos de teste serão descartados.
  - [ ] **Reinstalar** o app em todos os aparelhos de teste depois (o store antigo some; sem caminho de migração, o app começa com banco novo).
  - [ ] Conferir que nada importante dos testes se perde (o que importar deve estar na cópia da conta / AccountSync).
  - Motivo: a partir do lançamento, a cadeia de migração passa a ser intocável (não apagar versões), senão quebra a atualização de quem já tem o app.

## Firebase
- [ ] Trocar a conta do Firebase para a **conta da empresa**: novo `GoogleService-Info.plist` (e `google-services.json` no Android), fora do git.
- [ ] Revisar regras e índices do Firestore na conta nova.

## MFIT (importação)
- [ ] Rever se o endpoint/contrato do MFIT ainda vale (é engenharia reversa; pode mudar sem aviso).
