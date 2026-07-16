unit FHRUnit.HeaderReader.Types;

interface

uses
  System.Classes;

const
  UNINITIALIZED_VERSION = -1;
  // Some fields simply do not exist in every ODS generation (Firebird 6 / ODS 14
  // dropped hdr_sequence and hdr_next_page, for example). Those report this.
  VALUE_NOT_AVAILABLE = -1;

type
  // Decoded hdr_flags / ODS 14 mode bytes. Mirrors what "gstat -h" prints as Attributes.
  TFirebirdDatabaseAttribute = (
    fdaForceWrite,
    fdaNoReserve,
    fdaNoChecksums,        // ODS 10/11 only
    fdaActiveShadow,
    fdaReadOnly,
    fdaEncrypted,          // ODS 12+
    fdaCryptProcess,       // ODS 12+
    fdaShutdownMulti,
    fdaShutdownFull,
    fdaShutdownSingle,
    fdaBackupLock,
    fdaBackupMerge,
    fdaReplicaReadOnly,    // ODS 13+
    fdaReplicaReadWrite    // ODS 13+
  );

  TFirebirdDatabaseAttributes = set of TFirebirdDatabaseAttribute;

  TFireBirdODSHeaderInfo = class(TObject)
  strict private
    FAttributes: TFirebirdDatabaseAttributes;
    FCreationDate: TDateTime;
    FDialect: Integer;
    FGeneration: Cardinal;
    FIsFirebirdDatabase: Boolean;
    FMajorVersion: Integer;
    FMinorVersion: Integer;
    FNextAttachmentID: Int64;
    FNextHeaderPage: Int64;
    FNextTransaction: Int64;
    FOldestActive: Int64;
    FOldestSnapshot: Int64;
    FOldestTransaction: Int64;
    FPageBuffers: Int64;
    FPageFlags: Byte;
    FPageSize: Integer;
    FSequenceNumber: Int64;
    FShadowCount: Integer;
    FSystemChangeNumber: Cardinal;
    function InternalODSVersionStr: string;
  public
    constructor Create;

    procedure Clear;
    procedure ToStrings(const AStrings: TStrings);
    function ODSVersionStr: string;
    function AttributesStr: string;

    property Attributes: TFirebirdDatabaseAttributes read FAttributes write FAttributes;
    property CreationDate: TDateTime read FCreationDate write FCreationDate;
    property Dialect: Integer read FDialect write FDialect;
    property Generation: Cardinal read FGeneration write FGeneration;
    property IsFirebirdDatabase: Boolean read FIsFirebirdDatabase write FIsFirebirdDatabase;
    property MajorVersion: Integer read FMajorVersion write FMajorVersion;
    property MinorVersion: Integer read FMinorVersion write FMinorVersion;
    property NextAttachmentID: Int64 read FNextAttachmentID write FNextAttachmentID;
    property NextHeaderPage: Int64 read FNextHeaderPage write FNextHeaderPage;
    property NextTransaction: Int64 read FNextTransaction write FNextTransaction;
    property OldestActive: Int64 read FOldestActive write FOldestActive;
    property OldestSnapshot: Int64 read FOldestSnapshot write FOldestSnapshot;
    property OldestTransaction: Int64 read FOldestTransaction write FOldestTransaction;
    property PageBuffers: Int64 read FPageBuffers write FPageBuffers;
    property PageFlags: Byte read FPageFlags write FPageFlags;
    property PageSize: Integer read FPageSize write FPageSize;
    property SequenceNumber: Int64 read FSequenceNumber write FSequenceNumber;
    property ShadowCount: Integer read FShadowCount write FShadowCount;
    property SystemChangeNumber: Cardinal read FSystemChangeNumber write FSystemChangeNumber;
  end;

  // "struct pag" - the 16 byte prefix every database page starts with.
  TODSPag = packed record
    PageType: Byte;      // Offset 0  - pag_type, 1 = header page
    PageFlags: Byte;     // Offset 1  - pag_flags, printed as "Flags" by gstat
    Reserved: Word;      // Offset 2  - alignment only
    Generation: Cardinal;// Offset 4  - pag_generation
    SCN: Cardinal;       // Offset 8  - pag_scn, "System Change Number"
    PageNo: Cardinal;    // Offset 12 - pag_pageno, for validation
  end;

  // Fixed prefix shared by every ODS version - enough to detect the version and
  // decide which of the header page records below applies.
  TODSStaticHeader = packed record
  public
    StructPag: array [0..15] of Byte; // Offset 00..15 - 16 bytes
    PageSize: Word;                   // Offset 16..17 - 2 bytes
    EncodedODSMajorVersion: Word;     // Offset 18..19 - 2 bytes

    procedure Clear;

    function IsHeaderPage: Boolean;    // pag_type = 1 marks a database header page
    function HasFirebirdFlag: Boolean; // set by Firebird 2.0+ (ODS 11+), absent on InterBase / Firebird 1.x
    function ODSMajorVersion: Word;    // ODS major version, with the Firebird flag stripped off
  end;

  // Firebird 1.0.x / 1.5.x (ODS 10) and 2.0.x / 2.1.x / 2.5.x (ODS 11).
  // The two generations are identical over every field this reader uses; they only
  // diverge past OldestSnapshot (ODS 10 has misc[4], ODS 11 has backup_pages + misc[3]),
  // and both end with hdr_data at offset 96.
  TODSHeaderPage10_11 = packed record
    Pag: TODSPag;                         // Offset 0
    PageSize: Word;                       // Offset 16
    EncodedODSVersion: Word;              // Offset 18
    PagesRelationPage: Cardinal;          // Offset 20 - hdr_PAGES
    NextPage: Cardinal;                   // Offset 24 - hdr_next_page
    OldestTransaction: Cardinal;          // Offset 28
    OldestActive: Cardinal;               // Offset 32
    NextTransaction: Cardinal;            // Offset 36
    Sequence: Word;                       // Offset 40
    Flags: Word;                          // Offset 42 - hdr_flags
    CreationDate: array [0..1] of Integer;// Offset 44 - ISC date / time
    AttachmentID: Cardinal;               // Offset 52
    ShadowCount: Integer;                 // Offset 56
    ImplementationNumber: SmallInt;       // Offset 60 - hdr_implementation
    ODSMinor: Word;                       // Offset 62 - hdr_ods_minor
    ODSMinorOriginal: Word;               // Offset 64 - ODS the database was CREATED with
    HeaderEnd: Word;                      // Offset 66 - hdr_end
    PageBuffers: Cardinal;                // Offset 68
    BumpedTransaction: Integer;           // Offset 72
    OldestSnapshot: Cardinal;             // Offset 76
  end;                                    // 80 bytes read (struct continues to 96)

  // Firebird 3.0.x (ODS 12). hdr_implementation was split into the CPU/OS/CC bytes,
  // which pushed hdr_ods_minor to offset 64, and the transaction counters gained
  // separate high words at the end.
  TODSHeaderPage12 = packed record
    Pag: TODSPag;                         // Offset 0
    PageSize: Word;                       // Offset 16
    EncodedODSVersion: Word;              // Offset 18
    PagesRelationPage: Cardinal;          // Offset 20
    NextPage: Cardinal;                   // Offset 24
    OldestTransaction: Cardinal;          // Offset 28
    OldestActive: Cardinal;               // Offset 32
    NextTransaction: Cardinal;            // Offset 36
    Sequence: Word;                       // Offset 40
    Flags: Word;                          // Offset 42
    CreationDate: array [0..1] of Integer;// Offset 44
    AttachmentID: Cardinal;               // Offset 52
    ShadowCount: Integer;                 // Offset 56
    CPU: Byte;                            // Offset 60
    OS: Byte;                             // Offset 61
    CC: Byte;                             // Offset 62
    CompatibilityFlags: Byte;             // Offset 63
    ODSMinor: Word;                       // Offset 64 - hdr_ods_minor
    HeaderEnd: Word;                      // Offset 66
    PageBuffers: Cardinal;                // Offset 68
    OldestSnapshot: Cardinal;             // Offset 72
    BackupPages: Integer;                 // Offset 76
    CryptPage: Cardinal;                  // Offset 80
    TopCrypt: Cardinal;                   // Offset 84 - only ODS 12 has this
    CryptPlugin: array [0..31] of AnsiChar;// Offset 88
    AttHigh: Integer;                     // Offset 120
    TraHigh: array [0..3] of Word;        // Offset 124
  end;                                    // 132 bytes = hdr_data offset

  // Firebird 4.0.x / 5.0.x (ODS 13). Same as ODS 12 except hdr_top_crypt is gone,
  // which moves everything from CryptPlugin on 4 bytes down.
  TODSHeaderPage13 = packed record
    Pag: TODSPag;                         // Offset 0
    PageSize: Word;                       // Offset 16
    EncodedODSVersion: Word;              // Offset 18
    PagesRelationPage: Cardinal;          // Offset 20
    NextPage: Cardinal;                   // Offset 24
    OldestTransaction: Cardinal;          // Offset 28
    OldestActive: Cardinal;               // Offset 32
    NextTransaction: Cardinal;            // Offset 36
    Sequence: Word;                       // Offset 40
    Flags: Word;                          // Offset 42
    CreationDate: array [0..1] of Integer;// Offset 44
    AttachmentID: Cardinal;               // Offset 52
    ShadowCount: Integer;                 // Offset 56
    CPU: Byte;                            // Offset 60
    OS: Byte;                             // Offset 61
    CC: Byte;                             // Offset 62
    CompatibilityFlags: Byte;             // Offset 63
    ODSMinor: Word;                       // Offset 64 - hdr_ods_minor
    HeaderEnd: Word;                      // Offset 66
    PageBuffers: Cardinal;                // Offset 68
    OldestSnapshot: Cardinal;             // Offset 72
    BackupPages: Integer;                 // Offset 76
    CryptPage: Cardinal;                  // Offset 80
    CryptPlugin: array [0..31] of AnsiChar;// Offset 84
    AttHigh: Integer;                     // Offset 116
    TraHigh: array [0..3] of Word;        // Offset 120
  end;                                    // 128 bytes = hdr_data offset

  // Firebird 6.0.x (ODS 14). The header page was reorganized: the minor version sits
  // next to the major one, the transaction counters became native 64 bit, the GUID
  // became a fixed field, and hdr_sequence / hdr_next_page were dropped entirely.
  TODSHeaderPage14 = packed record
    Pag: TODSPag;                         // Offset 0
    PageSize: Word;                       // Offset 16
    EncodedODSVersion: Word;              // Offset 18
    ODSMinor: Word;                       // Offset 20 - hdr_ods_minor
    Flags: Word;                          // Offset 22
    BackupMode: Byte;                     // Offset 24
    ShutdownMode: Byte;                   // Offset 25
    ReplicaMode: Byte;                    // Offset 26
    Unused1: Byte;                        // Offset 27 - alignment
    PagesRelationPage: Cardinal;          // Offset 28
    PageBuffers: Cardinal;                // Offset 32
    HeaderEnd: Word;                      // Offset 36
    Unused2: Word;                        // Offset 38 - alignment before the 64 bit fields
    NextTransaction: UInt64;              // Offset 40
    OldestTransaction: UInt64;            // Offset 48
    OldestActive: UInt64;                 // Offset 56
    OldestSnapshot: UInt64;               // Offset 64
    AttachmentID: UInt64;                 // Offset 72
    CPU: Byte;                            // Offset 80
    OS: Byte;                             // Offset 81
    CC: Byte;                             // Offset 82
    CompatibilityFlags: Byte;             // Offset 83
    GUID: array [0..15] of Byte;          // Offset 84
    CreationDate: array [0..1] of Integer;// Offset 100
    ShadowCount: Integer;                 // Offset 108
    CryptPage: Cardinal;                  // Offset 112
    CryptPlugin: array [0..31] of AnsiChar;// Offset 116
  end;                                    // 148 bytes = hdr_data offset

implementation

uses
  System.SysUtils, System.DateUtils;

{ TODSStaticHeader }

procedure TODSStaticHeader.Clear;
begin
  FillChar(Self, SizeOf(Self), 0);
end;

function TODSStaticHeader.IsHeaderPage: Boolean;
const
  PAGE_TYPE_HEADER = 1; // pag_type of a database header page (StructPag offset 0)
begin
  Result := StructPag[0] = PAGE_TYPE_HEADER;
end;

function TODSStaticHeader.HasFirebirdFlag: Boolean;
const
  ODS_FIREBIRD_FLAG = $8000;
begin
  Result := (EncodedODSMajorVersion and ODS_FIREBIRD_FLAG) <> 0;
end;

function TODSStaticHeader.ODSMajorVersion: Word;
const
  ODS_MAJOR_VERSION_MASK = $7FFF;
begin
  Result := EncodedODSMajorVersion and ODS_MAJOR_VERSION_MASK;
end;

{ TFireBirdODSHeaderInfo }

constructor TFireBirdODSHeaderInfo.Create;
begin
  inherited Create;

  Clear;
end;

procedure TFireBirdODSHeaderInfo.Clear;
begin
  FAttributes := [];
  FCreationDate := 0;
  FDialect := VALUE_NOT_AVAILABLE;
  FGeneration := 0;
  FIsFirebirdDatabase := False;
  FMajorVersion := UNINITIALIZED_VERSION;
  FMinorVersion := UNINITIALIZED_VERSION;
  FNextAttachmentID := VALUE_NOT_AVAILABLE;
  FNextHeaderPage := VALUE_NOT_AVAILABLE;
  FNextTransaction := VALUE_NOT_AVAILABLE;
  FOldestActive := VALUE_NOT_AVAILABLE;
  FOldestSnapshot := VALUE_NOT_AVAILABLE;
  FOldestTransaction := VALUE_NOT_AVAILABLE;
  FPageBuffers := VALUE_NOT_AVAILABLE;
  FPageFlags := 0;
  FPageSize := 0;
  FSequenceNumber := VALUE_NOT_AVAILABLE;
  FShadowCount := VALUE_NOT_AVAILABLE;
  FSystemChangeNumber := 0;
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

function TFireBirdODSHeaderInfo.AttributesStr: string;
const
  ATTRIBUTE_NAMES: array [TFirebirdDatabaseAttribute] of string = (
    'force write',
    'no reserve',
    'no checksums',
    'active shadow',
    'read only',
    'encrypted',
    'crypt process',
    'multi-user maintenance',
    'full shutdown',
    'single-user maintenance',
    'backup lock',
    'merge',
    'read-only replica',
    'read-write replica'
  );
var
  LAttribute: TFirebirdDatabaseAttribute;
begin
  Result := '';

  for LAttribute := Low(TFirebirdDatabaseAttribute) to High(TFirebirdDatabaseAttribute) do
    if LAttribute in FAttributes then
    begin
      if not Result.IsEmpty then
        Result := Result + ', ';

      Result := Result + ATTRIBUTE_NAMES[LAttribute];
    end;
end;

procedure TFireBirdODSHeaderInfo.ToStrings(const AStrings: TStrings);

  procedure AddValue(const ACaption: string; const AValue: Int64);
  begin
    if AValue = VALUE_NOT_AVAILABLE then
      AStrings.Add(ACaption + ' = n/a')
    else
      AStrings.Add(ACaption + ' = ' + AValue.ToString);
  end;

begin
  AStrings.Add('Flags = ' + FPageFlags.ToString);
  AStrings.Add('Generation = ' + FGeneration.ToString);
  AStrings.Add('System Change Number = ' + FSystemChangeNumber.ToString);
  AStrings.Add('Page size = ' + FPageSize.ToString);
  AStrings.Add('ODS version = ' + ODSVersionStr);
  AddValue('Oldest transaction', FOldestTransaction);
  AddValue('Oldest active', FOldestActive);
  AddValue('Oldest snapshot', FOldestSnapshot);
  AddValue('Next transaction', FNextTransaction);
  AddValue('Sequence number', FSequenceNumber);
  AddValue('Next attachment ID', FNextAttachmentID);
  AddValue('Shadow count', FShadowCount);
  AddValue('Page buffers', FPageBuffers);
  AddValue('Next header page', FNextHeaderPage);
  AddValue('Database dialect', FDialect);

  if FCreationDate = 0 then
    AStrings.Add('Creation date = n/a')
  else
    AStrings.Add('Creation date = ' + FormatDateTime('mmm d, yyyy h:nn:ss', FCreationDate));

  AStrings.Add('Attributes = ' + AttributesStr);
end;

end.
