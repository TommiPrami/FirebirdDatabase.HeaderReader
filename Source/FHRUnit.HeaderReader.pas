unit FHRUnit.HeaderReader;

interface

uses
  System.Classes, FHRUnit.HeaderReader.Types;

type
  TFirebirdODSHeaderReader = class(TObject)
  strict private
    FODSHeaderInfo: TFireBirdODSHeaderInfo;
    function ReadODSStaticHeader(const AStream: TStream; var AODSHeader: TODSStaticHeader): Boolean;
    function DecodeODSStaticHeaderMajorVersion(const AODSStaticHeader: TODSStaticHeader): Boolean;
    function ReadODSVariableHeader(const AStream: TStream): Boolean;
    function ReadODS11VariableHeader(const AStream: TStream): Boolean;
    function ReadODS12VariableHeader(const AStream: TStream): Boolean;
    function ReadODS13VariableHeader(const AStream: TStream): Boolean;
    function ReadODS14VariableHeader(const AStream: TStream): Boolean;
  public
    constructor Create;
    destructor Destroy; override;

    function ReadHeader(const AFirebirdDatabaseFileName: string): Boolean;
    property ODSHeaderInfo: TFireBirdODSHeaderInfo read FODSHeaderInfo;
  end;

implementation

uses
  System.SysUTils;

function TFirebirdODSHeaderReader.DecodeODSStaticHeaderMajorVersion(const AODSStaticHeader: TODSStaticHeader): Boolean;
const
  ODS_FIREBIRD_FLAG = $8000; // is it Firebird or InterBase
begin
  FODSHeaderInfo.PageSize := AODSStaticHeader.PageSize;

  Result := (AODSStaticHeader.EncodedODSMajorVersion and ODS_FIREBIRD_FLAG) <> 0;
  FODSHeaderInfo.IsFirebirdDatabase := Result;

  if not FODSHeaderInfo.IsFirebirdDatabase then
    Exit;

  FODSHeaderInfo.MajorVersion := AODSStaticHeader.EncodedODSMajorVersion and (not ODS_FIREBIRD_FLAG);
end;

function TFirebirdODSHeaderReader.ReadODSStaticHeader(const AStream: TStream; var AODSHeader: TODSStaticHeader): Boolean;
var
  LDataRead: Integer;
begin
  Result := False;
  AODSHeader.Clear;

  LDataRead := AStream.Read(AODSHeader, SizeOf(TODSStaticHeader));

  if LDataRead <> SizeOf(TODSStaticHeader) then
    AODSHeader.Clear
  else
    Result := True;

  Assert(AStream.Position = SizeOf(TODSStaticHeader), 'Stream at wrong position');
end;

function TFirebirdODSHeaderReader.ReadODS11VariableHeader(const AStream: TStream): Boolean;
var
  LDataRead: Integer;
  LODS11VariableHeader: TODS11VariabeHeader;
begin
  Result := False;
  LODS11VariableHeader.Clear;

  LDataRead := AStream.Read(LODS11VariableHeader, SizeOf(TODS11VariabeHeader));

  if LDataRead = SizeOf(TODS11VariabeHeader) then
  begin
    FODSHeaderInfo.MinorVersion := LODS11VariableHeader.ODSMinorVersion;
    Result := True;
  end;
end;

function TFirebirdODSHeaderReader.ReadODS12VariableHeader(const AStream: TStream): Boolean;
var
  LDataRead: Integer;
  LODS12VariableHeader: TODS12VariabeHeader;
begin
  Result := False;
  LODS12VariableHeader.Clear;

  LDataRead := AStream.Read(LODS12VariableHeader, SizeOf(TODS12VariabeHeader));

  if LDataRead = SizeOf(TODS12VariabeHeader) then
  begin
    FODSHeaderInfo.MinorVersion := LODS12VariableHeader.ODSMinorVersion;
    Result := True;
  end;
end;

function TFirebirdODSHeaderReader.ReadODS13VariableHeader(const AStream: TStream): Boolean;
var
  LDataRead: Integer;
  LODS13VariableHeader: TODS13VariabeHeader;
begin
  Result := False;
  LODS13VariableHeader.Clear;

  LDataRead := AStream.Read(LODS13VariableHeader, SizeOf(TODS13VariabeHeader));

  if LDataRead = SizeOf(TODS13VariabeHeader) then
  begin
    FODSHeaderInfo.MinorVersion := LODS13VariableHeader.ODSMinorVersion;
    Result := True;
  end;
end;

function TFirebirdODSHeaderReader.ReadODS14VariableHeader(const AStream: TStream): Boolean;
var
  LDataRead: Integer;
  LODS14VariableHeader: TODS14VariabeHeader;
begin
  Result := False;
  LODS14VariableHeader.Clear;

  LDataRead := AStream.Read(LODS14VariableHeader, SizeOf(TODS14VariabeHeader));

  if LDataRead <> SizeOf(TODS14VariabeHeader) then
    LODS14VariableHeader.Clear
  else
  begin
    FODSHeaderInfo.MinorVersion := LODS14VariableHeader.ODSMinorVersion;
    Result := True;
  end;
end;

function TFirebirdODSHeaderReader.ReadODSVariableHeader(const AStream: TStream): Boolean;
begin
  Result := False;
  FODSHeaderInfo.MinorVersion := 0;

  case FODSHeaderInfo.MajorVersion of
    11: Result := ReadODS11VariableHeader(AStream);
    12: Result := ReadODS12VariableHeader(AStream);
    13: Result := ReadODS13VariableHeader(AStream);
    14: Result := ReadODS14VariableHeader(AStream);
  end;
end;


{ TFirebirdODSHeaderReader }

constructor TFirebirdODSHeaderReader.Create;
begin
  inherited Create;

  FODSHeaderInfo := TFireBirdODSHeaderInfo.Create;
end;

destructor TFirebirdODSHeaderReader.Destroy;
begin
  FODSHeaderInfo.Free;

  inherited Destroy;;
end;

function TFirebirdODSHeaderReader.ReadHeader(const AFirebirdDatabaseFileName: string): Boolean;
var
  LFileStream: TFileStream;
  LODSStaticHeader: TODSStaticHeader;
begin
  Result := False;
  FODSHeaderInfo.Clear;

  if FileExists(AFirebirdDatabaseFileName) then
  begin
    LFileStream := TFileStream.Create(AFirebirdDatabaseFileName, fmOpenRead or fmShareDenyNone);
    try
      if ReadODSStaticHeader(LFileStream, LODSStaticHeader) then
        if DecodeODSStaticHeaderMajorVersion(LODSStaticHeader) then
          Result := ReadODSVariableHeader(LFileStream);
    finally
      LFileStream.Free;
    end;
  end;
end;

end.
