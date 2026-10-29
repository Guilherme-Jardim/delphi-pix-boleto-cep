unit Pix;

{ Gerador e validador de payload Pix estatico (BR Code / EMV). }

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

type
  TPixInfo = record
    Chave: string;
    Descricao: string;
    Nome: string;
    Cidade: string;
    TxId: string;
    Valor: Currency;
    TemValor: Boolean;
  end;

{ CRC16-CCITT (polinomio 1021, inicial FFFF), em 4 hexadecimais maiusculos. }
function Crc16Ccitt(const S: string): string;

{ Passa para maiuscula e descarta o que nao for ASCII imprimivel.
  Em Delphi (Unicode) tambem tira acentos Latin-1. Usado em nome e cidade. }
function PixTextoSeguro(const S: string): string;

{ Monta o payload. AValor = 0 gera um Pix sem valor fixo.
  ATxId vazio vira '***'. Levanta Exception se algum campo for invalido. }
function GerarPayloadPix(const AChave, ANome, ACidade: string;
  AValor: Currency = 0; const ATxId: string = '';
  const ADescricao: string = ''): string;

{ Confere estrutura, campos obrigatorios e CRC. Preenche AInfo quando valido. }
function ValidarPayloadPix(const APayload: string; out AInfo: TPixInfo;
  out AErro: string): Boolean; overload;
function ValidarPayloadPix(const APayload: string): Boolean; overload;

implementation

uses
  SysUtils;

const
  GUI_PIX = 'br.gov.bcb.pix';
  { Latin-1 192..255 sem acento }
  SEM_ACENTO = 'AAAAAAACEEEEIIIIDNOOOOOxOUUUUYTs' +
               'aaaaaaaceeeeiiiidnooooo/ouuuuyty';

function Crc16Ccitt(const S: string): string;
var
  Crc, I, B: Integer;
begin
  Crc := $FFFF;
  for I := 1 to Length(S) do
  begin
    Crc := Crc xor ((Ord(S[I]) and $FF) shl 8);
    for B := 1 to 8 do
      if (Crc and $8000) <> 0 then
        Crc := ((Crc shl 1) xor $1021) and $FFFF
      else
        Crc := (Crc shl 1) and $FFFF;
  end;
  Result := IntToHex(Crc, 4);
end;

function PixTextoSeguro(const S: string): string;
var
  I, C: Integer;
  Ch: Char;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    C := Ord(S[I]);
    if (C >= 32) and (C <= 126) then
      Ch := S[I]
    else if (SizeOf(Char) > 1) and (C >= 192) and (C <= 255) then
      Ch := SEM_ACENTO[C - 191]
    else
      Continue;
    Result := Result + UpCase(Ch);
  end;
end;

function Campo(const AId, AValor: string): string;
begin
  Result := AId + Format('%.2d', [Length(AValor)]) + AValor;
end;

function FormatarValor(AValor: Currency): string;
var
  Cent: Int64;
begin
  Cent := Round(AValor * 100);
  Result := IntToStr(Cent div 100) + '.' + Format('%.2d', [Cent mod 100]);
end;

function GerarPayloadPix(const AChave, ANome, ACidade: string;
  AValor: Currency; const ATxId: string; const ADescricao: string): string;
var
  Nome, Cidade, TxId, Conta, Sem: string;
begin
  if Trim(AChave) = '' then
    raise Exception.Create('Chave Pix obrigatoria');
  Nome := Copy(PixTextoSeguro(Trim(ANome)), 1, 25);
  Cidade := Copy(PixTextoSeguro(Trim(ACidade)), 1, 15);
  if Nome = '' then raise Exception.Create('Nome do recebedor obrigatorio');
  if Cidade = '' then raise Exception.Create('Cidade do recebedor obrigatoria');
  if AValor < 0 then raise Exception.Create('Valor negativo');
  if AValor > 9999999999.99 then raise Exception.Create('Valor grande demais');

  TxId := ATxId;
  if TxId = '' then TxId := '***';
  if Length(TxId) > 25 then raise Exception.Create('TxId acima de 25 caracteres');

  Conta := Campo('00', GUI_PIX) + Campo('01', AChave);
  if ADescricao <> '' then
    Conta := Conta + Campo('02', ADescricao);
  if Length(Conta) > 99 then
    raise Exception.Create('Chave e descricao ultrapassam o tamanho do campo');

  Result := Campo('00', '01') + Campo('01', '11') + Campo('26', Conta) +
    Campo('52', '0000') + Campo('53', '986');
  if AValor > 0 then
    Result := Result + Campo('54', FormatarValor(AValor));
  Result := Result + Campo('58', 'BR') + Campo('59', Nome) +
    Campo('60', Cidade) + Campo('62', Campo('05', TxId));
  Sem := Result + '6304';
  Result := Sem + Crc16Ccitt(Sem);
end;

{ Le um campo TLV em APos; devolve False se estiver truncado. }
function LerTlv(const S: string; var APos: Integer; out AId, AVal: string): Boolean;
var
  N: Integer;
begin
  Result := False;
  AId := '';
  AVal := '';
  if APos + 3 > Length(S) then Exit;
  if not (S[APos] in ['0'..'9']) or not (S[APos + 1] in ['0'..'9']) then Exit;
  if not (S[APos + 2] in ['0'..'9']) or not (S[APos + 3] in ['0'..'9']) then Exit;
  AId := Copy(S, APos, 2);
  N := StrToInt(Copy(S, APos + 2, 2));
  if APos + 3 + N > Length(S) then Exit;
  AVal := Copy(S, APos + 4, N);
  APos := APos + 4 + N;
  Result := True;
end;

function ValidarPayloadPix(const APayload: string; out AInfo: TPixInfo;
  out AErro: string): Boolean;
var
  P, P2, Fim: Integer;
  Id, Val, SubId, SubVal, Crc: string;
  Tem00, Tem26, Tem53, Tem58, Tem59, Tem60, TemGui: Boolean;
  Fmt: TFormatSettings;
begin
  Result := False;
  AErro := '';
  AInfo.Chave := '';
  AInfo.Descricao := '';
  AInfo.Nome := '';
  AInfo.Cidade := '';
  AInfo.TxId := '';
  AInfo.Valor := 0;
  AInfo.TemValor := False;

  if Length(APayload) < 30 then begin AErro := 'Payload curto demais'; Exit; end;
  if Copy(APayload, 1, 6) <> '000201' then
  begin AErro := 'Inicio invalido (esperado 000201)'; Exit; end;
  if Copy(APayload, Length(APayload) - 7, 4) <> '6304' then
  begin AErro := 'Campo de CRC (63) ausente no fim'; Exit; end;
  Crc := Copy(APayload, Length(APayload) - 3, 4);
  if not SameText(Crc, Crc16Ccitt(Copy(APayload, 1, Length(APayload) - 4))) then
  begin AErro := 'CRC16 nao confere'; Exit; end;

  Tem00 := False; Tem26 := False; Tem53 := False; Tem58 := False;
  Tem59 := False; Tem60 := False; TemGui := False;
  Fmt := FormatSettings;
  Fmt.DecimalSeparator := '.';

  Fim := Length(APayload) - 8;  { tudo antes do campo 63 }
  P := 1;
  while P <= Fim do
  begin
    if not LerTlv(APayload, P, Id, Val) then
    begin AErro := 'Campo TLV truncado ou mal formado'; Exit; end;
    if Id = '00' then Tem00 := True
    else if Id = '26' then
    begin
      Tem26 := True;
      P2 := 1;
      while P2 <= Length(Val) do
      begin
        if not LerTlv(Val, P2, SubId, SubVal) then
        begin AErro := 'Conta (26) mal formada'; Exit; end;
        if SubId = '00' then TemGui := SameText(SubVal, GUI_PIX)
        else if SubId = '01' then AInfo.Chave := SubVal
        else if SubId = '02' then AInfo.Descricao := SubVal;
      end;
    end
    else if Id = '53' then
    begin
      Tem53 := True;
      if Val <> '986' then begin AErro := 'Moeda diferente de BRL'; Exit; end;
    end
    else if Id = '54' then
    begin
      if not TryStrToCurr(Val, AInfo.Valor, Fmt) or (AInfo.Valor <= 0) then
      begin AErro := 'Valor (54) invalido'; Exit; end;
      AInfo.TemValor := True;
    end
    else if Id = '58' then
    begin
      Tem58 := True;
      if Val <> 'BR' then begin AErro := 'Pais diferente de BR'; Exit; end;
    end
    else if Id = '59' then begin Tem59 := True; AInfo.Nome := Val; end
    else if Id = '60' then begin Tem60 := True; AInfo.Cidade := Val; end
    else if Id = '62' then
    begin
      P2 := 1;
      while P2 <= Length(Val) do
      begin
        if not LerTlv(Val, P2, SubId, SubVal) then
        begin AErro := 'Dados adicionais (62) mal formados'; Exit; end;
        if SubId = '05' then AInfo.TxId := SubVal;
      end;
    end;
  end;

  if not Tem00 then begin AErro := 'Falta o campo 00'; Exit; end;
  if not Tem26 then begin AErro := 'Falta a conta (26)'; Exit; end;
  if not TemGui then begin AErro := 'GUI br.gov.bcb.pix ausente'; Exit; end;
  if AInfo.Chave = '' then begin AErro := 'Chave Pix ausente'; Exit; end;
  if not Tem53 then begin AErro := 'Falta a moeda (53)'; Exit; end;
  if not Tem58 then begin AErro := 'Falta o pais (58)'; Exit; end;
  if not Tem59 then begin AErro := 'Falta o nome (59)'; Exit; end;
  if not Tem60 then begin AErro := 'Falta a cidade (60)'; Exit; end;
  Result := True;
end;

function ValidarPayloadPix(const APayload: string): Boolean;
var
  Info: TPixInfo;
  Erro: string;
begin
  Result := ValidarPayloadPix(APayload, Info, Erro);
end;

end.
