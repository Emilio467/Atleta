# Sincronização com a Aiven

## Uso neste computador

Neste computador, abra `ABRIR ATLETA.cmd` da pasta ATLETA-PROJETO e use
**Preparar computador** se o servidor estiver parado. O painel inicia a cópia
para a nuvem automaticamente. A linha abaixo dos botões
mostra conexão, pendências ou o motivo da falha. O resultado mais recente também
fica em `laboratorio/runtime/cloud-status.json`, sem senhas.

O ESP32 continua enviando ao EMQX local. O painel lê o MySQL local e replica para
a Aiven. Portanto, o computador deve permanecer ligado e o painel aberto para
sincronizar. Ao fechar o painel, os serviços locais continuam funcionando e a
cópia para a nuvem é pausada. Ao reabrir, ela retoma as leituras pendentes.

## Configurar outra instalação

1. Prepare o laboratório pelo painel, sem reutilizar credenciais de outra instalação.
2. Copie `cloud.example.json` para `cloud.local.json` dentro de `laboratorio`.
3. Preencha host, porta, banco, usuário e senha obtidos na Aiven e `enabled: true`.
   A senha também pode vir da variável `ATLETA_CLOUD_PASSWORD`.
4. Baixe o certificado CA do serviço pela conta Aiven. Salve-o em
   `laboratorio/runtime/aiven-ca.pem`. Não use um certificado obtido de uma
   conexão que não foi validada.
5. Instale `laboratorio/painel/requirements-build.txt` em um ambiente Python.
6. Na primeira preparação, use a credencial administrativa e execute:

```powershell
python laboratorio/tools/provision_cloud.py
```

Esse comando cria apenas tabelas ausentes e uma conta dedicada, com TLS obrigatório,
SELECT/INSERT em telemetry e SELECT/INSERT/UPDATE no cursor de sincronização.
Confere a conexão da nova conta e a salva em `cloud.local.json`. A configuração
administrativa anterior fica somente em `runtime/cloud-admin.local.json` para
manutenção; ela não é usada pelo painel. O comando não muda a senha administrativa.
Se essa senha já foi publicada ou distribuída, o titular deve rotacioná-la na Aiven.

Se o banco existente possui a relação telemetry → mqtt_users, a preparação cadastra
identidades locais ausentes como registros desabilitados, sem copiar senhas MQTT.
Novos dispositivos que exijam cadastro podem ser preparados repetindo esse comando.
Não remove tabelas, registros ou índices existentes. Esquemas incompatíveis geram erro.

## Quando aparecer falha de DNS

Essa mensagem significa que o endereço configurado não pôde ser convertido em um
endereço de rede. O sincronizador continua tentando, sem descartar leituras locais.
O erro sozinho não permite concluir se o serviço está desligado ou se o endereço mudou.

O titular da conta Aiven deve abrir o serviço MySQL e verificar seu estado e os
dados de conexão. Se estiver desligado, pode usar **Actions → Power on service**.
Confira o host e a porta da página **Overview** com `cloud.local.json`. Se mudarem,
atualize os dois campos nesse arquivo; o painel os lê novamente a cada tentativa.
Se o destino for outro serviço ou projeto, confira também o certificado CA e as
credenciais antes de enviar os dados. A senha do MySQL não dá acesso ao painel Aiven.

Mantenha o MySQL local e seu histórico. Após restabelecer a conexão, a cópia retoma
do último lote confirmado. Só considere a nuvem validada depois de consultar uma
leitura recente no destino e conferir que não existem leituras pendentes.

Referência: [Aiven: ligar o serviço MySQL](https://aiven.io/docs/products/mysql/howto/power-cycle-service).

## Terminal opcional

```powershell
python enviar_nuvem.py --uma-vez
python enviar_nuvem.py
```

O primeiro comando envia um lote; o segundo continua enviando até Ctrl+C. A opção
`--pasta` permite indicar outra pasta de laboratório. O executável do painel já
inclui as bibliotecas e não exige Python no computador de uso diário.

## Integridade e retomada

- TLS 1.2 ou superior, com CA confiável e nome do servidor conferidos.
- Acesso local somente de leitura pelo usuário `lab_reader` da instalação.
- Lotes em ordem crescente do ID local, sem descartar o histórico antigo.
- Uma leitura compartilhada aguarda inserções ainda não confirmadas com ID menor;
  os bloqueios locais são liberados antes do envio à nuvem.
- Identidade única: mqtt_username + boot_id + sample_seq.
- O cursor e as inserções são confirmados na mesma transação InnoDB na nuvem.
- Repetição após queda não duplica amostras. Conteúdo divergente para a mesma
  identidade interrompe o lote sem sobrescrever dados.
- Cursor separado por UUID do servidor local e banco. Alteração/remoção da
  amostra que ancora o cursor faz a leitura recomeçar, com deduplicação.
- Datas são interpretadas em UTC; os campos e o JSON são preservados.
- Leituras source=test continuam marcadas como teste.
- Timeout em conexão, leitura e escrita; falhas são repetidas com espera limitada.

O histórico local deve ser mantido até a confirmação da cópia. Exclusões manuais
na nuvem não são uma operação suportada de sincronização. Após restaurar o destino,
um administrador pode reiniciar os cursores para revalidar todo o histórico.
O trecho ESP32 → EMQX continua sendo MQTT local sem TLS, QoS 0 e sem fila persistente
na placa; a nuvem só recupera amostras que já chegaram ao MySQL local.

## Pacotes e testes

`tools/empacotar.py` inclui o sincronizador e seu exemplo, e exclui runtime, arquivos
.env, config.json, *.local.json, certificados e chaves. O ZIP público não é uma
migração privada pronta: configure novamente a nuvem e a rede no computador destino.

```powershell
python -m unittest discover -s laboratorio/painel -p "test_*.py"
python laboratorio/tools/test_cloud_integration.py --run -v
```

O segundo comando cria duas bases temporárias de teste no MySQL local, com nomes
aleatórios `teste_nuvem_*`, e as remove ao terminar. Não envia dados de teste para
a Aiven. Testa histórico, repetição, concorrência, falha antes/depois do commit,
conflitos, restauração do banco, TLS e exclusão de arquivos privados dos pacotes.

Referências: [Aiven: certificados CA](https://aiven.io/docs/platform/concepts/tls-ssl-certificates)
e [PyMySQL: conexão TLS](https://pymysql.readthedocs.io/en/latest/modules/connections.html).
