unit Boleto;

{ Validacao e decodificacao de linha digitavel:
  boleto bancario (47 digitos) e arrecadacao/convenio (48 digitos). }

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

type
  TBoletoInfo = record
    Banco: string;          { codigo do banco, 3 digitos }
    Moeda: string;          { 9 = real }
    Fator: Integer;         { fator de vencimento, 0 = sem vencimento }
    TemVencimento: Boolean;
    Vencimento: TDateTime;
    Valor: Currency;
    CodigoBarras: string;   { 44 digitos }
  end;

  TArrecadacaoInfo = record
    Segmento: string;       { 1 digito (1 = prefeituras, 2 = saneamento...) }
    TipoValor: string;      { 6/7 = modulo 10, 8/9 = modulo 11 }
    Modulo11: Boolean;
    TemValor: Boolean;      { so para tipos 6 e 8 (valor efetivo) }
    Valor: Currency;
    CodigoBarras: string;   { 44 digitos }
  end;

function SomenteDigitos(const S: string): string;
function Modulo10(const S: string): Integer;
{ Modulo 11 do codigo de barras do boleto bancario (0, 10 e 11 viram 1). }
function Modulo11Bancario(const S: string): Integer;
{ Modulo 11 da arrecadacao (resto 0 ou 1 vira 0). }
function Modulo11Arrecadacao(const S: string): Integer;

function LinhaBancariaValida(const ALinha: string): Boolean;
function LinhaArrecadacaoValida(const ALinha: string): Boolean;

{ Converte linha digitavel em dados. Retorna False se invalida.
  ADataRef serve para resolver o ciclo do fator (que recomecou em
  22/02/2025); sem ela usa a data de hoje. }
function DecodificarBoleto(const ALinha: string; out AInfo: TBoletoInfo): Boolean; overload;
function DecodificarBoleto(const ALinha: string; ADataRef: TDateTime;
  out AInfo: TBoletoInfo): Boolean; overload;
function DecodificarArrecadacao(const ALinha: string;
  out AInfo: TArrecadacaoInfo): Boolean;

{ Data de vencimento a partir do fator, escolhendo o ciclo de 9000 dias
  mais proximo de ADataRef. Fator 0 devolve 0. }
function VencimentoPorFator(AFator: Integer; ADataRef: TDateTime): TDateTime;

implementation

uses
  SysUtils;

function SomenteDigitos(const S: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
    if S[I] in ['0'..'9'] then
      Result := Result + S[I];
end;

function Modulo10(const S: string): Integer;
var
  I, Peso, P, Soma: Integer;
begin
  Soma := 0;
  Peso := 2;
  for I := Length(S) downto 1 do
  begin
    P := (Ord(S[I]) - 48) * Peso;
    Soma := Soma + (P div 10) + (P mod 10);
    if Peso = 2 then Peso := 1 else Peso := 2;
  end;
  Result := (10 - (Soma mod 10)) mod 10;
end;

function SomaModulo11(const S: string): Integer;
var
  I, Peso: Integer;
begin
  Result := 0;
  Peso := 2;
  for I := Length(S) downto 1 do
  begin
    Result := Result + (Ord(S[I]) - 48) * Peso;
    Inc(Peso);
    if Peso > 9 then Peso := 2;
  end;
end;

function Modulo11Bancario(const S: string): Integer;
begin
  Result := 11 - (SomaModulo11(S) mod 11);
  if Result in [0, 10, 11] then Result := 1;
end;

function Modulo11Arrecadacao(const S: string): Integer;
var
  R: Integer;
begin
  R := SomaModulo11(S) mod 11;
  if R <= 1 then Result := 0 else Result := 11 - R;
end;

function VencimentoPorFator(AFator: Integer; ADataRef: TDateTime): TDateTime;
var
  Base, Cand, Melhor: TDateTime;
  K: Integer;
begin
  if AFator <= 0 then
  begin
    Result := 0;
    Exit;
  end;
  Base := EncodeDate(1997, 10, 7) + AFator;
  Melhor := Base;
  for K := 0 to 3 do
  begin
    Cand := Base + 9000 * K;
    if Abs(Cand - ADataRef) < Abs(Melhor - ADataRef) then
      Melhor := Cand;
  end;
  Result := Melhor;
end;

function CentavosParaMoeda(const S: string): Currency;
var
  C: Int64;
begin
  C := StrToInt64(S);
  Result := C;
  Result := Result / 100;
end;

function DecodificarBoleto(const ALinha: string; ADataRef: TDateTime;
  out AInfo: TBoletoInfo): Boolean;
var
  L, C1, C2, C3, Barras: string;
begin
  Result := False;
  AInfo.Banco := '';
  AInfo.Moeda := '';
  AInfo.Fator := 0;
  AInfo.TemVencimento := False;
  AInfo.Vencimento := 0;
  AInfo.Valor := 0;
  AInfo.CodigoBarras := '';

  L := SomenteDigitos(ALinha);
  if Length(L) <> 47 then Exit;
  C1 := Copy(L, 1, 9);
  C2 := Copy(L, 11, 10);
  C3 := Copy(L, 22, 10);
  if Modulo10(C1) <> Ord(L[10]) - 48 then Exit;
  if Modulo10(C2) <> Ord(L[21]) - 48 then Exit;
  if Modulo10(C3) <> Ord(L[32]) - 48 then Exit;

  { codigo de barras: banco+moeda, DV, fator+valor, campo livre }
  Barras := Copy(L, 1, 4) + Copy(L, 33, 1) + Copy(L, 34, 14) +
    Copy(L, 5, 5) + C2 + C3;
  if Length(Barras) <> 44 then Exit;
  if Modulo11Bancario(Copy(Barras, 1, 4) + Copy(Barras, 6, 39)) <>
     Ord(Barras[5]) - 48 then Exit;

  AInfo.Banco := Copy(Barras, 1, 3);
  AInfo.Moeda := Copy(Barras, 4, 1);
  AInfo.Fator := StrToInt(Copy(Barras, 6, 4));
  AInfo.TemVencimento := AInfo.Fator > 0;
  AInfo.Vencimento := VencimentoPorFator(AInfo.Fator, ADataRef);
  AInfo.Valor := CentavosParaMoeda(Copy(Barras, 10, 10));
  AInfo.CodigoBarras := Barras;
  Result := True;
end;

function DecodificarBoleto(const ALinha: string; out AInfo: TBoletoInfo): Boolean;
begin
  Result := DecodificarBoleto(ALinha, Date, AInfo);
end;

function LinhaBancariaValida(const ALinha: string): Boolean;
var
  Info: TBoletoInfo;
begin
  Result := DecodificarBoleto(ALinha, Date, Info);
end;

function DecodificarArrecadacao(const ALinha: string;
  out AInfo: TArrecadacaoInfo): Boolean;
var
  L, Bloco, Barras: string;
  I: Integer;
  Mod11: Boolean;
  DvEsperado, DvGeral: Integer;
begin
  Result := False;
  AInfo.Segmento := '';
  AInfo.TipoValor := '';
  AInfo.Modulo11 := False;
  AInfo.TemValor := False;
  AInfo.Valor := 0;
  AInfo.CodigoBarras := '';

  L := SomenteDigitos(ALinha);
  if Length(L) <> 48 then Exit;
  if L[1] <> '8' then Exit;
  if not (L[3] in ['6'..'9']) then Exit;
  Mod11 := L[3] in ['8', '9'];

  Barras := '';
  for I := 0 to 3 do
  begin
    Bloco := Copy(L, I * 12 + 1, 11);
    if Mod11 then DvEsperado := Modulo11Arrecadacao(Bloco)
    else DvEsperado := Modulo10(Bloco);
    if DvEsperado <> Ord(L[I * 12 + 12]) - 48 then Exit;
    Barras := Barras + Bloco;
  end;

  { DV geral na posicao 4 do codigo de barras }
  if Mod11 then DvGeral := Modulo11Arrecadacao(Copy(Barras, 1, 3) + Copy(Barras, 5, 40))
  else DvGeral := Modulo10(Copy(Barras, 1, 3) + Copy(Barras, 5, 40));
  if DvGeral <> Ord(Barras[4]) - 48 then Exit;

  AInfo.Segmento := Barras[2];
  AInfo.TipoValor := Barras[3];
  AInfo.Modulo11 := Mod11;
  AInfo.TemValor := AInfo.TipoValor[1] in ['6', '8'];
  if AInfo.TemValor then
    AInfo.Valor := CentavosParaMoeda(Copy(Barras, 5, 11));
  AInfo.CodigoBarras := Barras;
  Result := True;
end;

function LinhaArrecadacaoValida(const ALinha: string): Boolean;
var
  Info: TArrecadacaoInfo;
begin
  Result := DecodificarArrecadacao(ALinha, Info);
end;

end.
