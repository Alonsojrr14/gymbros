# Revisão da Apple (App Review)

Como enviar o GymBros para revisão enquanto o app roda com `Backend.mode = .mock` (sem servidor real), e o que trocar quando houver servidor. A ordem geral de publicação está em [publicacao.md](publicacao.md).

## O que o revisor encontra

- **Login obrigatório.** O GymBros é uma rede social de treino: o progresso do bro, os treinos e o perfil pertencem à conta e alimentam ligas, amigos e o perfil público. Por isso o app abre na tela de login (`RootView`, `App/App.swift`). A justificativa nas notas cita a guideline 5.1.1(v): o login é exigido porque o recurso principal depende da conta, e "Excluir conta" existe dentro do app.
- **Conta de demonstração.** Só no `.mock`, a tela de login mostra **"Entrar com conta de demonstração"** (`DemoAccount`, `Services/DemoAccount.swift`). O botão entra pelo `AuthBackend` como qualquer conta de e-mail. Também dá para digitar as credenciais fixas:
  - E-mail: `revisao@gymbros.app`
  - Senha: `GymBros2026`
  - Nome da conta: "Bro Revisor"
  No `.mock` qualquer e-mail válido com senha de 8+ caracteres entra; as credenciais acima são as documentadas. "Continuar com a Apple" também funciona, simulado.
- **Conteúdo de exemplo.** Na primeira vez que a conta de demonstração abre a aba Ligas, ela já está na "Liga dos Bros" (código `AMIGOS`, marcada "exemplo"), com participantes, check-ins, ranking, times e mural simulados. Sair da liga não a traz de volta (marca `demoSeeded`, que vai com a conta). Qualquer conta pode entrar nela por Ligas > "Experimentar a liga de exemplo". Amigos, pedido de amizade, mapa de amigos e mensagens diretas também têm pessoas simuladas.
- **Primeiro acesso.** Uma conta nova (inclusive a de demonstração) passa antes pelo onboarding (`OnboardingView`, poucos toques): nome do treinador, as duas caixas "Li e concordo com os Termos de uso" e "Li e concordo com a Política de privacidade" (`LegalConsent`; tocar marca e desmarca, o documento abre pelo link sublinhado no nome dele), "Receber meu ovo" e "Começar a jornada".
- **X1.** A tela inicial tem sempre o cartão X1: desafio direto entre duas pessoas, sem relação com ligas, em que vence quem fizer mais na métrica escolhida nas 24 h depois do aceite. No `.mock`, as pessoas simuladas respondem em 3 a 9 s (a maioria aceita), treinam durante o X1 e às vezes desafiam a conta. Ovos não lutam: sem um bro chocado, desafiar e aceitar dão "Ovos não entram no X1…" (`DuelRefusal.noHatchedBro`), e a conta de demonstração começa com um ovo. Desafiar e aceitar pedem o aceite dos termos. **Recomendação:** dar à conta de demonstração um bro já chocado (ou dizer nas notas quanto registrar para chocar), para o revisor conseguir testar o X1.
- **Rodada suíça.** Cada liga tem uma rodada diária em pares (Ranking > "Rodada suíça de hoje"); na Liga dos Bros a conta enfrenta os participantes simulados a partir do dia em que entrou.
- **Música.** Desligada por padrão. Ajustes > Música > "Mostrar o que estou ouvindo" pede a permissão de Apple Music (biblioteca de mídia) e mostra só a música que está tocando no app Música. No `.mock` ela não sai do aparelho; os amigos simulados do Mapa (Bruno e Ana) mostram uma música de exemplo.
- **Denúncias no `.mock`.** A denúncia esconde o conteúdo na hora para quem denunciou e fica guardada no aparelho; ninguém a analisa até haver servidor. As notas em inglês dizem isso; a revisão em até 24 h só entra com a fila de moderação.
- **O que é simulado.** Não há servidor: as outras pessoas, ligas, amigos e mensagens são gerados no aparelho; a conta e a cópia dela ficam num arquivo dentro do app. Nada sai do iPhone (o manifesto de privacidade declara zero dados coletados). A tela de login e a política de privacidade dizem isso.

## Onde fica cada coisa (para as notas)

| Item | Caminho no app |
|---|---|
| Denunciar check-in / foto | Ligas > Liga dos Bros > check-in de outra pessoa > ⋯ > "Denunciar check-in" / "Denunciar foto" |
| Denunciar comentário ou recado do mural | Toque longo no comentário / recado de outra pessoa |
| Denunciar / bloquear perfil | Perfil público de outra pessoa > ⋯ > "Denunciar perfil" / "Bloquear {nome}" |
| Bloquear pelo check-in | ⋯ do check-in > "Bloquear {nome}" |
| Lista de bloqueados | Ajustes (engrenagem na tela do bro) > Privacidade > "Usuários bloqueados" |
| Excluir conta | Ajustes > Conta > "Excluir conta" |
| X1 | Cartão "X1" na tela do bro; Amigos > "X1"; perfil de outra pessoa > "Desafiar para um X1"; botão "X1" na conversa |
| Rodada suíça | Ligas > Liga dos Bros > Ranking > "Rodada suíça de hoje" |
| Música | Ajustes > Música; Ajustes > Privacidade > "Mostrar o que estou ouvindo" |
| Termos de uso (EULA com tolerância zero) | Na tela de login; aceite obrigatório no onboarding da conta nova (nome do treinador, ovo e termos) ou em `TermsRequiredView` quando a versão muda; Ajustes > Privacidade > "Termos de uso" |
| Política de privacidade | Na tela de login; Ajustes > Privacidade > "Política de privacidade" |
| Filtro de conteúdo ofensivo | Títulos, notas, recados, nomes de liga e de treinador barrados antes de publicar (`ContentFilter`) |

## Permissões

- **Localização "Sempre".** Pedida só quando a pessoa salva um lugar de treino (Mapa > "Adicionar"). É usada para monitorar a região da academia: avisar ao chegar ("Avisar ao chegar") e encerrar o treino em andamento ao sair ("Encerrar treino ao sair"), mesmo com o app fechado. As duas automações podem ser desligadas no Mapa e em Ajustes (Notificações e Treino). A gravação de percurso (Mapa > corrida, caminhada ou pedalada) usa "Durante o uso" com atualização em segundo plano enquanto o percurso está sendo gravado (`UIBackgroundModes = location`). A localização não sai do aparelho.
- **Apple Music.** Pedida só ao ligar "Mostrar o que estou ouvindo" (`NSAppleMusicUsageDescription`: "Para mostrar aos seus amigos a música que está tocando enquanto você treina, se você ligar essa opção."). O app usa a permissão da biblioteca de mídia (`MPMediaLibrary`) só para ler o item que está tocando; não lê histórico, playlists nem a biblioteca. Negada, a opção continua desligada.
- **Apple Saúde.** Opcional, em Ajustes > Apple Saúde. Lê treinos e peso para virar atividades e XP; grava treinos e energia ativa se a pessoa ligar "Gravar". Dados do Saúde não vão para o iCloud, nem para publicidade; calorias, distância e esforço do Saúde nunca vão para posts (guideline 5.1.3).

## Notas para colar no App Store Connect (App Review Information > Notes)

```text
GymBros is a social workout app: your bro (virtual companion), workouts and profile belong to your account and power leagues, friends and your public profile. That is why sign-in is required at launch (guideline 5.1.1(v)); the account can be deleted in the app at Settings > Conta > Excluir conta.

DEMO ACCOUNT
On the login screen tap "Entrar com conta de demonstração", or sign in with:
  E-mail: revisao@gymbros.app
  Password: GymBros2026
This build has no live server yet: other people, leagues, friends and messages are simulated on the device, and nothing leaves the iPhone. The demo account starts in the sample league "Liga dos Bros" (tab Ligas) with simulated members, check-ins and wall messages.

HOW TO TEST
1. Sign in with the demo account. A new account first goes through a short onboarding (a few taps): type a trainer name, check both boxes, "Li e concordo com os Termos de uso" and "Li e concordo com a Política de privacidade" (each document opens from its underlined name), tap "Receber meu ovo", then "Começar a jornada".
2. Tab Treino: start a routine or "Treino livre"; or tap "Registrar atividade" on the home screen. Posting to the league is optional.
3. Tab Ligas > Liga dos Bros: ranking, check-ins, wall (Mural).
4. Friends: people icon on the home screen. Map and route recording: tab Mapa.
5. X1 (1-on-1 challenge, not tied to leagues): card "X1" on the home screen, or "Desafiar para um X1" on someone's profile. Pick a person and a metric; simulated people answer in a few seconds and the one who does more in the 24 hours after acceptance wins. Eggs cannot fight: the starter egg must hatch first (log activities on the home screen until it hatches).
6. Daily Swiss round inside each league: Ligas > Liga dos Bros > Ranking > "Rodada suíça de hoje".

USER-GENERATED CONTENT (1.2)
- Report: ⋯ on another person's check-in > "Denunciar check-in" / "Denunciar foto"; long-press a comment or wall message; ⋯ on a public profile > "Denunciar perfil". In this build (no server yet) a report hides the content immediately for the reporter and is kept on the device; the moderation queue with review within 24 hours starts with the server.
- Block: ⋯ > "Bloquear {name}". Blocked users: Settings > Privacidade > Usuários bloqueados.
- Terms of Use with zero tolerance for objectionable content must be accepted before posting. Offensive words are filtered before publishing.

PERMISSIONS
- Location "Always": only after saving a gym on the Map tab, to notify on arrival and finish the running workout when leaving the gym, with the app closed. Both can be turned off. Route recording uses location while recording. Location stays on the device.
- Apple Music (optional, Settings > Música > "Mostrar o que estou ouvindo", off by default): media library permission, used only to read the song playing now in the Music app to show it to friends during a live workout. In this build it stays on the device.
- HealthKit (optional, Settings > Apple Saúde): reads workouts and body mass to award XP, writes workouts if enabled. Health data is not stored in iCloud, not used for ads and never posted (only type, date and duration if the user posts that activity).

Privacy policy and Terms are linked on the login screen and in Settings > Privacidade.
```

## Checklist: o que trocar quando houver servidor real

- [ ] `Backend.mode = .cloudKit` em `GymBros/Services/Backend.swift` (e implementar o `ServerAccountDataBackend`/`ServerInboxBackend` ou o servidor próprio; ver [servidor-real.md](servidor-real.md)). Com isso o botão de demonstração some (`DemoAccount.isAvailable`).
- [ ] Conta de demonstração **real** no servidor (e-mail e senha que funcionem de verdade, com dados de exemplo e pelo menos uma liga com outras pessoas) e notas acima atualizadas. Sign in with Apple não serve como conta demo.
- [ ] Capabilities no alvo GymBros (conta paga): **iCloud → CloudKit** com `Backend.containerID` e **Sign in with Apple** ([cloudkit.md](cloudkit.md) > "Ligar o CloudKit").
- [ ] `PrivacyInfo.xcprivacy` do app: preencher `NSPrivacyCollectedDataTypes` com o bloco abaixo. O do widget continua vazio (não coleta nada).
- [ ] App Privacy no App Store Connect igual ao manifesto (Data Linked to You, sem tracking).
- [ ] Política de privacidade (`App/PrivacyPolicyView.swift`, `docs/privacidade.md`, `PrivacyPolicy.updated`) e termos (`App/TermsView.swift`, `docs/termos.md`, `Terms.version`) sem "modo de demonstração / nada sai do aparelho".
- [ ] Fila de moderação com resposta em até 24 h: quem lê `Report` no Dashboard (ou servidor com chave em cofre), remove o conteúdo para todos e expulsa o autor ([cloudkit.md](cloudkit.md) > "Checklist do que falta no servidor (moderação)").
- [ ] Revogação do token do Sign in with Apple ao excluir a conta (servidor com a chave .p8 em cofre).
- [ ] Remover das notas a frase "nothing leaves the iPhone" e trocar a frase de denúncia por "reports are reviewed within 24 hours" só quando a fila existir.

## PrivacyInfo: bloco para o modo com servidor

Hoje, no `.mock`, `NSPrivacyCollectedDataTypes` fica **vazio** de propósito: nada sai do aparelho. Não altere o arquivo antes de ligar o servidor. Quando o modo CloudKit for ligado, troque o `<array/>` de `NSPrivacyCollectedDataTypes` em `GymBros/Resources/PrivacyInfo.xcprivacy` por:

```xml
	<key>NSPrivacyCollectedDataTypes</key>
	<array>
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeName</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeUserID</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypePhotosorVideos</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeOtherUserContent</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeFitness</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
	</array>
```

O que cada tipo cobre no banco público ([cloudkit.md](cloudkit.md) > "Esquema"):

| Tipo | Origem |
|---|---|
| `Name` | `Profile.name`, `Member.name`, `Duel.name`/`opponentName` |
| `UserID` | id do usuário do iCloud em todos os registros (`user`, `from`, `to`, `opponent`) |
| `PhotosorVideos` | `CheckIn.photo` (foto de check-in) |
| `OtherUserContent` | `Profile.username`/`bio`, títulos e notas de `CheckIn`, `Message` do mural, denúncias (`Report`) |
| `Fitness` | tipo, data, duração, esforço e distância do GPS do app em `CheckIn`; números públicos do perfil; total do X1 na métrica (`Duel.value`); dia de entrada na liga (`Member.joinedAt`) |

Se a cópia da conta (`AccountDataBackend`) ou as mensagens diretas forem para um servidor, acrescente também, com o mesmo formato: `NSPrivacyCollectedDataTypeHealth` (dados do Saúde na cópia), `NSPrivacyCollectedDataTypePreciseLocation` (academias e rotas), `NSPrivacyCollectedDataTypeEmailAddress` (login com e-mail) e `NSPrivacyCollectedDataTypeEmailsOrTextMessages` (mensagens diretas). O convite para treinar junto leva as coordenadas da academia escolhida (`TrainInvite.latitude`/`longitude`), então mensagens diretas no servidor também exigem `PreciseLocation`. Quando o status ao vivo subir com a música (`MusicShareStore.current`), acrescente `NSPrivacyCollectedDataTypeOtherUsageData` (vinculado, sem tracking, funcionalidade do app).

Os `NSPrivacyAccessedAPITypes` não mudam: o app só usa `UserDefaults` (`CA92.1`, `1C8F.1` para o App Group) entre as APIs com motivo obrigatório.
