unit CepHttpDelphi;

{ Implementacao de IHttpGet com System.Net.HttpClient (Delphi XE8+).
  So compila no Delphi; em Free Pascal a unit fica vazia. Use sua propria
  implementacao de IHttpGet (Indy, fphttpclient...) se preferir. }

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

{$IFNDEF FPC}
uses
  Cep;

type
  TNetHttpGet = class(TInterfacedObject, IHttpGet)
  public
    function Get(const AUrl: string): string;
  end;
{$ENDIF}

implementation

{$IFNDEF FPC}
uses
  System.SysUtils, System.Net.HttpClient;

function TNetHttpGet.Get(const AUrl: string): string;
var
  Cli: THTTPClient;
  Resp: IHTTPResponse;
begin
  Cli := THTTPClient.Create;
  try
    Cli.ConnectionTimeout := 5000;
    Cli.ResponseTimeout := 10000;
    Resp := Cli.Get(AUrl);
    if Resp.StatusCode <> 200 then
      raise ECepFalha.CreateFmt('HTTP %d', [Resp.StatusCode]);
    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    Cli.Free;
  end;
end;
{$ENDIF}

end.
