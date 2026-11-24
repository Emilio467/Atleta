# Organização e backup

Estrutura consolidada em 19/10/2026, com firmware 2.1.7, painel Windows 1.5.0 e
diagrama revisado da entrega N1.

## Arquivos de trabalho

- `laboratorio/firmware/src/`: código do M5 e contador de passos.
- `laboratorio/entrega/`: executável do painel, firmware compilado e seus manifestos.
- `laboratorio/painel/`, `laboratorio/tools/`, `laboratorio/emqx/` e `laboratorio/sql/`:
  código e configuração da plataforma.
- `laboratorio/evidencias/`: registros dos testes já realizados.
- `site/`, `docs/`, `tools/` e `.github/`: apresentação, documentação e publicação.
- `codigo-original/`: API original para integração futura.

## Configuração e histórico locais

`laboratorio/runtime/`, `laboratorio/config.local.json`,
`laboratorio/endereco-servidor.json` e `laboratorio/migracao/` podem conter dados
da instalação. Eles permanecem locais, ignorados pelo Git e excluídos dos pacotes
compartilháveis. Os volumes do Docker são administrados pelo Docker.

## Gerar o backup compartilhável

```powershell
python tools/empacotar.py
```

O destino padrão é `../Backups/Atleta/`, fora da árvore do projeto. Cada execução
gera um ZIP com data e hora, seu checksum SHA-256 e um manifesto com os arquivos
incluídos. Um nome já existente não é substituído.

O pacote inclui fontes, executáveis, firmware compilado, documentação, GitPage,
diagramas, banner e evidências públicas. No outro PC, extraia todo o ZIP e siga
`LEIA PRIMEIRO.txt`. É preciso configurar novamente a rede e o M5.

## Evitar novos acúmulos

- Guarde backups fora do projeto.
- As pastas `entrega-v1` e `publicacao-n1` deixaram de ser cópias de trabalho;
  seus arquivos atuais estão na estrutura principal.
- `.pio/`, `.pio-core/`, ambientes virtuais e instaladores são recriáveis e não
  fazem parte do backup compartilhável.
- Os ZIPs de `site/downloads/` atendem aos links da GitPage; mantenha esses dois
  arquivos ou regenere-os com o empacotador antes de publicar o site.

As cópias anteriores à organização foram guardadas separadamente em
`../Backups/Atleta/arquivo-anterior-2026-10-19/`. Essa pasta preserva o estado local
antigo e pode conter configurações particulares; use o novo ZIP compartilhável
para enviar o projeto.
