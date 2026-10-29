# delphi-pix-boleto-cep

Tres coisas que todo sistema brasileiro acaba precisando, em Object Pascal puro e sem dependencias externas:

- **Pix**: gera o payload do QR Code estatico (BR Code / EMV, com CRC16-CCITT) e valida um payload existente.
- **Boleto**: valida e decodifica a linha digitavel de boleto bancario (47 digitos) e de arrecadacao/convenio (48 digitos): modulos 10 e 11, vencimento pelo fator e valor.
- **CEP**: consulta por uma interface (`ICepProvider`), com implementacao ViaCEP sobre uma camada HTTP que voce injeta e um provider falso para testes.

Tudo roda offline nos testes. Nenhum teste faz chamada de rede.

## Como usar

Copie a pasta `src` para o seu projeto (ou adicione ao search path) e use as units que precisar.

### Pix

```pascal
uses Pix;

var
  Payload, Erro: string;
  Info: TPixInfo;
begin
  // Pix com valor fixo
  Payload := GerarPayloadPix('123e4567-e12b-12d1-a456-426655440000',
    'Fulano de Tal', 'Brasilia', 123.45);

  // Pix sem valor (quem paga digita), com identificador
  Payload := GerarPayloadPix('fulano@exemplo.com', 'Fulano de Tal', 'Brasilia',
    0, 'PEDIDO123');

  if ValidarPayloadPix(Payload, Info, Erro) then
    WriteLn(Info.Nome, ' / ', Info.Cidade)
  else
    WriteLn('Payload invalido: ', Erro);
end;
```

O resultado e o texto do "copia e cola"; para o QR Code, passe a string para qualquer biblioteca que desenhe QR.
Nome (ate 25) e cidade (ate 15) sao cortados e convertidos para maiusculas sem acento. A funcao `Crc16Ccitt` tambem esta exposta.

### Linha digitavel

```pascal
uses Boleto;

var
  B: TBoletoInfo;
  A: TArrecadacaoInfo;
begin
  if DecodificarBoleto('00190.50095 40144.816069 06809.350314 3 37370000000100', B) then
    WriteLn(B.Banco, ' R$ ', CurrToStr(B.Valor), ' vence ', DateToStr(B.Vencimento));

  if DecodificarArrecadacao('816100000016234501234566789012345672890123456711', A) then
    WriteLn('Conta de convenio, valor ', CurrToStr(A.Valor));
end;
```

A linha pode vir com pontos e espacos. O fator de vencimento recomecou em 22/02/2025 (voltou a 1000); por isso `DecodificarBoleto` aceita uma data de referencia e escolhe o ciclo mais proximo dela (sem informar, usa a data de hoje). Fator 0 significa boleto sem vencimento.
A validacao confere os digitos verificadores, nao diz se o boleto existe nem se esta pago.

### CEP

```pascal
uses Cep, CepHttpDelphi;

var
  Prov: ICepProvider;
  End_: TEndereco;
begin
  Prov := TViaCepProvider.Create(TNetHttpGet.Create);  // Delphi: System.Net.HttpClient
  if Prov.Consultar('01001-000', End_) then
    WriteLn(End_.Logradouro, ', ', End_.Localidade, '/', End_.UF)
  else
    WriteLn('CEP nao encontrado');
end;
```

`Consultar` devolve `False` quando o CEP nao existe, levanta `ECepInvalido` para CEP mal formado e `ECepFalha` para erro de rede ou resposta ilegivel.

A camada HTTP e a interface `IHttpGet` (um unico metodo `Get(url): string`). Use `TNetHttpGet` (Delphi), escreva uma em Indy, fphttpclient ou o que preferir. Em testes, use `TCepFalso`:

```pascal
Fake := TCepFalso.Create;
Fake.Adicionar(Endereco);
Prov := Fake;
```

O JSON e lido com `System.JSON` no Delphi e com `fpjson` no Free Pascal.

## Rodar os testes

Com Free Pascal (modo Delphi), a partir da raiz do repositorio:

```
mkdir bin
fpc -Mdelphi -Fusrc -FEbin -FUbin tests/Testes.dpr
bin/Testes.exe
```

O programa imprime `[ok]` ou `[FALHA]` por caso e termina com codigo 1 se algo falhar. Sao 79 casos, entre eles:

- CRC16 de `123456789` = `29B1`;
- payloads Pix comparados com vetores calculados por um script independente;
- uma linha digitavel publica muito citada (Banco do Brasil, R$ 1,00, vencimento 31/12/2007);
- linhas de teste com digitos verificadores corretos, adulteracoes que devem ser rejeitadas, ciclo do fator de vencimento;
- ViaCEP com HTTP falso (URL montada, CEP inexistente, falha de rede, JSON invalido).

Algumas linhas digitaveis dos testes foram geradas por script apenas para exercitar os calculos; nao sao boletos reais.

## Estrutura

```
src/
  Pix.pas             payload Pix, CRC16, validador
  Boleto.pas          linha digitavel 47 e 48 digitos
  Cep.pas             ICepProvider, ViaCEP, TCepFalso, parsing JSON
  CepHttpDelphi.pas   IHttpGet com System.Net.HttpClient (so Delphi)
tests/
  Testes.dpr          programa de testes (console)
```

## O que foi (e o que nao foi) validado

Os testes foram compilados e executados com **Free Pascal 3.2.2 em modo Delphi** (`-Mdelphi`). Eu **nao** compilei nem testei na IDE Delphi: o codigo usa so recursos comuns (Delphi 10+ em tese), mas isso ainda e uma expectativa, nao um resultado medido. Dois pontos que dependem do Delphi e nao passaram por nenhum compilador aqui: o caminho `System.JSON` em `Cep.pas` e a unit `CepHttpDelphi.pas`.

Limites conhecidos:

- Pix: so o payload estatico. Pix dinamico (com URL do PSP) nao esta coberto.
- Acentos: a remocao de acentos em nome e cidade funciona em Delphi com strings Unicode; no Free Pascal o texto fora do ASCII e descartado.
- A consulta real ao ViaCEP depende do servico deles e nao e exercitada nos testes.

## Licenca

MIT. Veja [LICENSE](LICENSE).
