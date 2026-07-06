unit FHRUnit.HeaderReader;

interface

uses
  System.Classes, FHRUnit.HeaderReader.Types;

type
  TFirebirdODSHeaderReader = class(TObject)
  strict private
    FODSHeaderInfo: TFireBirdODSHeaderInfo;
    function ReadODSStaticHeader(const AStream: TStream; var AODSHeader: TODSStaticHeader): Boolean;
    function DecodeODSStaticHeader(const AODSStaticHeader: TODSStaticHeader): Boolean;
    function ReadODSMinorVersion(const AStream: TStream): Boolean;
  public
    constructor Create;
    destructor Destroy; override;

    function ReadHeader(const AFirebirdDatabaseFileName: string): Boolean;
    property ODSHeaderInfo: TFireBirdODSHeaderInfo read FODSHeaderInfo;
  end;

implementation

uses
  System.SysUtils;

const
  // Absolute file offset of the "hdr_ods_minor" byte, which differs between ODS
  // generations because the header page was restructured for Firebird 6 / ODS 14.
  //
  //   ODS 10 - Firebird 1.0.x / 1.5.x         |
  //   ODS 11 - Firebird 2.0.x / 2.1.x / 2.5.x |  hdr_ods_minor at offset 64
  //   ODS 12 - Firebird 3.0.x                 |
  //   ODS 13 - Firebird 4.0.x / 5.0.x         |
  //   ODS 14 - Firebird 6.0.x                 -> hdr_ods_minor at offset 20
  //
  ODS_MINOR_VERSION_OFFSET_ODS_10_TO_13 = 64;
  ODS_MINOR_VERSION_OFFSET_ODS_14       = 20;

  MAJOR_VERSION_HAS_NO_KNOWN_OFFSET = -1;

function MinorVersionFileOffset(const AMajorVersion: Integer): Integer;
begin
  case AMajorVersion of
    10, 11, 12, 13: Result := ODS_MINOR_VERSION_OFFSET_ODS_10_TO_13;
    14:             Result := ODS_MINOR_VERSION_OFFSET_ODS_14;
  else
    Result := MAJOR_VERSION_HAS_NO_KNOWN_OFFSET;
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

  inherited Destroy;
end;

function TFirebirdODSHeaderReader.DecodeODSStaticHeader(const AODSStaticHeader: TODSStaticHeader): Boolean;
begin
  Result := False;

  // Every database file starts with a header page whose pag_type is 1. Checking
  // it rejects files that merely happen to have plausible bytes at offset 18..19.
  if not AODSStaticHeader.IsHeaderPage then
    Exit;

  FODSHeaderInfo.PageSize := AODSStaticHeader.PageSize;

  // ODS 10 (Firebird 1.0 / 1.5) predates the Firebird flag and is accepted without
  // it - Firebird 1.x and InterBase 6 share this format and the ODS version is
  // still correct. ODS 11+ must carry the flag; without it the file is InterBase,
  // not Firebird, and its layout differs from the one this reader understands.
  case AODSStaticHeader.ODSMajorVersion of
    10:             Result := True;
    11, 12, 13, 14: Result := AODSStaticHeader.HasFirebirdFlag;
  end;

  if not Result then
    Exit;

  FODSHeaderInfo.IsFirebirdDatabase := True;
  FODSHeaderInfo.MajorVersion := AODSStaticHeader.ODSMajorVersion;
end;

function TFirebirdODSHeaderReader.ReadODSStaticHeader(const AStream: TStream; var AODSHeader: TODSStaticHeader): Boolean;
begin
  AODSHeader.Clear;

  Result := AStream.Read(AODSHeader, SizeOf(TODSStaticHeader)) = SizeOf(TODSStaticHeader);

  if not Result then
    AODSHeader.Clear;
end;

function TFirebirdODSHeaderReader.ReadODSMinorVersion(const AStream: TStream): Boolean;
var
  LMinorVersionOffset: Integer;
  LODSMinorVersion: Byte;
begin
  Result := False;
  FODSHeaderInfo.MinorVersion := 0;

  LMinorVersionOffset := MinorVersionFileOffset(FODSHeaderInfo.MajorVersion);

  if LMinorVersionOffset = MAJOR_VERSION_HAS_NO_KNOWN_OFFSET then
    Exit;

  if LMinorVersionOffset + SizeOf(LODSMinorVersion) > AStream.Size then
    Exit;

  AStream.Position := LMinorVersionOffset;

  Result := AStream.Read(LODSMinorVersion, SizeOf(LODSMinorVersion)) = SizeOf(LODSMinorVersion);

  if Result then
    FODSHeaderInfo.MinorVersion := LODSMinorVersion;
end;

function TFirebirdODSHeaderReader.ReadHeader(const AFirebirdDatabaseFileName: string): Boolean;
var
  LFileStream: TFileStream;
  LODSStaticHeader: TODSStaticHeader;
begin
  Result := False;
  FODSHeaderInfo.Clear;

  if not FileExists(AFirebirdDatabaseFileName) then
    Exit;

  // A database that is in use by a running server can refuse to open (sharing
  // violation / access denied). Treat that as "not readable" rather than letting
  // the exception escape to the caller.
  try
    LFileStream := TFileStream.Create(AFirebirdDatabaseFileName, fmOpenRead or fmShareDenyNone);
    try
      if ReadODSStaticHeader(LFileStream, LODSStaticHeader) then
        if DecodeODSStaticHeader(LODSStaticHeader) then
          Result := ReadODSMinorVersion(LFileStream);
    finally
      LFileStream.Free;
    end;
  except
    on EStreamError do
      FODSHeaderInfo.Clear;
  end;
end;

end.
