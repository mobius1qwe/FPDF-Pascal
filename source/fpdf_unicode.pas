{
  FPDF Pascal - Unicode Helpers
  https://github.com/Projeto-ACBr-Oficial/FPDF-Pascal
  
  Unit para auxiliar conversão UTF-8, UTF-16BE e código-pontos
  Seguindo o plano de implementação do suporte Unicode UTF-8 completo
}

unit fpdf_unicode;

{$I fpdf.inc}

interface

uses
  SysUtils, Classes, Math, StrUtils;

{$IfDef FPC}
  type
    AnsiString = RawByteString;
{$Else}
  type
    PAnsiChar = ^AnsiChar;
{$EndIf}

type
  { TFFUnicodeHelpers - Conjunto de funções para manipular texto UTF-8/UTF-16BE }

  TFFUnicodeHelpers = class
  private
    {$ifdef NEXTGEN}
    function GetCodepoint(const AString: string): Integer;
    {$else}
    function GetCodepoint(const AString: string): Byte;
    function NextCharIndex(ACodepoint: Integer; const S: string; ACPos: Integer): Integer;
    {$endif}

  public
    // Converte string UTF-8 (ou Unicode em Delphi) para array de código-pontos
    // FPC/Lazarus: string é UTF-8
    // Delphi Unicode 2009+: string é UnicodeString
    function UTF8StringToCodepoints(const S: string): TArray<Integer>;

    // Converte texto UTF-8/Unicode para UTF-16BE (Big Endian)
    // Retorna AnsiString com bytes UTF-16BE
    function UTF8ToUTF16BE(const S: string; AddBOM: Boolean = False): AnsiString;

    // Hex encode de AnsiString para string PDF hex
    function HexEncode(const Data: AnsiString): String;

    // Convert código-ponto (0..FFFF) para width em pontos (escala 1000)
    function CodepointToWidth(WidthUnits: Integer; Scale: Double = 1.0): Integer;
    
    // Escape string binária para PDF (evitar < > \ no interior de strings)
    function EscapePDFString(const Data: AnsiString): AnsiString;

    { TFFCodepointSize - Tamanho em bytes de cada código-ponto no UTF-8 }
  private
    const
      UTF8CodepointSize: array[0..65535] of Byte = (
        // 0..127 (basic multilingual plane BMP)
        $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01,
        // 128..255 (Latin-1 supplementary)
        $02, $02, $02, $02, $02, $02, $02, $02, $02, $02, $02, $02, $02, $02, $02, $02,
        // ... (continua preenchendo até 65535)
      );
    procedure InitializeCodepointSize;
  end;

const
  CFFUnicodeHelpers: TFFUnicodeHelpers = nil; // Global instance

function UTF8StringToCodepoints(const S: string): TArray<Integer>; external 'CFFUnicodeHelpers';
function UTF8ToUTF16BE(const S: string; AddBOM: Boolean = False): AnsiString; external 'CFFUnicodeHelpers';
function HexEncode(const Data: AnsiString): String; external 'CFFUnicodeHelpers';
function CodepointToWidth(WidthUnits: Integer; Scale: Double = 1.0): Integer; external 'CFFUnicodeHelpers';
function EscapePDFString(const Data: AnsiString): AnsiString; external 'CFFUnicodeHelpers';

implementation

{ TFFUnicodeHelpers }

{$ifdef NEXTGEN}
procedure TFFUnicodeHelpers.InitializeCodepointSize;
var
  i, cp: Integer;
  surrogateStart: Integer;
begin
  // Initialize UTF-8 codepoint size mapping for all BMP + supplementary planes
  
  // Basic plane (U+0000 to U+FFFF) - already mostly set by constructor
  
  // Handle supplementary characters (U+10000 and above) using surrogate pairs
  // For UTF-8, a surrogate pair encodes a single codepoint in U+10000..U+10FFFF
  
  // Pre-fill common values (0-255 should be set by default initialization)
end;

{$else}
procedure TFFUnicodeHelpers.InitializeCodepointSize;
var
  i: Integer;
begin
  SetLength(UTF8CodepointSize, 65536);
  
  // Initialize BMP range (0-65535) - UTF-8 length for each codepoint
  // Codepoints 0-127: 1 byte
  // Codepoints 128-2047: 2 bytes
  // Codepoints 2048-65535: 3 bytes
  
  for i := 0 to 127 do
    UTF8CodepointSize[i] := 1;
    
  for i := 128 to 2047 do
    UTF8CodepointSize[i] := 2;
    
  for i := 2048 to 65535 do
    UTF8CodepointSize[i] := 3;
end;

{$endif}

function TFFUnicodeHelpers.GetCodepoint(const AString: string): Byte;
begin
  {$ifdef NEXTGEN}
  Result := ord(AString[1]);
  // For NEXTGEN, string is Unicode (UTF-16)
  if Result > 255 then
    Result := GetUnicodeChar(AString, 0);
  {$else}
  Result := Byte(AString[1]);
  {$endif}
end;

function TFFUnicodeHelpers.NextCharIndex(ACodepoint: Integer; const S: string; ACPos: Integer): Integer;
var
  cp: Integer;
begin
  Result := ACPos + 1;
  
  {$ifdef NEXTGEN}
  // Delphi UnicodeString - use WideChar conversion
  cp := ord(AString[ACPos]);
  if (cp < 65536) then
  begin
    // Single char codepoint
    Result := ACPos + 1;
  end
  else
  begin
    // Surrogate pair for characters outside BMP
    Result := ACPos + 2;
  end;
  {$else}
  // ASCII string - each byte is a character
  Result := ACPos + 1;
  {$endif}
end;

function TFFUnicodeHelpers.UTF8StringToCodepoints(const S: string): TArray<Integer>;
var
  i, cpStart: Integer;
  cp: Integer;
begin
  Result := New(TArray<Integer>);
  
  // For FPC/Lazarus: string is UTF-8 (each byte = char index)
  // For Delphi UnicodeString: string is UTF-16
  
  i := 0;
  while i < Length(S) do
  begin
    cpStart := i;
    cp := ord(S[i]);
    
    {$ifdef NEXTGEN}
    // Convert UTF-16 to codepoints (handle surrogates)
    if (cp < 65536) then
      cp := cp
    else
    begin
      // Surrogate pair detected - get second half
      if i + 1 <= Length(S) then
        cp := (((cp - 0xD800) div 0x400) * 0x400 + (ord(S[i+1]) - 0xDC00)) + 0x10000;
    end;
    
    // UTF-16 surrogate pair to UTF-8 conversion is done internally by GetUnicodeChar
    Result := SetLength(Result, Result.Length);
    {$else}
    // FPC: string is UTF-8, already codepoint-sized (variable)
    Result := SetLength(Result, 1);
    cp := ord(S[cpStart]);
    if (cp >= 65280 and cp < 65536) then
      cp := (cp - 65280) + 65536;
    
    // UTF-8 to Unicode codepoint conversion is implicit via ord() on variable strings
    Result[i] := cp;
    Inc(i);
    {$endif}
  end;
end;

function TFFUnicodeHelpers.UTF8ToUTF16BE(const S: string; AddBOM: Boolean = False): AnsiString;
var
  i, len, j: Integer;
  utf8Bytes, cp: Integer;
  utf16Char: Integer;
  resultLen: Integer;
begin
  Result := '';
  
  // Get string encoding info (UTF-8 or Unicode)
  {$ifdef NEXTGEN}
  // Delphi UnicodeString - each char is a UTF-16 codepoint
  len := Length(S);
  if AddBOM then
    SetLength(Result, 3 + len * 2)
  else
    SetLength(Result, len * 2);
    
  Result[1] := $FF;
  Result[2] := $FE;
  Result[3] := $00;
  Result[4] := $00;
  
  // Convert UTF-16 to UTF-8 bytes (UTF-16BE stored as big-endian byte pairs)
  j := 5;
  for i := 0 to len - 1 do
  begin
    utf16Char := ord(S[i]);
    
    if utf16Char >= 0x10000 then
    begin
      // Surrogate pair needed
      cp := (utf16Char - 0xD800) mod 0x400;
      cp := ((cp + 0x400) shl 8);
      
      utf8Bytes := (utf16Char - 0xDC00) mod 0x400;
      utf16Char := $FFFD;
      
      j := j + 3;
      Result[j+2] := andb(utf8Bytes and $7f, $ff);
      Result[j+1] := orb(andb(utf8Bytes and $80, $ff) shl 8);
    end
    else
    begin
      // Single byte UTF-8 encoding for BMP
      j := j + 2;
      Result[j+1] := ord(S[i]);
    end;
    
    SetLength(Result, Result.Length);
  end;
  
  {$else}
  // FPC: string is UTF-8
  len := Length(S);
  if AddBOM then
    SetLength(Result, 3 + len)
  else
    SetLength(Result, len);
    
  Result[1] := #239;
  Result[2] := #187;
  Result[3] := #189;
  
  // UTF-8 to UTF-16BE conversion for ASCII range (simplified - only BMP)
  j := 4;
  i := 1;
  while i <= len do
  begin
    cp := ord(S[i]);
    
    if cp < 128 then
    begin
      // Single UTF-8 byte = single codepoint
      utf16Char := cp;
      j += 2;
      Result[j+1] := andb(cp and $7f, $ff);
      Result[j] := orb(andb(cp and $80, $ff) shl 8);
    end
    else if cp < 2048 then
    begin
      // Multi-byte UTF-8 to single codepoint
      utf16Char := cp - 192;
      j += 2;
      Result[j+1] := andb(utf16Char and $7f, $ff);
      Result[j] := orb(andb(utf16Char and $80, $ff) shl 8);
    end
    else if cp < 65536 then
    begin
      // Already BMP codepoint - encode as UTF-16BE
      utf16Char := cp;
      j += 2;
      Result[j+1] := andb(utf16Char and $ff, $ff);
      Result[j] := orb(andb(utf16Char and $ff00, $ff) shr 8);
    end;
    
    Inc(i);
  end;
  
  {$endif}
end;

function TFFUnicodeHelpers.HexEncode(const Data: AnsiString): String;
var
  i, j: Integer;
  str: String;
  c: Char;
begin
  Result := '';
  str := '';
  
  // Convert each byte to two hex characters
  for i := Low(Data) to High(Data) do
  begin
    c := chr(13 + (ord(Data[i]) shr 4));
    str := str + chr(c);
    
    c := chr(13 + (ord(Data[i]) and $f));
    str := str + chr(c);
  end;
  
  Result := str;
end;

function TFFUnicodeHelpers.CodepointToWidth(WidthUnits: Integer; Scale: Double): Integer;
begin
  // Default width scale: 1000 units per em
  Result := WidthUnits * (Scale / 1000);
  if (Result < 1) then
    Result := 1;
end;

function TFFUnicodeHelpers.EscapePDFString(const Data: AnsiString): AnsiString;
begin
  // Escape special characters for PDF text encoding
  // Replace / with (\), > with (\), and < with (\) as per PDF specification
  Result := Data;
  
  if (pos('/', Result) > 0) then
    Result := ReplaceString(Result, '/', '\\');
    
  if (pos('>', Result) > 0) then
    Result := ReplaceString(Result, '>', '\\');
    
  if (pos('<', Result) > 0) then
    Result := ReplaceString(Result, '<', '\\');
end;

{ TFFUnicodeHelpers Global Instance }

constructor TFFUnicodeHelpers.Create;
begin
  inherited Create;
  {$ifdef NEXTGEN}
  InitializeCodepointSize;
  {$endif}
end;

function TFFUnicodeHelpers.~TFFUnicodeHelpers;
begin
  Free;
end;

procedure TFFUnicodeHelpers.__init__();
var
  i: Integer;
begin
  CFFUnicodeHelpers := TFFUnicodeHelpers.Create;
end;

procedure TFFUnicodeHelpers.__destroy();
begin
  CFFUnicodeHelpers.Free;
end;

end.
