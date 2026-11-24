# ATLETA

Aplicativo Flutter para acompanhar treinos, carga de treinamento, prontidão e atividade do M5StickC Plus2. A interface mantém os rótulos em inglês.

## Perfis locais

Ao abrir o app, escolha um perfil ou toque em **Create profile**. O nome é suficiente. Altura, peso, ano de nascimento, comprimento do passo e foto são opcionais e podem ser alterados em **Profile & Settings → Edit profile**. Use **Switch profile** para voltar à lista.

Cada perfil guarda seus treinos, prontidão, dias de descanso, sessões em andamento e integrações. Quem usa o mesmo dispositivo pode selecionar qualquer perfil. O app funciona sem conta, senha ou servidor de autenticação. Na atualização, o perfil e o histórico da versão anterior aparecem na lista. Se o histórico ainda não tiver nome, selecione **Existing local history** e dê um nome a ele.

## Conectar o M5StickC Plus2

1. Abra **Profile & Settings → M5 watch** ou use o cartão em **Workouts**.
2. Use **Find M5 watch** e escolha **Atleta-M5**. Se o Bluetooth estiver desligado, ative-o segurando **B** na tela principal do relógio.
3. O cartão mostra passos, tempo ativo e bateria quando recebe uma leitura recente. O comprimento do passo no perfil permite estimar distância. Em **Progress**, passos e distância são somados a partir dos treinos salvos no intervalo.

| Firmware | Como salvar um treino |
| --- | --- |
| **2.1.7** | Segure **A** para começar no relógio, pressione **A** para pausar e use **Save M5 workout** no app. Confirme a data, a atividade e o esforço. A leitura antiga contém um resumo instantâneo e não inclui a identidade da sessão. O app usa relógio, data e contadores para evitar salvar o mesmo resumo duas vezes. |
| **2.1.8** | Em **Workouts**, use **Set up a watch workout → Start on M5**. Pause, retome e finalize pelo app. Os botões refletem o estado recebido do relógio. Use **Save M5 workout** para informar o esforço e salvar os totais. |

A conexão Bluetooth funciona diretamente entre o relógio e o dispositivo que executa o app. O painel Windows, MQTT e MySQL seguem como caminhos independentes para o laboratório. O relógio permanece vinculado a um perfil por vez neste app. Para trocar de dono, finalize o treino ou descarte o rascunho, remova o vínculo no perfil anterior e conecte no novo.

Se o Bluetooth cair durante um treino, reconecte no mesmo perfil. O relógio segue contando em memória enquanto estiver ligado. Se ele reiniciar ou você segurar **A** para criar outra sessão, o resumo anterior na memória pode ser perdido. O resumo confirmado em **Finish** fica salvo como rascunho no app até a gravação definitiva, inclusive após fechar o app.

Em Android, conceda a permissão de dispositivos próximos. Em Android 11 e anteriores, o sistema pode pedir localização para descobrir Bluetooth LE. O app usa essa permissão para descoberta. No iOS, conceda acesso ao Bluetooth. Na web, use um navegador com Web Bluetooth num endereço HTTPS ou local. Os demais fluxos funcionam quando o navegador ou o dispositivo não oferece Bluetooth.

## Executar e instalar

A partir de `aplicativo`, com Flutter 3.44.3 e Dart 3.12.2:

~~~powershell
flutter pub get
flutter run -d chrome --no-web-resources-cdn
flutter build apk --release
~~~

O APK de teste fica em `build/app/outputs/flutter-apk/app-release.apk`, usa a assinatura de desenvolvimento e requer Android 8 (API 26) ou superior. Para iOS, use macOS com Xcode, abra `ios/Runner.xcworkspace`, selecione a equipe de assinatura e habilite HealthKit se usar a importação opcional de treinos. O alvo mínimo é iOS 15.

A partir da versão **2.2.0**, o firmware do M5StickC Plus2 pode ser atualizado pelo painel Windows. Veja o [procedimento de instalação e o protocolo BLE](../laboratorio/docs/FIRMWARE_M5.md). O binário combinado da versão atual está em `laboratorio/entrega/firmware/m5stickc-plus2-lab-2.2.5.bin`.

## Indicadores

- **Carga de treinamento** usa duração em minutos × esforço de 0 a 10. O app soma por dia, calcula as médias de 7 e 28 dias e divide uma pela outra. O cálculo exige 28 datas consecutivas com treinos completos ou descanso confirmado e média de 28 dias maior que zero. Treinos do M5 entram no mesmo cálculo dos registros manuais.
- **Prontidão** continua sendo uma autoavaliação de 0 a 100. As faixas são Low de 0 a 49, Moderate de 50 a 79 e High de 80 a 100.
- **Importação opcional** em **Data sources** consulta apenas treinos dos últimos 30 dias pelo HealthKit ou Health Connect. O vínculo da fonte fica em um perfil por vez, e o esforço dos treinos importados é preenchido no app.
- As telas e permissões de frequência cardíaca e sono foram removidas. Os registros anteriores dessas métricas ficam no armazenamento legado, fora dos fluxos e cálculos atuais.

## Demonstração e testes

~~~powershell
flutter run -d chrome --dart-define=ATLETA_DEMO=true
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test
flutter test tool/capture_reference_test.dart
~~~

A demonstração abre direto em **Today** com dados temporários. Use `?screen=load` para abrir o gráfico de carga e `&capture=1` para ocultar a etiqueta da demonstração. Na versão padrão, o IndexedDB do navegador guarda perfis por origem. Mantenha o mesmo endereço e porta para voltar ao mesmo banco.

Dependências principais: `sembast`, `sembast_web`, `universal_ble`, `health`, `path_provider`, `image_picker` e `intl`. Veja [as capturas e verificações](design-qa.md). [Documentação de universal_ble](https://pub.dev/packages/universal_ble)
