# ATLETA — Projeto Integrador 6 / N1

Monitoramento de atividade com **M5StickC Plus2 → MQTT → EMQX → MySQL local → MySQL na Aiven** e painel Windows.

O [app Flutter do ATLETA](aplicativo/README.md) oferece perfis locais, treinos e conexão
direta por Bluetooth ao M5. A partir do firmware 2.2.0, o painel permite
[atualizar o relógio por Wi-Fi pelo painel](laboratorio/docs/FIRMWARE_M5.md#atualização-por-wi-fi-pelo-painel).

## Abrir e conectar — painel 1.11.2

Abra **ABRIR PAINEL.exe**. A aba **Início** mostra passos, tempo e bateria ao vivo
pelo MQTT local, além do estado do servidor, do M5 e da nuvem. O firmware 2.2.5
envia uma leitura por segundo. O histórico continua no MySQL.

1. **Preparar computador** inicia o servidor. Se ele já estiver pronto, pode seguir.
2. **Configurar Wi-Fi** envia a rede e a senha por Bluetooth, com o firmware
   2.2.2 ou posterior. Libere **Wi-Fi por Bluetooth** com o botão **B** no relógio.
   O painel preenche a rede ativa do notebook e a senha, quando o Windows libera a chave.
   Depois de clicar em **Enviar por Bluetooth**, a busca aguarda até um minuto
   enquanto você libera o relógio. A busca pode ser cancelada antes do envio.
   **Usar hotspot do notebook** seleciona o Hotspot móvel de 2,4 GHz e envia
   ao M5 o endereço do servidor nessa rede. Se o hotspot estiver salvo no M5,
   o painel mantém essa seleção ao abrir a janela.
   O M5 testa a rede antes de gravá-la e começa uma nova sessão ao reiniciar.
3. **Ver dados do atleta** abre passos, bateria e histórico. Após configurar,
   basta ligar o M5 na mesma rede; o cabo USB pode ser retirado.

**Atualizar por Wi-Fi** abre a janela de atualização do firmware do relógio.
**Configurar por USB** fica na janela de configuração para placas com firmware anterior.

O perfil do atleta fica em uma aba opcional. IP, portas, Dashboard e parada do
servidor ficam em **Opções avançadas**. Abrir uma tela ou detectar o USB não
altera a configuração da placa. **M5 conectado** exige uma leitura real recente.
Uma falha da nuvem aparece separadamente do recebimento local dos dados.
**Ver detalhes** abre a aba do registro de operações e falhas do servidor no painel.

## Integração com a nuvem — painel 1.6.0

O painel inicia automaticamente a sincronização quando `laboratorio/cloud.local.json`
está habilitado. A linha **Nuvem conectada** informa quantas leituras estão pendentes.
O computador e o painel precisam permanecer ligados. Fechar o painel pausa a cópia;
EMQX e MySQL continuam ligados, e as leituras pendentes são recuperadas ao reabrir.

A conexão usa TLS com validação do certificado e do nome do servidor. As senhas
ficam em arquivos privados, fora do código, do Git e dos pacotes públicos. O banco
local é acessado por uma conta somente de leitura; a nuvem usa uma conta restrita.
Os lotes são enviados do mais antigo para o mais recente. O cursor é salvo na mesma
transação do lote na nuvem, e a identidade da amostra impede duplicação na retomada.

Veja [configuração, recuperação e limites da nuvem](laboratorio/docs/NUVEM.md).

## Dados atuais e histórico — painel 1.6.2

Os cartões mantêm os últimos valores recebidos quando há uma interrupção. Após
10 segundos sem dados, a tela mostra **Sem dados recentes — últimos valores
recebidos**, com data e firmware da leitura. Os valores voltam a atualizar
automaticamente quando o M5 reconecta. A opção **Manter última leitura** vem
marcada; desmarque-a para ocultar os valores quando estiverem desatualizados.
O histórico permanece na tabela. Um registro salvo não comprova a conexão atual.

[Abrir a GitPage do Atleta](https://Babi-Portella.github.io/atleta/).

![Banner](site/assets/banner-atleta-v1.png)

## Entregáveis da primeira N1

| Requisito | Arquivo |
| --- | --- |
| GitPage: Home, Plataforma, Dispositivos e Aplicativo | [site/index.html](site/index.html) |
| Firmware 2.1.7 conectado à plataforma própria | [main.cpp](laboratorio/firmware/src/main.cpp), [activity.h](laboratorio/firmware/src/activity.h), [guia](laboratorio/README.md) |
| Diagrama completo | [SVG](site/assets/diagrama-projeto-v1.svg), [PNG](site/assets/diagrama-projeto-v1.png), [fonte](docs/DIAGRAMA.md) |
| Banner atualizado | [PNG](site/assets/banner-atleta-v1.png) |
| Circuito eletrônico | [SVG](site/assets/circuito-v1.svg), [PNG](site/assets/circuito-v1.png), [pinagem](docs/CIRCUITO.md) |
| Aplicativo da primeira versão | [Painel Windows](laboratorio/entrega/PainelIP.exe) e [código](laboratorio/painel/app.py) |

## Equipe

- **Babi Portella** — [Babi-Portella](https://github.com/Babi-Portella).
- **Emilio467** — [Emilio467](https://github.com/Emilio467).
- **jvBaracho** — [jvBaracho](https://github.com/jvBaracho).

As contribuições individuais serão registradas quando confirmadas; a hospedagem
na conta da Babi não atribui a ela autoria exclusiva do projeto.

## Abrir no Windows

1. Extraia o pacote completo em uma pasta. Instale e inicie Docker Desktop com containers Linux.
2. Abra **ABRIR PAINEL.exe**. Python não é necessário para usar o executável.
3. Marque **Permitir conexão do M5 pela rede** e inicie o laboratório.
4. Configure a rede Wi-Fi de 2,4 GHz e o servidor no M5 usando o botão de configuração por USB.
5. Aguarde **Conexão confirmada** e consulte **Ver dados do atleta**.

Cada instalação nova cria suas credenciais e banco. Senhas, histórico local e
backups privados não integram o repositório. O primeiro início requer internet.

## Organização do projeto

Esta pasta contém uma única versão do projeto. Os arquivos da entrega N1, incluindo
o diagrama revisado, estão incorporados à estrutura principal.

| Local | Conteúdo |
| --- | --- |
| `ABRIR PAINEL.exe` | Atalho executável para iniciar o programa Windows |
| `laboratorio/` | Firmware, painel, EMQX, MySQL, instruções e evidências |
| `site/` | GitPage, banner, diagramas e downloads públicos |
| `docs/` | Documentação geral do projeto |
| `tools/` | Geração dos diagramas e dos pacotes |
| `codigo-original/` | API original preservada para integração futura |
| `.github/` | Publicação automática da GitPage |

Configurações particulares ficam em `laboratorio/config.local.json` e
`laboratorio/runtime/`; o histórico de migração pode existir em `laboratorio/migracao/`.
Esses arquivos são locais e ficam fora do backup compartilhável.

### Gerar um novo backup

Com Python instalado, execute na raiz:

```powershell
python tools/empacotar.py
```

O ZIP completo, o checksum e o manifesto são salvos em `../Backups/Atleta/`.
O processo verifica os binários, a sintaxe Python, os links locais e os ZIPs.
Para escolher o destino, use `--output` com um caminho fora do projeto.
Os dois ZIPs em `site/downloads/` são downloads da GitPage e são regenerados pelo
empacotador. Consulte [o guia de organização](docs/ORGANIZACAO.md).

## Compilar o M5

Requer Python e internet para instalar as dependências. Execute na raiz:

```powershell
python -m venv .venv-lab
.\.venv-lab\Scripts\python.exe -m pip install -r laboratorio\requirements.txt
.\.venv-lab\Scripts\python.exe laboratorio\tools\release.py --firmware-only
```

Para gravar, substitua COM3 pela porta do relógio:

```powershell
.\.venv-lab\Scripts\python.exe laboratorio\tools\flash.py --port COM3
```

O M5 dos testes já usa 2.1.7. Trocar o servidor exige configurar a rede por USB.

## GitHub Pages

O workflow [.github/workflows/pages.yml](.github/workflows/pages.yml) publica
somente `site/`. Em **Settings → Pages**, selecione **GitHub Actions**.
EMQX, o MySQL local e o painel executam no PC servidor. O sincronizador copia as
leituras para a Aiven. A GitPage apresenta o projeto e não consulta o banco.

Prévia local:

```powershell
python -m http.server 8765 --bind 127.0.0.1 --directory site
```

## Validação e limites

Em 02/10/2026, o M5 2.1.7 enviou **12.113 amostras por MQTT/MySQL** na captura.
Uma caminhada de 20 passos curtos registrou **17**; colocar e manusear o relógio
não acrescentou passos nesse ensaio. É uma medição, sem garantia de precisão geral.
Veja [as evidências](laboratorio/evidencias/contador-passos-2.1.7.json).

Distância e calorias são estimativas dependentes do perfil. BPM, SpO₂,
temperatura corporal, GPS e aplicativo móvel ilustrados no banner são expansões
futuras. O esquema do circuito resume os componentes internos utilizados no M5.
O código original FastAPI está preservado e sua integração à telemetria é futura.
