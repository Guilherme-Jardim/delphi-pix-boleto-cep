unit Cep;

{ Consulta de CEP por interface (ICepProvider).
  - TViaCepProvider: usa o ViaCEP por cima de uma camada HTTP injetavel (IHttpGet).
  - TCepFalso: provider em memoria, para testes e demos.
  O JSON e lido com System.JSON (Delphi) ou fpjson (Free Pascal). }

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils;

type
  ECepInvalido = class(Exception);
  ECepFalha = class(Exception);

  TEndereco = record
    Cep: string;          { 8 digitos }
    Logradouro: string;
    Complemento: string;
    Bairro: string;
    Localidade: string;
    UF: string;
    Ibge: string;
  end;

  { Camada fina de HTTP: so precisa saber fazer GET e devolver o corpo. }
  IHttpGet = interface
    ['{6F0B1D7A-3C52-4E0B-9A41-52B7C1D0A1E3}']
    function Get(const AUrl: string): string;
  end;

  ICepProvider = interface
    ['{B2A8E4C1-7D3F-4A65-8E19-0C4F6A9D2B77}']
    { True quando o CEP existe. Levanta ECepInvalido para CEP mal formado
      e ECepFalha para erro de rede ou resposta ilegivel. }
    function Consultar(const ACep: string; out AEndereco: TEndereco): Boolean;
  end;

  TCepFalso = class(TInterfacedObject, ICepProvider)
  private
    FCeps: array of TEndereco;
    FConsultas: Integer;
  public
    procedure Adicionar(const AEndereco: TEndereco);
    function Consultar(const ACep: string; out AEndereco: TEndereco): Boolean;
    property Consultas: Integer read FConsultas;
  end;

  TViaCepProvider = class(TInterfacedObject, ICepProvider)
  private
    FHttp: IHttpGet;
    FBaseUrl: string;
  public
    constructor Create(const AHttp: IHttpGet;
      const ABaseUrl: string = 'https://viacep.com.br/ws/');
    function Consultar(const ACep: string; out AEndereco: TEndereco): Boolean;
  end;

function CepNormalizar(const ACep: string): string;
function CepValido(const ACep: string): Boolean;
function CepFormatar(const ACep: string): string;
{ Interpreta a resposta JSON do ViaCEP. False quando traz "erro". }
function ParseViaCep(const AJson: string; out AEndereco: TEndereco): Boolean;

implementation

uses
{$IFDEF FPC}
  fpjson, jsonparser;
{$ELSE}
  System.JSON;
{$ENDIF}

function CepNormalizar(const ACep: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(ACep) do
    if ACep[I] in ['0'..'9'] then
      Result := Result + ACep[I];
end;

function CepValido(const ACep: string): Boolean;
var
  N: string;
  I: Integer;
  Todos: Boolean;
begin
  N := CepNormalizar(ACep);
  Result := Length(N) = 8;
  if Result then
  begin
    { 00000000 e sequencias iguais nao existem }
    Todos := True;
    for I := 2 to 8 do
      if N[I] <> N[1] then Todos := False;
    Result := not Todos;
  end;
end;

function CepFormatar(const ACep: string): string;
var
  N: string;
begin
  N := CepNormalizar(ACep);
  if Length(N) <> 8 then
    raise ECepInvalido.Create('CEP deve ter 8 digitos: ' + ACep);
  Result := Copy(N, 1, 5) + '-' + Copy(N, 6, 3);
end;

{ ---- JSON ---- }

{$IFDEF FPC}
function JsonStr(AObj: TJSONObject; const ANome: string): string;
var
  D: TJSONData;
begin
  Result := '';
  D := AObj.Find(ANome);
  if (D <> nil) and not D.IsNull then
    Result := D.AsString;
end;
{$ELSE}
function JsonStr(AObj: TJSONObject; const ANome: string): string;
var
  V: TJSONValue;
begin
  Result := '';
  V := AObj.GetValue(ANome);
  if (V <> nil) and not (V is TJSONNull) then
    Result := V.Value;
end;
{$ENDIF}

function ParseViaCep(const AJson: string; out AEndereco: TEndereco): Boolean;
var
  Obj: TJSONObject;
{$IFDEF FPC}
  Dado: TJSONData;
{$ELSE}
  Dado: TJSONValue;
{$ENDIF}
begin
  AEndereco.Cep := '';
  AEndereco.Logradouro := '';
  AEndereco.Complemento := '';
  AEndereco.Bairro := '';
  AEndereco.Localidade := '';
  AEndereco.UF := '';
  AEndereco.Ibge := '';
  Result := False;

  Dado := nil;
  try
    try
{$IFDEF FPC}
      Dado := GetJSON(AJson);
{$ELSE}
      Dado := TJSONObject.ParseJSONValue(AJson);
{$ENDIF}
    except
      raise ECepFalha.Create('Resposta nao e um JSON valido');
    end;
    if not (Dado is TJSONObject) then
      raise ECepFalha.Create('Resposta nao e um objeto JSON');
    Obj := TJSONObject(Dado);

    if SameText(JsonStr(Obj, 'erro'), 'true') then Exit;

    AEndereco.Cep := CepNormalizar(JsonStr(Obj, 'cep'));
    AEndereco.Logradouro := JsonStr(Obj, 'logradouro');
    AEndereco.Complemento := JsonStr(Obj, 'complemento');
    AEndereco.Bairro := JsonStr(Obj, 'bairro');
    AEndereco.Localidade := JsonStr(Obj, 'localidade');
    AEndereco.UF := JsonStr(Obj, 'uf');
    AEndereco.Ibge := JsonStr(Obj, 'ibge');
    Result := AEndereco.Cep <> '';
  finally
    Dado.Free;
  end;
end;

{ ---- TCepFalso ---- }

procedure TCepFalso.Adicionar(const AEndereco: TEndereco);
begin
  SetLength(FCeps, Length(FCeps) + 1);
  FCeps[High(FCeps)] := AEndereco;
  FCeps[High(FCeps)].Cep := CepNormalizar(AEndereco.Cep);
end;

function TCepFalso.Consultar(const ACep: string; out AEndereco: TEndereco): Boolean;
var
  N: string;
  I: Integer;
begin
  Inc(FConsultas);
  if not CepValido(ACep) then
    raise ECepInvalido.Create('CEP invalido: ' + ACep);
  N := CepNormalizar(ACep);
  for I := 0 to High(FCeps) do
    if FCeps[I].Cep = N then
    begin
      AEndereco := FCeps[I];
      Result := True;
      Exit;
    end;
  AEndereco.Cep := '';
  AEndereco.Logradouro := '';
  AEndereco.Complemento := '';
  AEndereco.Bairro := '';
  AEndereco.Localidade := '';
  AEndereco.UF := '';
  AEndereco.Ibge := '';
  Result := False;
end;

{ ---- TViaCepProvider ---- }

constructor TViaCepProvider.Create(const AHttp: IHttpGet; const ABaseUrl: string);
begin
  inherited Create;
  FHttp := AHttp;
  FBaseUrl := ABaseUrl;
  if (FBaseUrl <> '') and (FBaseUrl[Length(FBaseUrl)] <> '/') then
    FBaseUrl := FBaseUrl + '/';
end;

function TViaCepProvider.Consultar(const ACep: string; out AEndereco: TEndereco): Boolean;
var
  Corpo: string;
begin
  if not CepValido(ACep) then
    raise ECepInvalido.Create('CEP invalido: ' + ACep);
  try
    Corpo := FHttp.Get(FBaseUrl + CepNormalizar(ACep) + '/json/');
  except
    on E: ECepFalha do raise;
    on E: Exception do
      raise ECepFalha.Create('Falha ao consultar o ViaCEP: ' + E.Message);
  end;
  Result := ParseViaCep(Corpo, AEndereco);
end;

end.
