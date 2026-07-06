unit FHRUnit.HeaderReader.Types;

interface

uses
  System.Classes;

const
  UNINITIALIZED_VERSION = -1;

type
  TFireBirdODSHeaderInfo = class(TObject)
  strict private
    FIsFirebirdDatabase: Boolean;
    FMajorVersion: Integer;
    FMinorVersion: Integer;
    FPageSize: Integer;
    function InternalODSVersionStr: string;
  public
    constructor Create;

    procedure Clear;
    procedure ToStrings(const AStrings: TStrings);
    function ODSVersionStr: string;

    property IsFirebirdDatabase: Boolean read FIsFirebirdDatabase write FIsFirebirdDatabase;
    property PageSize: Integer read FPageSize write FPageSize;
    property MajorVersion: Integer read FMajorVersion write FMajorVersion;
    property MinorVersion: Integer read FMinorVersion write FMinorVersion;
  end;

  // Fixed-size prefix shared by every ODS version. The stream is read into this
  // record first, then - depending on the major version - the minor version byte
  // is read from a version specific offset (see FHRUnit.HeaderReader).
  //
  // Layout of the on-disk "header_page" prefix (little-endian):
  //
  //   struct pag                    Size  Offset
  //   {
  //     UCHAR  pag_type;            1     0
  //     UCHAR  pag_flags;           1     1
  //     USHORT pag_reserved;        2     2   // alignment only
  //     ULONG  pag_generation;      4     4
  //     ULONG  pag_scn;             4     8
  //     ULONG  pag_pageno;          4     12  // for validation
  //   };
  //   USHORT hdr_page_size;         2     16
  //   USHORT hdr_ods_version;       2     18  // high bit ($8000) flags "is Firebird"
  //
  TODSStaticHeader = packed record
  public
    StructPag: array [0..15] of Byte; // Offset 00..15 - 16 bytes
    PageSize: Word;                   // Offset 16..17 - 2 bytes
    EncodedODSMajorVersion: Word;     // Offset 18..19 - 2 bytes

    procedure Clear;
  end;

implementation

uses
  System.SysUtils;

{ TODSStaticHeader }

procedure TODSStaticHeader.Clear;
begin
  FillChar(Self, SizeOf(Self), 0);
end;

{ TFireBirdODSHeaderInfo }

constructor TFireBirdODSHeaderInfo.Create;
begin
  inherited Create;

  Clear;
end;

procedure TFireBirdODSHeaderInfo.Clear;
begin
  FIsFirebirdDatabase := False;
  FMajorVersion := UNINITIALIZED_VERSION;
  FMinorVersion := UNINITIALIZED_VERSION;
  FPageSize := 0;
end;

function TFireBirdODSHeaderInfo.InternalODSVersionStr: string;
begin
  Result := FMajorVersion.ToString + '.' + FMinorVersion.ToString;
end;

function TFireBirdODSHeaderInfo.ODSVersionStr: string;
begin
  Result := '';

  if FMajorVersion <> UNINITIALIZED_VERSION then
    Result := InternalODSVersionStr;
end;

procedure TFireBirdODSHeaderInfo.ToStrings(const AStrings: TStrings);
begin
  AStrings.Add('ODS version = ' + ODSVersionStr);
  AStrings.Add('Page size = ' + FPageSize.ToString);
end;

end.
