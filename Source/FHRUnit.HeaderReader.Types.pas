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
    procedure Clear;
    procedure ToStrings(const AStrings: TStrings);
    function ODSVersionStr: string;

    property IsFirebirdDatabase: Boolean read FIsFirebirdDatabase write FIsFirebirdDatabase;
    property PageSize: Integer read FPageSize write FPageSize;
    property MajorVersion: Integer read FMajorVersion write FMajorVersion;
    property MinorVersion: Integer read FMinorVersion write FMinorVersion;
  end;

  TODSStaticHeader = packed record
  public
    (*                        Size    Offset

      struct pag
      {
        UCHAR pag_type;       1       0
        UCHAR pag_flags;      1       1
        USHORT pag_reserved;	2       2  // not used but anyway present because of alignment rules
        ULONG pag_generation; 4       4
        ULONG pag_scn;        4       8
        ULONG pag_pageno;			4       12 // for validation
      };

      No
    *)
    StructPag: array [0..15] of Byte; // Offset 00..17
    PageSize: Word;                   // Offset 16..17
    EncodedODSMajorVersion: Word;     // Offset 18..19

    procedure Clear;
  end;


(* Not currently supported
  // Firebird 1.0
  TODSVariabeHeaderV10_0 = packed record
  end;
*)

(* Not currently supported
  // Firebird 1.5
  TODSVariabeHeaderV10_1 = packed record
  end;
*)

(* Not currently supported
  // Firebird 2.0
  TODSVariabeHeaderV11_1 = packed record
  end;
*)

(* Not currently supported
  // Firebird 2.1
  TODSVariabeHeaderV11_1 = packed record
  end;
*)

  // Firebird 2.x
  TODS11VariabeHeader = packed record
    Padding2: array [1..42] of Byte; // offset 20-63 (42 bytes)
    ODSMinorVersion: Word;           // Offset 63..64
    ODSMinorVersionOriginal : Word;  // Offset 65..66

    procedure Clear;
  end;

  // Firebird 3.0
  TODS12VariabeHeader = packed record
    Padding2: array [1..44] of Byte; // offset 20-65 (44 bytes)
    ODSMinorVersion: Word;           // Offset 66..67

    procedure Clear;
  end;

  // Firebird 4.0.x & 5.0.x
  TODS13VariabeHeader = packed record
    Padding2: array [1..44] of Byte; // offset 20-65 (44 bytes)
    ODSMinorVersion: Word;           // Offset 65..66

    procedure Clear;
  end;

  // Firebird 6.0
  TODS14VariabeHeader = packed record
    ODSMinorVersion: Word;           // Offset 20..21

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

{ TODS11VariabeHeader }

procedure TODS11VariabeHeader.Clear;
begin
  FillChar(Self, SizeOf(Self), 0);
end;

{ TODS12VariabeHeader }

procedure TODS12VariabeHeader.Clear;
begin
  FillChar(Self, SizeOf(Self), 0);
end;

{ TODS13VariabeHeader }

procedure TODS13VariabeHeader.Clear;
begin
  FillChar(Self, SizeOf(Self), 0);
end;

{ TODS14VariabeHeader }

procedure TODS14VariabeHeader.Clear;
begin
  FillChar(Self, SizeOf(Self), 0);
end;

{ TFireBirdODSHeaderInfo }

procedure TFireBirdODSHeaderInfo.Clear;
begin
  FIsFirebirdDatabase := False;
  FMajorVersion := UNINITIALIZED_VERSION;
  FMinorVersion := UNINITIALIZED_VERSION;
end;

function TFireBirdODSHeaderInfo.InternalODSVersionStr: string;
begin
  Result := FMajorVersion.ToString + '.' + FMinorVersion.ToString;
end;

function TFireBirdODSHeaderInfo.ODSVersionStr: string;
begin
  Result := '';

  if FMajorVersion <> UNINITIALIZED_VERSION  then
    Result := InternalODSVersionStr;
end;

procedure TFireBirdODSHeaderInfo.ToStrings(const AStrings: TStrings);
begin
  AStrings.Add('ODS version = ' + InternalODSVersionStr);
  AStrings.Add('Page size = ' + PageSize.ToString);
end;

end.
