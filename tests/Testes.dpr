program Testes;

{$APPTYPE CONSOLE}
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

uses
  SysUtils,
  Pix in '..\src\Pix.pas',
  Boleto in '..\src\Boleto.pas',
  Cep in '..\src\Cep.pas';

const
  CHAVE = '123e4567-e12b-12d1-a456-426655440000';
  { calculados por um script independente (python), nao por esta biblioteca }
  PIX_SEM_VALOR =
    '00020101021126580014br.gov.bcb.pix0136123e4567-e12b-12d1-a456-426655440000' +
    '5204000053039865802BR5913FULANO DE TAL6008BRASILIA62070503***6304A5E2';
  PIX_COM_VALOR =
    '00020101021126580014br.gov.bcb.pix0136123e4567-e12b-12d1-a456-426655440000' +
    '5204000053039865406123.455802BR5913FULANO DE TAL6008BRASILIA62070503***63047818';

  { linhas de teste com digitos verificadores corretos (geradas por script,
    nao sao boletos reais) }
  LINHA_1 = '23793.81284 60000.000004 00004.081238 3 84340000012345';
  LINHA_2 = '00191234546789012345767890123457300000000000000';
  LINHA_3 = '34191090162345678901723456789017910100000150075';
  LINHA_4 = '03399999979999999999099999999990130000000000100';
  { exemplo publico muito citado (Banco do Brasil, vencimento 31/12/2007, R$ 1,00) }
  LINHA_BB = '00190.50095 40144.816069 06809.350314 3 37370000000100';
  LINHA_5 = '10491111132222233333244444555559310000000010000';
  ARREC_1 = '816100000016234501234566789012345672890123456711';
  ARREC_2 = '82830000009 09999987654 37210987654 32210987654 3212';

var
  Falhas: Integer = 0;
  Total: Integer = 0;

procedure Verificar(const ANome: string; ACondicao: Boolean);
begin
  Inc(Total);
  if ACondicao then
    WriteLn('[ok]    ', ANome)
  else
  begin
    Inc(Falhas);
    WriteLn('[FALHA] ', ANome);
  end;
end;

function Perto(A: Currency; B: Double): Boolean;
begin
  Result := Abs(A - B) < 0.0001;
end;

function Troca(const S: string; Pos: Integer; Digito: Char): string;
begin
  Result := S;
  Result[Pos] := Digito;
end;

function ExcecaoDe(const ACep: string; AProv: ICepProvider): string;
var
  E: TEndereco;
begin
  Result := '';
  try
    AProv.Consultar(ACep, E);
  except
    on Ex: Exception do Result := Ex.ClassName;
  end;
end;

{ ---------- Pix ---------- }

procedure TestarPix;
var
  Info: TPixInfo;
  Erro, P: string;
begin
  Verificar('CRC16 de "123456789" = 29B1', Crc16Ccitt('123456789') = '29B1');
  Verificar('CRC16 de string vazia = FFFF', Crc16Ccitt('') = 'FFFF');
  Verificar('CRC16 tem 4 hexadecimais', Length(Crc16Ccitt('abc')) = 4);

  Verificar('Payload sem valor bate com o vetor',
    GerarPayloadPix(CHAVE, 'Fulano de Tal', 'Brasilia') = PIX_SEM_VALOR);
  Verificar('Payload com valor 123,45 bate com o vetor',
    GerarPayloadPix(CHAVE, 'Fulano de Tal', 'Brasilia', 123.45) = PIX_COM_VALOR);
  Verificar('Valor com um centavo vira 0.01',
    Pos('54040.01', GerarPayloadPix(CHAVE, 'A', 'B', 0.01)) > 0);
  Verificar('Nome em minusculas vira maiusculo',
    Pos('5903ANA', GerarPayloadPix(CHAVE, 'ana', 'Rio')) > 0);
  Verificar('Nome e cortado em 25 caracteres',
    Pos('5925' + StringOfChar('X', 25) + '60',
      GerarPayloadPix(CHAVE, StringOfChar('x', 40), 'Rio')) > 0);
  Verificar('Cidade e cortada em 15 caracteres',
    Pos('6015' + StringOfChar('C', 15) + '62',
      GerarPayloadPix(CHAVE, 'Ana', StringOfChar('c', 30))) > 0);
  Verificar('TxId informado entra no campo 62',
    Pos('0507PEDIDO1', GerarPayloadPix(CHAVE, 'Ana', 'Rio', 0, 'PEDIDO1')) > 0);
  Verificar('Descricao entra na conta (02)',
    Pos('0207Aluguel', GerarPayloadPix(CHAVE, 'Ana', 'Rio', 0, '', 'Aluguel')) > 0);

  Verificar('Valida o payload sem valor', ValidarPayloadPix(PIX_SEM_VALOR));
  Verificar('Valida o payload com valor', ValidarPayloadPix(PIX_COM_VALOR));
  Verificar('Decodifica chave, nome, cidade e txid',
    ValidarPayloadPix(PIX_COM_VALOR, Info, Erro) and (Info.Chave = CHAVE) and
    (Info.Nome = 'FULANO DE TAL') and (Info.Cidade = 'BRASILIA') and
    (Info.TxId = '***'));
  Verificar('Decodifica o valor 123,45',
    ValidarPayloadPix(PIX_COM_VALOR, Info, Erro) and Info.TemValor and
    Perto(Info.Valor, 123.45));
  Verificar('Payload sem valor nao tem valor',
    ValidarPayloadPix(PIX_SEM_VALOR, Info, Erro) and not Info.TemValor);

  Verificar('CRC adulterado e rejeitado',
    not ValidarPayloadPix(Copy(PIX_SEM_VALOR, 1, Length(PIX_SEM_VALOR) - 1) + '3'));
  Verificar('Mensagem de erro diz CRC',
    (not ValidarPayloadPix(Troca(PIX_SEM_VALOR, 40, 'Z'), Info, Erro)) and
    (Pos('CRC', Erro) > 0));
  Verificar('Texto vazio e rejeitado', not ValidarPayloadPix(''));
  Verificar('Payload truncado e rejeitado',
    not ValidarPayloadPix(Copy(PIX_SEM_VALOR, 1, 50)));
  Verificar('Sem 000201 no inicio e rejeitado',
    not ValidarPayloadPix('99' + Copy(PIX_SEM_VALOR, 3, Length(PIX_SEM_VALOR))));

  { monta um payload com CRC correto mas sem o campo 59 }
  P := '00020101021126580014br.gov.bcb.pix0136' + CHAVE +
    '520400005303986' + '5802BR' + '6008BRASILIA' + '62070503***' + '6304';
  P := P + Crc16Ccitt(P);
  Verificar('Falta o nome (59) e rejeitado',
    (not ValidarPayloadPix(P, Info, Erro)) and (Pos('59', Erro) > 0));

  try
    GerarPayloadPix('', 'Ana', 'Rio');
    Verificar('Chave vazia levanta excecao', False);
  except
    Verificar('Chave vazia levanta excecao', True);
  end;
  try
    GerarPayloadPix(CHAVE, 'Ana', 'Rio', -1);
    Verificar('Valor negativo levanta excecao', False);
  except
    Verificar('Valor negativo levanta excecao', True);
  end;
end;

{ ---------- Boleto ---------- }

procedure TestarBoleto;
var
  B: TBoletoInfo;
  A: TArrecadacaoInfo;
  Ref: TDateTime;
begin
  Ref := EncodeDate(2020, 10, 1);

  Verificar('Modulo 10 de 001905009 = 5', Modulo10('001905009') = 5);
  Verificar('Modulo 10 de 4014849637 = 1', Modulo10('4014481606') = 9);
  Verificar('Modulo 11 bancario devolve 1 quando daria 0/10/11',
    Modulo11Bancario('00000000000000000000000000000000000000000') = 1);
  Verificar('Modulo 11 arrecadacao com resto 0 ou 1 devolve 0',
    Modulo11Arrecadacao('00000000000') = 0);
  Verificar('SomenteDigitos tira pontos e espacos',
    SomenteDigitos('23793.81284 60000') = '2379381284' + '60000');

  Verificar('Linha publica do BB e valida', LinhaBancariaValida(LINHA_BB));
  Verificar('Linha publica do BB: banco 001, R$ 1,00, 31/12/2007',
    DecodificarBoleto(LINHA_BB, EncodeDate(2007, 12, 1), B) and (B.Banco = '001') and
    Perto(B.Valor, 1) and (Trunc(B.Vencimento) = Trunc(EncodeDate(2007, 12, 31))));
  Verificar('Linha 1 (com mascara) e valida', LinhaBancariaValida(LINHA_1));
  Verificar('Linha 2 e valida', LinhaBancariaValida(LINHA_2));
  Verificar('Linha 3 e valida', LinhaBancariaValida(LINHA_3));
  Verificar('Linha 4 e valida', LinhaBancariaValida(LINHA_4));
  Verificar('Linha 5 e valida', LinhaBancariaValida(LINHA_5));

  Verificar('Linha 1: banco 237, moeda 9, valor 123,45',
    DecodificarBoleto(LINHA_1, Ref, B) and (B.Banco = '237') and
    (B.Moeda = '9') and Perto(B.Valor, 123.45));
  Verificar('Linha 1: vencimento 09/11/2020 (fator 8434)',
    DecodificarBoleto(LINHA_1, Ref, B) and B.TemVencimento and
    (B.Fator = 8434) and (Trunc(B.Vencimento) = Trunc(EncodeDate(2020, 11, 9))));
  Verificar('Linha 1: codigo de barras tem 44 digitos',
    DecodificarBoleto(LINHA_1, Ref, B) and (Length(B.CodigoBarras) = 44) and
    (Copy(B.CodigoBarras, 1, 4) = '2379'));
  Verificar('Linha 2: fator 0 significa sem vencimento',
    DecodificarBoleto(LINHA_2, Ref, B) and not B.TemVencimento and
    (B.Vencimento = 0));
  Verificar('Linha 2: valor zero', DecodificarBoleto(LINHA_2, Ref, B) and Perto(B.Valor, 0));
  Verificar('Linha 3: valor 1500,75 e vencimento 13/07/2000',
    DecodificarBoleto(LINHA_3, EncodeDate(2000, 6, 1), B) and Perto(B.Valor, 1500.75) and
    (Trunc(B.Vencimento) = Trunc(EncodeDate(2000, 7, 13))));
  Verificar('Linha 4: vencimento 24/12/2005',
    DecodificarBoleto(LINHA_4, EncodeDate(2005, 12, 1), B) and
    (Trunc(B.Vencimento) = Trunc(EncodeDate(2005, 12, 24))));
  Verificar('Fator 1000 em 2025 cai em 22/02/2025 (ciclo reiniciado)',
    DecodificarBoleto(LINHA_5, EncodeDate(2025, 6, 1), B) and
    (Trunc(B.Vencimento) = Trunc(EncodeDate(2025, 2, 22))));
  Verificar('Fator 1000 em 2000 cai em 03/07/2000',
    DecodificarBoleto(LINHA_5, EncodeDate(2000, 6, 1), B) and
    (Trunc(B.Vencimento) = Trunc(EncodeDate(2000, 7, 3))));

  Verificar('DV de campo adulterado e rejeitado',
    not LinhaBancariaValida(Troca(LINHA_2, 10, '0')));
  Verificar('Digito do campo livre adulterado e rejeitado',
    not LinhaBancariaValida(Troca(LINHA_2, 6, '9')));
  Verificar('DV geral adulterado e rejeitado',
    not LinhaBancariaValida(Troca(LINHA_2, 33, '9')));
  Verificar('Valor adulterado e rejeitado',
    not LinhaBancariaValida(Troca(LINHA_3, 47, '9')));
  Verificar('Linha curta e rejeitada', not LinhaBancariaValida('1234'));
  Verificar('Linha vazia e rejeitada', not LinhaBancariaValida(''));

  Verificar('Arrecadacao 1 (modulo 10) e valida', LinhaArrecadacaoValida(ARREC_1));
  Verificar('Arrecadacao 2 (modulo 11, com espacos) e valida',
    LinhaArrecadacaoValida(ARREC_2));
  Verificar('Arrecadacao 1: segmento 1, valor 123,45',
    DecodificarArrecadacao(ARREC_1, A) and (A.Segmento = '1') and A.TemValor and
    not A.Modulo11 and Perto(A.Valor, 123.45) and (Length(A.CodigoBarras) = 44));
  Verificar('Arrecadacao 2: modulo 11, valor 999,99',
    DecodificarArrecadacao(ARREC_2, A) and A.Modulo11 and Perto(A.Valor, 999.99));
  Verificar('Arrecadacao adulterada e rejeitada',
    not LinhaArrecadacaoValida(Troca(ARREC_1, 20, '9')));
  Verificar('Linha de 47 digitos nao passa como arrecadacao',
    not LinhaArrecadacaoValida(LINHA_2));
  Verificar('Linha de 48 digitos nao passa como bancaria',
    not LinhaBancariaValida(ARREC_1));
end;

{ ---------- CEP ---------- }

type
  { HTTP falso: devolve um corpo fixo ou levanta erro }
  THttpFalso = class(TInterfacedObject, IHttpGet)
  public
    Corpo: string;
    Falhar: Boolean;
    UltimaUrl: string;
    function Get(const AUrl: string): string;
  end;

function THttpFalso.Get(const AUrl: string): string;
begin
  UltimaUrl := AUrl;
  if Falhar then raise Exception.Create('sem rede');
  Result := Corpo;
end;

const
  JSON_OK =
    '{"cep":"01001-000","logradouro":"Pra\u00e7a da S\u00e9","complemento":"lado \u00edmpar",' +
    '"bairro":"S\u00e9","localidade":"S\u00e3o Paulo","uf":"SP","ibge":"3550308","gia":"1004"}';

procedure TestarCep;
var
  Fake: TCepFalso;
  Prov: ICepProvider;
  Http: THttpFalso;
  HttpI: IHttpGet;
  E: TEndereco;
  X: TEndereco;
begin
  Verificar('CepNormalizar tira o hifen', CepNormalizar('01001-000') = '01001000');
  Verificar('CepFormatar poe o hifen', CepFormatar('01001000') = '01001-000');
  Verificar('CEP valido', CepValido('01001-000'));
  Verificar('CEP com 7 digitos e invalido', not CepValido('0100100'));
  Verificar('CEP 00000000 e invalido', not CepValido('00000-000'));
  Verificar('CEP com letras e invalido', not CepValido('abcde-fgh'));

  Verificar('ParseViaCep le localidade e UF',
    ParseViaCep(JSON_OK, E) and (E.UF = 'SP') and (Pos('Paulo', E.Localidade) > 0));
  Verificar('ParseViaCep normaliza o CEP e le o IBGE',
    ParseViaCep(JSON_OK, E) and (E.Cep = '01001000') and (E.Ibge = '3550308'));
  Verificar('ParseViaCep devolve False com "erro": true',
    not ParseViaCep('{"erro": true}', E));
  Verificar('ParseViaCep devolve False com "erro": "true"',
    not ParseViaCep('{"erro": "true"}', E));
  try
    ParseViaCep('isto nao e json', E);
    Verificar('JSON invalido levanta ECepFalha', False);
  except
    on Ex: ECepFalha do Verificar('JSON invalido levanta ECepFalha', True);
    on Ex: Exception do Verificar('JSON invalido levanta ECepFalha', False);
  end;

  { provider falso }
  Fake := TCepFalso.Create;
  Prov := Fake;
  X.Cep := '01310-100'; X.Logradouro := 'Avenida Paulista'; X.Complemento := '';
  X.Bairro := 'Bela Vista'; X.Localidade := 'Sao Paulo'; X.UF := 'SP'; X.Ibge := '3550308';
  Fake.Adicionar(X);
  Verificar('TCepFalso encontra CEP cadastrado',
    Prov.Consultar('01310100', E) and (E.Logradouro = 'Avenida Paulista'));
  Verificar('TCepFalso aceita CEP com mascara',
    Prov.Consultar('01310-100', E) and (E.Bairro = 'Bela Vista'));
  Verificar('TCepFalso devolve False para CEP desconhecido',
    not Prov.Consultar('12345-678', E));
  Verificar('TCepFalso levanta ECepInvalido para CEP mal formado',
    ExcecaoDe('123', Prov) = 'ECepInvalido');
  Verificar('TCepFalso conta as consultas', Fake.Consultas = 4);

  { ViaCEP com HTTP injetado }
  Http := THttpFalso.Create;
  HttpI := Http;
  Prov := TViaCepProvider.Create(HttpI);
  Http.Corpo := JSON_OK;
  Verificar('ViaCep monta a URL esperada',
    Prov.Consultar('01001-000', E) and
    (Http.UltimaUrl = 'https://viacep.com.br/ws/01001000/json/'));
  Verificar('ViaCep devolve o endereco', (E.UF = 'SP') and (E.Cep = '01001000'));
  Http.Corpo := '{"erro": true}';
  Verificar('ViaCep devolve False para CEP inexistente',
    not Prov.Consultar('01001-000', E));
  Http.Falhar := True;
  Verificar('Falha de rede vira ECepFalha',
    ExcecaoDe('01001-000', Prov) = 'ECepFalha');
  Verificar('CEP invalido nem chega no HTTP',
    (ExcecaoDe('12', Prov) = 'ECepInvalido'));
end;

begin
  TestarPix;
  TestarBoleto;
  TestarCep;
  WriteLn;
  WriteLn(Total, ' testes, ', Falhas, ' falha(s)');
  if Falhas > 0 then Halt(1);
end.
