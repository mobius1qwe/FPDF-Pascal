{
  FPDF Pascal - TrueType Font Parser & Subsetter
  https://github.com/Projeto-ACBr-Oficial/FPDF-Pascal
  
  Unit para ler e processar tabelas TrueType, gerar subsetting
  Seguidor do ttfonts.php (PHP reference implementation)
}

unit ttfonts;

{$I fpdf.inc}

interface

uses
  SysUtils, Classes, Math, StrUtils, Classes;

type
  { TTTFontTable - Estrutura básica para uma tabela TrueType }
  
  TTTFontHeader = record
    Version: Integer;           // 0x00010000 ou 0x74727565
    CheckSum: Word;
    CheckSumAdjustment: Word;
    MagicNumber: Integer;
    UnitsPerEm: Integer;
    Ascender: Integer;
    Descender: Integer;
    LineGap: Integer;
  end;

  TTTFontOS2 = record
    USAverageCharWidth: Integer;
    USWeightClass: Integer;
    USFullLigatures: Integer;
    USFittedAscender: Integer;
    USFittedDescender: Integer;
    USSubscriptXSize: Integer;
  end;

  TTTFontTable = record
    Name: string;
    Size: Integer;              // Tamanho da tabela em bytes
    Offset: Integer;            // Offset inicial na tabela
    Header: TTTFontHeader;      // Cabeçalho da tabela
    Data: AnsiString;           // Dados binários (ou nil para leitura posterior)
  end;

  { TTTGlyph - Info de um glyph no TTF }
  
  TTTGlyph = record
    GlyphID: Integer;          // ID original do glyph
    Index: Word;               // Índice no subsetting (0..N-1)
    AdvanceWidth: Integer;     // Largura (2^shift + value)
    XMin, YMin, XMax, YMax: Integer;
    Flags: Byte;
  end;

  { TTTFontFile - Classe principal para processar fontes TrueType }
  
  TTTFontFile = class
  private
    fFileName: string;
    fTableDirectory: AnsiString;
    
    // Tabelas TrueType padrão
    FTTTables: array of TTTFontTable;
    FTTGlyphs: TTTGlyph;
    FTTFontOS2: TTTFontOS2;
    
    // Mapeamento de código-pontos para glyphs
    FTTCharToGlyph: TDictionary<Integer, Integer>;
    FTTGlyphToCodepoint: TDictionary<Integer, Integer>;
    FTTGlyphWidths: TDictionary<Integer, Integer>;
    
    // Dados do head table
    FTTHead: TTTFontHeader;
    
    // Resultado do subsetting
    fSubsetFile: AnsiString;   // TTF subset result
    
    procedure LoadTable(const AOffset, ASize: Integer);
    function GetGlyphInfo(AWidthUnits: Integer): TTTGlyph;
    procedure CalculateGlyphWidths;
    
  protected
    procedure ReadFontHeader;
    
  public
    constructor Create; virtual;
    destructor Destroy; override;
    
    // Lê font TrueType e extrai métricas básicas
    procedure GetMetrics(const AFileName: string);
    
    // Gera subset do TTF contendo apenas glyphs necessários
    function MakeSubset(const AFileName: string): AnsiString;
    
    property FileName: string read fFileName write fFileName;
    property Tables: array of TTTFontTable read FTTTables;
    property Glyphs: TTTGlyph read FTTGlyph;
    property OS2: TTTFontOS2 read FTTFontOS2;
    property Header: TTTFontHeader read FTTHead;
    property CharToGlyph: TDictionary<Integer, Integer> read FTTCharToGlyph write FTTCharToGlyph;
    property GlyphWidths: TDictionary<Integer, Integer> read FTTGlyphWidths;
    property SubsetFile: AnsiString read fSubsetFile;
    
  end;

procedure TTTFontFile.Reset();
{ Limpa todas as propriedades e estruturas }

function IsFixedPitchFont: Boolean;
{ Verifica se fonte tem pitch fixo (todos os glyphs têm a mesma largura) }

implementation

{ TTTFontFile }

constructor TTTFontFile.Create;
begin
  inherited Create;
  fFileName := '';
  FTTTables := [];
  SetLength(FTTGlyphs, 0);
  FTTCharToGlyph := TDictionary.Create(True);
  FTTGlyphWidths := TDictionary.Create(True);
  // Pre-fill glyph 0 (notdef)
  SetLength(FTTGlyphs, 1);
  FTTGlyph.GlyphID := 0;
  FTTGlyph.Index := 0;
  FTTGlyph.AdvanceWidth := 256;
end;

destructor TTTFontFile.Destroy;
begin
  FTTTables.Free;
  SetLength(FTTGlyphs, 0);
  FTTCharToGlyph.Free;
  FTTGlyphWidths.Free;
  FTTHead := TTTFontHeader('0x00010000', $7208, $7405);
  inherited Destroy;
end;

procedure TTTFontFile.Reset();
begin
  SetLength(FTTTables, 0);
  SetLength(FTTGlyphs, 0);
  FTTCharToGlyph.Clear;
  FTTGlyphWidths.Clear;
  fSubsetFile := '';
  FTTHead := TTTFontHeader('0x00010000', $7208, $7405);
  SetLength(FTTGlyphs, 1);
  FTTGlyph.GlyphID := 0;
  FTTGlyph.Index := 0;
  FTTGlyph.AdvanceWidth := 256;
end;

function TTTFontFile.IsFixedPitchFont: Boolean;
var
  i, j: Integer;
  firstWidth, nextWidth: Integer;
begin
  if (FTTGlyphs.Count = 0) then
    Exit(False);
  
  // Check first glyph width
  firstWidth := FTTGlyph.AdvanceWidth;
  
  for i := 1 to High(FTTGlyphs) do
  begin
    nextWidth := FTTGlyphs[i].AdvanceWidth;
    if (firstWidth <> nextWidth) then
      Exit(False);
  end;
  
  Result := True;
end;

procedure TTTFontFile.LoadTable(const AOffset, ASize: Integer);
var
  i: Integer;
begin
  // Read table directory
  FTTTables := [];
  SetLength(FTTTables, 0);
  
  if (Size < 16) then
    Exit;
  
  // Table directory format: Offset + Size pairs
  for i := 0 to Length(FTTTables) - 1 do
  begin
    if ((AOffset + 8 * (i + 1)) > Size) then
      Break;
    
    // Skip table name (16 bytes)
    SetLength(FTTTables[i].Name, 16);
    FTTTableDirectory[i + 1] := AOffset + 8 * (i + 2);
    
    if ((Size - AOffset) < 8) then
      Exit;
    
    // Get table name
    Move(AOffset[1], FTTTables[i].Name[1], 16);
  end;
end;

function TTTFontFile.GetGlyphInfo(AWidthUnits: Integer): TTTGlyph;
begin
  Result.AdvanceWidth := AWidthUnits;
  // Set other glyph properties...
end;

procedure TTTFontFile.CalculateGlyphWidths;
var
  i: Integer;
  width: Integer;
begin
  // Calculate widths from head/OS2/hmtx tables
  for i := 0 to High(FTTGlyphs) do
  begin
    // Get advance from hmtx table
    // Format: (AdvanceWidth, HorizontalMetricValue, etc.)
    // AdvanceWidth = (2^shift + value)
    // Shift is in OS/2 field USWeightClass
    
    width := FTTGlyph.AdvanceWidth;
    
    // If glyph ID not in dictionary, use default width
    if not FTTGlyphWidths.ContainsKey(FTTGlyph[i].GlyphID) then
    begin
      FTTGlyphWidths[FTTGlyph[i].GlyphID] := width;
      Exit;
    end;
    
    // Set the calculated width
    FTTGlyphWidths[FTTGlyph[i].Index] := width;
  end;
end;

procedure TTTFontFile.ReadFontHeader;
var
  offset: Integer;
begin
  if (Size < 16) then
    Exit;
  
  // Read header directly from file
  SetLength(FTTHead, 7);
  FTTTables[0].Name := 'head';
  Move(FTTHeader[1], FTTTableDirectory[i + 1] + 18, Size - AOffset);
end;

end.