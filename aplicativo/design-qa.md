# Verificação do ATLETA 1.1.6

## Layout aprovado em 17 de novembro de 2026

O [mockup aprovado](C:/Users/tassi/.codex/generated_images/01a1e6a9-a16e-7261-bd0d-e94e4ef7c2a9/exec-867353e0-0757-4c6a-9774-1781cf85e330.png) tem 1501 × 1048 px. As [telas do Flutter](C:/Users/tassi/.codex/visualizations/2026/11/16/01a1e6a9-a16e-7261-bd0d-e94e4ef7c2a9/atleta-redesign/telas-flutter-v2.png) foram capturadas a 390 × 844 px lógicos, em densidade 1, sem a área do sistema. Cada painel do mockup foi recortado e redimensionado sem distorção para a [comparação em duas linhas](C:/Users/tassi/.codex/visualizations/2026/11/16/01a1e6a9-a16e-7261-bd0d-e94e4ef7c2a9/atleta-redesign/comparacao-v2.png). A linha superior contém o mockup e a inferior contém a implementação. A [comparação dos ícones](C:/Users/tassi/.codex/visualizations/2026/11/16/01a1e6a9-a16e-7261-bd0d-e94e4ef7c2a9/atleta-redesign/icones-v2.png) amplia a cápsula em cada estado ativo.

A comparação cobre Hoje com M5 desconectado, Treinos com uma caminhada em andamento e Progresso em sete dias. O Flutter usa registros sintéticos coerentes e um M5 simulado.

- **Tipografia e conteúdo.** Inter nos títulos, rótulos e botões, IBM Plex Mono no cronômetro e nas leituras ao vivo. Os rótulos principais reproduzem o português do mockup. Os totais e o gráfico vêm dos registros do perfil e variam com o período.
- **Composição.** O M5 domina a tela Hoje. Em Treinos, o cronômetro e os comandos antecedem o histórico. Progresso mostra os quatro totais, o gráfico selecionável e a carga de treino.
- **Cores e estados.** Fundo verde escuro sobre preto, contraste nos botões verdes e seleção rosa na cápsula. O M5 exibe texto para conexão perdida, pausa ou treino finalizado.
- **Imagens e ícones.** A cápsula usa os três glifos do app extraídos da referência original. A foto vem do perfil. A silhueta redonda do relógio usa o ícone vetorial Material, uma diferença menor em relação ao relógio quadrado do mockup.

### Iteração visual

Na [primeira renderização](C:/Users/tassi/.codex/visualizations/2026/11/16/01a1e6a9-a16e-7261-bd0d-e94e4ef7c2a9/atleta-redesign/comparacao-v1.png), o texto dos botões verdes usava fonte de teste, os glifos apareciam menores e o histórico tinha filtros sem as setas do mockup. Fixei Inter nos botões, aumentei os glifos, dei mais espaço ao cronômetro e acrescentei as setas nos filtros. A [captura revisada](C:/Users/tassi/.codex/visualizations/2026/11/16/01a1e6a9-a16e-7261-bd0d-e94e4ef7c2a9/atleta-redesign/comparacao-v2.png) mostra os ajustes e os três estados do menu. A aba Progresso mantém setas pequenas para consultar períodos anteriores.

### Verificação funcional

O analisador do Flutter não encontrou problemas e os 19 testes automatizados passaram. Os fluxos cobrem abrir Treinos após conectar pelo cartão de Hoje, iniciar do zero, pausar, retomar, finalizar e salvar com um M5 simulado. Também cobrem cancelamento e confirmação da limpeza do histórico do perfil e cálculo, períodos e seleção do gráfico de passos. O ensaio com Motorola e M5 físicos desta versão fica para a instalação pelo usuário.

final result: passed

# Verificações anteriores do ATLETA

## Interface do ATLETA 1.1.0

A entrada pede para criar ou selecionar um perfil local. Today, Progress e Workouts mantêm a cápsula com os glifos da referência. A composição de Today foi ajustada após a remoção do cartão noturno. O gráfico de carga mantém seus rótulos, seleção e resumos.

- [Today](docs/screenshots/today.png)
- [Training Load Ratio](docs/screenshots/training-load-ratio.png)
- [Visão geral da demonstração atual](docs/screenshots/visao-geral.png)
- [Comparação dos glifos da cápsula](docs/screenshots/comparacao-menu.png)

Os pares antigos de comparação com a referência são evidência histórica da reprodução inicial do layout.

## Resultado dos testes

| Ambiente ou comando | Resultado |
| --- | --- |
| `flutter analyze --no-pub` | Nenhum problema. |
| `flutter test --no-pub test tool/capture_reference_test.dart` | 13 testes regulares e 2 capturas passaram. |
| Navegador do Codex | Criei dois perfis sintéticos. O primeiro guardou 172,5 cm, 68,4 kg e prontidão 71%. O segundo foi criado só com nome e começou com prontidão vazia. Após fechar e reabrir, os dois perfis reapareceram e o primeiro recuperou 71%. Conferi a entrada, a troca de perfil e a tela do M5. |
| Builds web e Android | Produção web, demonstração e APK Android 1.1.0 gerados. |
| PlatformIO e `release.py --firmware-only` | Firmware 2.1.8 compilado, binário combinado e manifesto gerados. |
| `python -m unittest discover -s laboratorio/painel -p test_*.py` | 66 testes do painel passaram. |

Os testes cobrem migração do perfil anterior, separação do histórico, gravação atômica e deduplicação do treino M5, carga recalculada, interpretação dos quadros BLE v1 e v2, e identificadores de confirmação dos comandos.

## Teste físico com o M5StickC Plus2 em 16/11/2026

O firmware 2.1.8 foi gravado pela COM3 a partir do pacote existente. O gravador validou os quatro segmentos e a placa confirmou a versão no próximo boot. O SHA-256 de `firmware.bin` foi `ebca65b5f0e9237a3370f2f6129d8f073c5e62a963b6fc5199a39bce72eab0cc`.

| Comando | Compilação nativa de teste no Windows | Chrome no Windows após pareamento pelo sistema |
| --- | --- | --- |
| Conectar | Recebeu passos, tempo ativo e bateria. | Recebeu os dados ao vivo. |
| Iniciar | A telemetria USB confirmou uma nova sessão com o cronômetro reiniciado. | O cronômetro reiniciou e o app exibiu Pausar e Finalizar. |
| Pausar | A sessão ficou inativa por USB e manteve 7 s. | O cronômetro ficou em 5 s e o app exibiu Retomar. |
| Retomar | A mesma sessão ficou ativa e voltou a contar. | O cronômetro voltou a contar. |
| Finalizar | A sessão ficou inativa com 16 s, salvos no histórico com origem Atleta-M5. | O app confirmou a finalização e salvou 12 s com origem Atleta-M5. |

Antes do pareamento pelo Windows, o Chrome recebeu dados ao vivo e caiu no primeiro comando de início. O reteste usou o mesmo rascunho, que conservou o horário da primeira tentativa apesar de o cronômetro ter iniciado na segunda. Os dois treinos foram salvos em perfis de teste. A validação física no iOS continua pendente.

[Ficha do treino salvo no Chrome](docs/screenshots/m5-treino-ble-2.1.8.jpg)

## Teste físico no Motorola Signature com Android 17 em 16/11/2026

O APK instalado corresponde ao `app-release.apk` do ATLETA 1.1.0 (código 2). O app recebeu dados do M5 com firmware 2.1.8 antes de o pareamento ser confirmado. O log Android registrou `BOND_BONDING` às 23:44:47.987 e `SMP_RSP_TIMEOUT` exatamente 30 segundos depois, seguido de `BOND_NONE` e desconexão do GATT. O M5 voltou a anunciar sem reiniciar. Uma tentativa imediata no mesmo processo falhou. O sistema confirmou `BOND_BONDED` ao selecionar **Atleta-M5** em **Configurações → Dispositivos conectados → Parear novo dispositivo** e confirmar **Parear**. Depois de reabrir o ATLETA e tocar em **Reconnect watch**, o teste passou.

| Comando no app | Resultado observado no M5 por USB |
| --- | --- |
| Iniciar | Nova sessão e cronômetro reiniciado. |
| Pausar | A sessão ficou inativa e o cronômetro manteve 6 s. |
| Retomar | A mesma sessão voltou a contar. |
| Finalizar | A sessão ficou inativa com 12 s. O app exibiu `Workout finished on the watch`. |

O teste ocorreu com o app em primeiro plano. O treino finalizado ficou disponível para salvar ou descartar, sem lançamento no histórico.

[Confirmação no Motorola](docs/screenshots/m5-android-17-treino-finalizado.jpg)

## Correção do pareamento no ATLETA 1.1.1 em 17/11/2026

No Android, o app aguarda a conclusão do pareamento do firmware com controle de treino antes de mostrar os dados ao vivo e habilitar os comandos. Enquanto aguarda, indica onde confirmar o Atleta-M5. Se o sistema encerrar a tentativa, o app explica o motivo e permite tentar novamente. A leitura de relógios com protocolo v1 mantém o fluxo anterior.

No Motorola Signature com Android 17, removi o pareamento criado no teste anterior e instalei o APK 1.1.1 (código 3) sobre a instalação existente. O Android apresentou duas confirmações de sistema no novo pareamento. Deixei a segunda expirar em uma tentativa e observei `SMP_RSP_TIMEOUT`. A tela voltou a oferecer **Reconnect watch**. Na tentativa seguinte, no mesmo processo do ATLETA, confirmei os dois avisos. O sistema registrou `BOND_BONDED` e o app exibiu passos, tempo ativo e bateria. Depois desconectei e reconectei pelo app. Os dados voltaram sem novo pedido de pareamento. Deixei o relógio conectado ao celular.

`flutter analyze --no-pub` passou, os 13 testes passaram, a assinatura do APK foi verificada e o SHA-256 do APK instalado bateu com o arquivo gerado.

[Pedido de pareamento no ATLETA 1.1.1](docs/screenshots/m5-android-aguardando-pareamento.jpg)

### Reteste do treino pelo ATLETA 1.1.1

No mesmo Motorola Signature com Android 17, o APK instalado bateu com o arquivo da versão 1.1.1. Com o M5 já pareado, iniciei um novo treino pelo app, pausei aos 8 s, conferi que o cronômetro ficou parado, retomei e finalizei com 17 s de tempo ativo. A tela exibiu `Workout finished on the watch` e manteve `Live from M5` após a finalização. Na janela de 90 s que cobriu a preparação, os quatro comandos e a verificação final, o Android não registrou eventos de desconexão ou reconexão do GATT para o app. O vínculo BLE do Atleta-M5 continuou criptografado ao fim do teste. O app ficou em primeiro plano, com o treino de teste finalizado e disponível para salvar.

[Treino finalizado no ATLETA 1.1.1](docs/screenshots/m5-android-1.1.1-treino-finalizado.jpg)

## Pareamento com uma confirmação no ATLETA 1.1.2 em 17/11/2026

O ATLETA inicia o pareamento pelo Android antes de abrir a conexão GATT. No teste com o Motorola Signature (Android 17) e o M5StickC Plus2 (firmware 2.1.8), refiz o vínculo pelo app. O log registrou um pedido `ACTION_PAIRING_REQUEST`, uma aceitação, `BOND_BONDED` e a conexão GATT, nessa ordem. O app exibiu os dados do relógio. Desconectei e reconectei pelo app com o vínculo salvo. A leitura voltou com o BLE criptografado e sem novo pedido de confirmação.

O APK 1.1.2 (código 4) foi instalado sobre a versão anterior e conferido por SHA-256. A assinatura foi verificada, a análise estática passou e os 13 testes passaram. A versão 1.1.2 foi testada fisicamente com o firmware 2.1.8.

[Confirmação de pareamento no Motorola](docs/screenshots/m5-android-1.1.2-confirmacao-unica.jpg)
