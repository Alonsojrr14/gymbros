# Checklist antes de publicar

Ordem sugerida: conta e assinatura → código de desenvolvimento → servidor → privacidade → build e testes → App Store. Cada item aponta para onde está o detalhe.

## 1. Conta e assinatura

- [ ] Migrar para a conta corporativa do Apple Developer (paga): bundle IDs `com.alonsoalmeida.gymbros*`, App Group `group.com.alonsoalmeida.gymbros` e time `5UV7WAAAL2` ainda estão na conta pessoal (`README.md` → "Migração para a conta corporativa").
- [ ] Ao trocar o App Group, migrar o banco SwiftData (`default.store` fica no container do grupo) e o `WidgetData`, senão os usuários de teste perdem os dados.
- [ ] Atualizar `WidgetData.appGroup` (`Shared/WidgetShared.swift`), os dois `.entitlements` e `Backend.containerID`.
- [ ] Capabilities no alvo `GymBros`: iCloud → CloudKit (container do app) e Sign in with Apple (`cloudkit.md` → "Ligar o CloudKit").
- [ ] `MARKETING_VERSION` e `CURRENT_PROJECT_VERSION` conferidos (hoje 1.0 / 1).

## 2. Código só de desenvolvimento

- [ ] Apagar `GymBros/Access/DevAccounts.swift` e as chamadas: `AuthStore.signIn(as:)` (`Services/Auth.swift`), `DevAccountPicker` no `LoginView` e `DevAccount.assignments` em `Backend.install()` (`Services/Backend.swift`). Remover `testDevAccountsResolveToTheirRoles` de `GymBrosTests/AccessTests.swift`.
- [ ] Conferir os outros blocos `#if DEBUG` (seção "Desenvolvimento" do onboarding em `App/SettingsView.swift`, `applyLaunchArguments` em `App/App.swift` e `Onboarding/OnboardingCoordinator.swift`): podem ficar, porque não entram no Release, mas confirme que nada fora deles depende deles.
- [ ] `grep -rn "#if DEBUG" GymBros` só mostra o que foi decidido manter.
- [ ] `DemoAccount` (`Services/DemoAccount.swift`) fica: é a conta da revisão e some sozinha fora do `.mock`.
- [ ] Nenhum segredo, token ou chave no repositório. Credenciais de servidor (chave server-to-server do CloudKit, chave `.p8` do Sign in with Apple) ficam num cofre/gerenciador de segredos, nunca em texto puro (`requisitos-nao-funcionais.md`, verificador de segredos recomendado).

## 3. Servidor (CloudKit)

- [ ] `Backend.mode = .cloudKit` (`Services/Backend.swift`). Sem isso, login e ligas continuam simulados.
- [ ] Esquema criado no Dashboard (Development) com índices: `Profile`, `League`, `Member`, `CheckIn`, `Message`, `FriendLink`, `Report`, `Block`, `RoleAssignment` (`cloudkit.md` → "Esquema").
- [ ] Security Roles conferidas: `World: Read · Authenticated: Create · Creator: Write`; `Report`/`Block` sem `World: Read`; `RoleAssignment` só `Authenticated: Read` (`cloudkit.md` → "Permissões", `rbac.md`).
- [ ] `RoleAssignment` criados para as contas `ADMIN`/`DEVELOPER`, cada uma listando também `USER`.
- [ ] Testado no aparelho com **duas** contas do iCloud: criar e entrar em liga, check-in com foto, mural, amizade, denunciar, bloquear, excluir conta.
- [ ] **Deploy Schema Changes** para Production.
- [ ] Processo de moderação definido para o prazo de 24 h prometido no app: quem olha a fila de `Report` no Dashboard e como tira conteúdo do ar e expulsa o autor (`cloudkit.md` → "Checklist do que falta no servidor (moderação)").
- [ ] Decidido o que fazer com as pendências de exclusão de conta: ligas sem dono, `FriendLink` de outras pessoas, revogação do token da Apple (`cloudkit.md` → "Checklist do que falta no servidor (conta)").

## 4. Privacidade e termos

- [ ] Política de privacidade atualizada para o modo com servidor (hoje diz "modo de demonstração, sem servidor"): `App/PrivacyPolicyView.swift` e a versão publicada em `PrivacyPolicy.url`, com a data em `PrivacyPolicy.updated` (`privacidade.md`).
- [ ] `NSPrivacyCollectedDataTypes` nos `PrivacyInfo.xcprivacy` (app e widget) refletindo o que passa a subir: nome, @usuário, bio, foto de check-in, conteúdo gerado, id do usuário (`requisitos-nao-funcionais.md`).
- [ ] App Privacy no App Store Connect igual ao manifesto.
- [ ] Termos de uso conferidos e com versão nova se o texto mudou (`termos.md`, `Terms.version`).
- [ ] Texto de uso da localização em segundo plano explicado para a revisão (percurso de corrida e automações de academia).

## 5. Build e testes

- [ ] Suíte inteira passando no aparelho, num build limpo:
  ```sh
  xcodebuild test -project GymBros.xcodeproj -scheme GymBros -destination 'id=<UDID>' -derivedDataPath build -allowProvisioningUpdates
  ```
- [ ] Build **Release** compila sem warnings novos (`-configuration Release`).
- [ ] Instalar o Release no aparelho e conferir: login sem a seção "Desenvolvimento", Ajustes sem "Diagnóstico" para conta comum, onboarding na primeira abertura.
- [ ] Atualização por cima da versão anterior: dados, bros e sessão continuam (sem recuperação do banco).
- [ ] Backup exportado na versão anterior restaura na nova.
- [ ] Widgets, Live Activity e controles funcionando com o App Group novo.

## 6. App Store

- [ ] Rodar a auditoria de revisão (skill `appstore-review`) e resolver o que aparecer.
- [ ] Conta de demonstração e notas da revisão: texto pronto em [app-review.md](app-review.md) (conta demo, denunciar/bloquear, excluir conta, termos, privacidade, localização "Sempre" e Saúde).
- [ ] Capturas de tela, descrição, palavras-chave e classificação etária (conteúdo gerado por usuários).
- [ ] URLs no App Store Connect: suporte e marketing `https://alonsojrr14.github.io/gymbros/` (landing em `index.html`, seção "Suporte"), privacidade `https://alonsojrr14.github.io/gymbros/privacidade/`. Para o Google Play, a exclusão de conta fica em `https://alonsojrr14.github.io/gymbros/excluir-conta/` (`excluir-conta.md`).
- [ ] Login obrigatório justificado nas notas por 5.1.1(v): progresso do bro, treinos e perfil pertencem à conta e alimentam ligas, amigos e perfil público ([app-review.md](app-review.md)).
- [ ] TestFlight interno antes do envio para revisão.
