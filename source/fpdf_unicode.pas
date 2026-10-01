{
  FPDF Pascal - Unicode Helpers
  https://github.com/Projeto-ACBr-Oficial/FPDF-Pascal

  Funcoes puras para converter texto entre UTF-8 / UTF-16 (string nativa),
  codepoints Unicode e UTF-16BE (o que o PDF usa em fontes Type0/Identity-H).

  - FPC/Lazarus: "string" e UTF-8 (AnsiString) em todas as plataformas.
  - Delphi Unicode (2009+): "string" e UTF-16.
  - Delphi antigo (pre-Unicode): "string" e tratada como UTF-8.

  Sem dependencia de WinAPI, iconv ou codepage do sistema: o resultado e o mesmo
  em Windows, Linux, macOS e demais targets do Lazarus.
}

unit fpdf_unicode;

{$I fpdf.inc}

interface

uses
  SysUtils;

type
  TUnicodeCodepoints = array of Cardinal;

const
  UNICODE_REPLACEMENT = $FFFD;

// "S" -> codepoints Unicode. Sequencias invalidas viram U+FFFD.
function UTF8StringToCodepoints(const S: string): TUnicodeCodepoints;

// codepoints -> bytes UTF-16BE (pares substitutos pra U+10000..U+10FFFF).
function CodepointsToUTF16BE(const ACodepoints: TUnicodeCodepoints;
  AddBOM: Boolean = False): AnsiString;

// "S" -> bytes UTF-16BE (opcionalmente com BOM FE FF).
function UTF8ToUTF16BE(const S: string; AddBOM: Boolean = False): AnsiString;

// bytes -> string hexadecimal maiuscula ("<...>" fica por conta de quem chama).
function HexEncode(const Data: AnsiString): string;

// Escapa \ ( ) e CR/LF pra uso em string literal PDF "(...)".
function EscapePDFString(const Data: AnsiString): AnsiString;

// Largura em unidades da fonte -> escala PDF de 1000 unidades por em.
function CodepointToWidth(AWidthUnits, AUnitsPerEm: Integer): Integer;

implementation

procedure AddCodepoint(var A: TUnicodeCodepoints; var N: Integer; C: Cardinal);
begin
  if N >= Length(A) then
    SetLength(A, Length(A) + 16 + Length(A) div 2);
  A[N] := C;
  Inc(N);
end;

function UTF8StringToCodepoints(const S: string): TUnicodeCodepoints;
var
  n, i, len, cnt, j: Integer;
  b: Byte;
  cp, minCp: Cardinal;
  ok: Boolean;
{$IfDef UNICODE}
  c, c2: Cardinal;
{$EndIf}
begin
  Result := nil;
  n := 0;
  len := Length(S);
  SetLength(Result, len);

  {$IfDef UNICODE}
  // string em UTF-16 (Delphi 2009+)
  i := 1;
  while i <= len do
  begin
    c := Ord(S[i]);
    Inc(i);
    if (c >= $D800) and (c <= $DBFF) then
    begin
      if (i <= len) and (Ord(S[i]) >= $DC00) and (Ord(S[i]) <= $DFFF) then
      begin
        c2 := Ord(S[i]);
        Inc(i);
        c := $10000 + ((c - $D800) shl 10) + (c2 - $DC00);
      end
      else
        c := UNICODE_REPLACEMENT;
    end
    else if (c >= $DC00) and (c <= $DFFF) then
      c := UNICODE_REPLACEMENT;
    AddCodepoint(Result, n, c);
  end;
  {$Else}
  // string em UTF-8 (FPC e Delphi pre-Unicode)
  i := 1;
  while i <= len do
  begin
    b := Ord(S[i]);
    if b < $80 then
    begin
      AddCodepoint(Result, n, b);
      Inc(i);
      Continue;
    end;

    cnt := 0;
    cp := 0;
    minCp := 0;
    if (b and $E0) = $C0 then
    begin
      cnt := 1;
      cp := b and $1F;
      minCp := $80;
    end
    else if (b and $F0) = $E0 then
    begin
      cnt := 2;
      cp := b and $0F;
      minCp := $800;
    end
    else if (b and $F8) = $F0 then
    begin
      cnt := 3;
      cp := b and $07;
      minCp := $10000;
    end;

    ok := (cnt > 0) and (i + cnt <= len);
    if ok then
      for j := 1 to cnt do
      begin
        b := Ord(S[i + j]);
        if (b and $C0) <> $80 then
        begin
          ok := False;
          Break;
        end;
        cp := (cp shl 6) or (b and $3F);
      end;

    if ok and ((cp < minCp) or (cp > $10FFFF) or ((cp >= $D800) and (cp <= $DFFF))) then
      ok := False;

    if ok then
    begin
      AddCodepoint(Result, n, cp);
      Inc(i, cnt + 1);
    end
    else
    begin
      AddCodepoint(Result, n, UNICODE_REPLACEMENT);
      Inc(i);
    end;
  end;
  {$EndIf}

  SetLength(Result, n);
end;

function CodepointsToUTF16BE(const ACodepoints: TUnicodeCodepoints;
  AddBOM: Boolean): AnsiString;
var
  i, p: Integer;
  c: Cardinal;

  procedure PutWord(W: Cardinal);
  begin
    Result[p] := AnsiChar(W shr 8);
    Result[p + 1] := AnsiChar(W and $FF);
    Inc(p, 2);
  end;

begin
  SetLength(Result, 2 + Length(ACodepoints) * 4);
  p := 1;
  if AddBOM then
    PutWord($FEFF);

  for i := 0 to High(ACodepoints) do
  begin
    c := ACodepoints[i];
    if (c > $10FFFF) or ((c >= $D800) and (c <= $DFFF)) then
      c := UNICODE_REPLACEMENT;

    if c >= $10000 then
    begin
      Dec(c, $10000);
      PutWord($D800 + (c shr 10));
      PutWord($DC00 + (c and $3FF));
    end
    else
      PutWord(c);
  end;

  SetLength(Result, p - 1);
end;

function UTF8ToUTF16BE(const S: string; AddBOM: Boolean): AnsiString;
begin
  Result := CodepointsToUTF16BE(UTF8StringToCodepoints(S), AddBOM);
end;

function HexEncode(const Data: AnsiString): string;
const
  Hex: array[0..15] of Char = '0123456789ABCDEF';
var
  i: Integer;
  b: Byte;
begin
  SetLength(Result, Length(Data) * 2);
  for i := 1 to Length(Data) do
  begin
    b := Ord(Data[i]);
    Result[i * 2 - 1] := Hex[b shr 4];
    Result[i * 2] := Hex[b and $F];
  end;
end;

function EscapePDFString(const Data: AnsiString): AnsiString;
var
  i, n: Integer;
  c: AnsiChar;
begin
  SetLength(Result, Length(Data) * 2);
  n := 0;
  for i := 1 to Length(Data) do
  begin
    c := Data[i];
    case c of
      '\', '(', ')':
        begin
          Inc(n);
          Result[n] := '\';
          Inc(n);
          Result[n] := c;
        end;
      #13:
        begin
          Inc(n);
          Result[n] := '\';
          Inc(n);
          Result[n] := 'r';
        end;
      #10:
        begin
          Inc(n);
          Result[n] := '\';
          Inc(n);
          Result[n] := 'n';
        end;
    else
      Inc(n);
      Result[n] := c;
    end;
  end;
  SetLength(Result, n);
end;

function CodepointToWidth(AWidthUnits, AUnitsPerEm: Integer): Integer;
begin
  if AUnitsPerEm <= 0 then
    AUnitsPerEm := 1000;
  Result := Round(AWidthUnits * 1000 / AUnitsPerEm);
end;

end.
