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
    function ReadRecord(const AStream: TStream; var ABuffer; const ASize: Integer): Boolean;
    function ReadHeaderPage(const AStream: TStream): Boolean;
    function ReadHeaderPage10_11(const AStream: TStream): Boolean;
    function ReadHeaderPage12(const AStream: TStream): Boolean;
    function ReadHeaderPage13(const AStream: TStream): Boolean;
    function ReadHeaderPage14(const AStream: TStream): Boolean;
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
  // hdr_flags bits. Firebird 3 / ODS 12 renumbered these, so ODS 10/11 needs its own set.
  ODS_10_11_FLAG_ACTIVE_SHADOW = $001;
  ODS_10_11_FLAG_FORCE_WRITE   = $002;
  ODS_10_11_FLAG_NO_CHECKSUMS  = $010;
  ODS_10_11_FLAG_NO_RESERVE    = $020;
  ODS_10_11_FLAG_SQL_DIALECT_3 = $100;
  ODS_10_11_FLAG_READ_ONLY     = $200;

  ODS_12_PLUS_FLAG_ACTIVE_SHADOW = $01;
  ODS_12_PLUS_FLAG_FORCE_WRITE   = $02;
  ODS_12_PLUS_FLAG_CRYPT_PROCESS = $04;
  ODS_12_PLUS_FLAG_NO_RESERVE    = $08;
  ODS_12_PLUS_FLAG_SQL_DIALECT_3 = $10;
  ODS_12_PLUS_FLAG_READ_ONLY     = $20;
  ODS_12_PLUS_FLAG_ENCRYPTED     = $40;

  // Shared by every generation that keeps these in hdr_flags (ODS 10..13).
  FLAG_BACKUP_MASK   = $0C00;
  FLAG_BACKUP_STALLED = $0400;
  FLAG_BACKUP_MERGE   = $0800;

  FLAG_SHUTDOWN_MASK   = $1080;
  FLAG_SHUTDOWN_MULTI  = $0080;
  FLAG_SHUTDOWN_FULL   = $1000;
  FLAG_SHUTDOWN_SINGLE = $1080;

  FLAG_REPLICA_MASK       = $6000;
  FLAG_REPLICA_READ_ONLY  = $2000;
  FLAG_REPLICA_READ_WRITE = $4000;

  // ODS 14 keeps backup / shutdown / replica in their own byte fields instead.
  ODS_14_BACKUP_STALLED = 1;
  ODS_14_BACKUP_MERGE   = 2;

  ODS_14_SHUTDOWN_MULTI  = 1;
  ODS_14_SHUTDOWN_SINGLE = 2;
  ODS_14_SHUTDOWN_FULL   = 3;

  ODS_14_REPLICA_READ_ONLY  = 1;
  ODS_14_REPLICA_READ_WRITE = 2;

  // hdr_creation_date[0] counts days from 17 Nov 1858, TDateTime counts from
  // 30 Dec 1899 - exactly 15018 days later. [1] is 1/10000 seconds since midnight.
  ISC_DATE_EPOCH_TO_DELPHI_EPOCH_DAYS = 15018;
  ISC_TIME_UNITS_PER_SECOND = 10000;
  SECONDS_PER_DAY = 24 * 60 * 60;

function ISCTimeStampToDateTime(const AISCDate, AISCTime: Integer): TDateTime;
begin
  Result := (AISCDate - ISC_DATE_EPOCH_TO_DELPHI_EPOCH_DAYS)
    + (AISCTime / ISC_TIME_UNITS_PER_SECOND / SECONDS_PER_DAY);
end;

// Combines a 32 bit counter with its high word, the way Ods::getNT / getOIT / getOAT /
// getOST / getAttID do in the Firebird sources.
function CombineHighWord(const AHighWord: Cardinal; const ALowValue: Cardinal): Int64;
begin
  Result := (Int64(AHighWord) shl 32) or ALowValue;
end;

function BackupAttributeFromMask(const AFlags: Word): TFirebirdDatabaseAttributes;
begin
  Result := [];

  case AFlags and FLAG_BACKUP_MASK of
    FLAG_BACKUP_STALLED: Result := [fdaBackupLock];
    FLAG_BACKUP_MERGE:   Result := [fdaBackupMerge];
  end;
end;

function ShutdownAttributeFromMask(const AFlags: Word): TFirebirdDatabaseAttributes;
begin
  Result := [];

  // Single is 0x1080, i.e. both of the other bits, so test it first.
  case AFlags and FLAG_SHUTDOWN_MASK of
    FLAG_SHUTDOWN_SINGLE: Result := [fdaShutdownSingle];
    FLAG_SHUTDOWN_FULL:   Result := [fdaShutdownFull];
    FLAG_SHUTDOWN_MULTI:  Result := [fdaShutdownMulti];
  end;
end;

function ReplicaAttributeFromMask(const AFlags: Word): TFirebirdDatabaseAttributes;
begin
  Result := [];

  case AFlags and FLAG_REPLICA_MASK of
    FLAG_REPLICA_READ_ONLY:  Result := [fdaReplicaReadOnly];
    FLAG_REPLICA_READ_WRITE: Result := [fdaReplicaReadWrite];
  end;
end;

function AttributesFromODS10_11Flags(const AFlags: Word): TFirebirdDatabaseAttributes;
begin
  Result := [];

  if (AFlags and ODS_10_11_FLAG_FORCE_WRITE) <> 0 then
    Include(Result, fdaForceWrite);
  if (AFlags and ODS_10_11_FLAG_NO_RESERVE) <> 0 then
    Include(Result, fdaNoReserve);
  if (AFlags and ODS_10_11_FLAG_NO_CHECKSUMS) <> 0 then
    Include(Result, fdaNoChecksums);
  if (AFlags and ODS_10_11_FLAG_ACTIVE_SHADOW) <> 0 then
    Include(Result, fdaActiveShadow);
  if (AFlags and ODS_10_11_FLAG_READ_ONLY) <> 0 then
    Include(Result, fdaReadOnly);

  Result := Result + BackupAttributeFromMask(AFlags) + ShutdownAttributeFromMask(AFlags);
end;

function AttributesFromODS12PlusFlags(const AFlags: Word): TFirebirdDatabaseAttributes;
begin
  Result := [];

  if (AFlags and ODS_12_PLUS_FLAG_FORCE_WRITE) <> 0 then
    Include(Result, fdaForceWrite);
  if (AFlags and ODS_12_PLUS_FLAG_NO_RESERVE) <> 0 then
    Include(Result, fdaNoReserve);
  if (AFlags and ODS_12_PLUS_FLAG_ACTIVE_SHADOW) <> 0 then
    Include(Result, fdaActiveShadow);
  if (AFlags and ODS_12_PLUS_FLAG_READ_ONLY) <> 0 then
    Include(Result, fdaReadOnly);
  if (AFlags and ODS_12_PLUS_FLAG_ENCRYPTED) <> 0 then
    Include(Result, fdaEncrypted);
  if (AFlags and ODS_12_PLUS_FLAG_CRYPT_PROCESS) <> 0 then
    Include(Result, fdaCryptProcess);

  Result := Result + BackupAttributeFromMask(AFlags) + ShutdownAttributeFromMask(AFlags)
    + ReplicaAttributeFromMask(AFlags);
end;

function DialectFromFlags(const AFlags, ADialect3Flag: Word): Integer;
begin
  if (AFlags and ADialect3Flag) <> 0 then
    Result := 3
  else
    Result := 1;
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

function TFirebirdODSHeaderReader.ReadRecord(const AStream: TStream; var ABuffer; const ASize: Integer): Boolean;
begin
  FillChar(ABuffer, ASize, 0);

  AStream.Position := 0;

  Result := AStream.Read(ABuffer, ASize) = ASize;
end;

function TFirebirdODSHeaderReader.ReadHeaderPage10_11(const AStream: TStream): Boolean;
var
  LHeaderPage: TODSHeaderPage10_11;
begin
  Result := ReadRecord(AStream, LHeaderPage, SizeOf(LHeaderPage));

  if not Result then
    Exit;

  FODSHeaderInfo.MinorVersion := LHeaderPage.ODSMinor;
  FODSHeaderInfo.PageFlags := LHeaderPage.Pag.PageFlags;
  FODSHeaderInfo.Generation := LHeaderPage.Pag.Generation;
  FODSHeaderInfo.SystemChangeNumber := LHeaderPage.Pag.SCN;
  FODSHeaderInfo.OldestTransaction := LHeaderPage.OldestTransaction;
  FODSHeaderInfo.OldestActive := LHeaderPage.OldestActive;
  FODSHeaderInfo.OldestSnapshot := LHeaderPage.OldestSnapshot;
  FODSHeaderInfo.NextTransaction := LHeaderPage.NextTransaction;
  FODSHeaderInfo.SequenceNumber := LHeaderPage.Sequence;
  FODSHeaderInfo.NextAttachmentID := LHeaderPage.AttachmentID;
  FODSHeaderInfo.ShadowCount := LHeaderPage.ShadowCount;
  FODSHeaderInfo.PageBuffers := LHeaderPage.PageBuffers;
  FODSHeaderInfo.NextHeaderPage := LHeaderPage.NextPage;
  FODSHeaderInfo.Dialect := DialectFromFlags(LHeaderPage.Flags, ODS_10_11_FLAG_SQL_DIALECT_3);
  FODSHeaderInfo.Attributes := AttributesFromODS10_11Flags(LHeaderPage.Flags);
  FODSHeaderInfo.CreationDate := ISCTimeStampToDateTime(LHeaderPage.CreationDate[0], LHeaderPage.CreationDate[1]);
end;

function TFirebirdODSHeaderReader.ReadHeaderPage12(const AStream: TStream): Boolean;
var
  LHeaderPage: TODSHeaderPage12;
begin
  Result := ReadRecord(AStream, LHeaderPage, SizeOf(LHeaderPage));

  if not Result then
    Exit;

  FODSHeaderInfo.MinorVersion := LHeaderPage.ODSMinor;
  FODSHeaderInfo.PageFlags := LHeaderPage.Pag.PageFlags;
  FODSHeaderInfo.Generation := LHeaderPage.Pag.Generation;
  FODSHeaderInfo.SystemChangeNumber := LHeaderPage.Pag.SCN;
  FODSHeaderInfo.NextTransaction := CombineHighWord(LHeaderPage.TraHigh[0], LHeaderPage.NextTransaction);
  FODSHeaderInfo.OldestTransaction := CombineHighWord(LHeaderPage.TraHigh[1], LHeaderPage.OldestTransaction);
  FODSHeaderInfo.OldestActive := CombineHighWord(LHeaderPage.TraHigh[2], LHeaderPage.OldestActive);
  FODSHeaderInfo.OldestSnapshot := CombineHighWord(LHeaderPage.TraHigh[3], LHeaderPage.OldestSnapshot);
  FODSHeaderInfo.SequenceNumber := LHeaderPage.Sequence;
  FODSHeaderInfo.NextAttachmentID := CombineHighWord(Cardinal(LHeaderPage.AttHigh), LHeaderPage.AttachmentID);
  FODSHeaderInfo.ShadowCount := LHeaderPage.ShadowCount;
  FODSHeaderInfo.PageBuffers := LHeaderPage.PageBuffers;
  FODSHeaderInfo.NextHeaderPage := LHeaderPage.NextPage;
  FODSHeaderInfo.Dialect := DialectFromFlags(LHeaderPage.Flags, ODS_12_PLUS_FLAG_SQL_DIALECT_3);
  FODSHeaderInfo.Attributes := AttributesFromODS12PlusFlags(LHeaderPage.Flags);
  FODSHeaderInfo.CreationDate := ISCTimeStampToDateTime(LHeaderPage.CreationDate[0], LHeaderPage.CreationDate[1]);
end;

function TFirebirdODSHeaderReader.ReadHeaderPage13(const AStream: TStream): Boolean;
var
  LHeaderPage: TODSHeaderPage13;
begin
  Result := ReadRecord(AStream, LHeaderPage, SizeOf(LHeaderPage));

  if not Result then
    Exit;

  FODSHeaderInfo.MinorVersion := LHeaderPage.ODSMinor;
  FODSHeaderInfo.PageFlags := LHeaderPage.Pag.PageFlags;
  FODSHeaderInfo.Generation := LHeaderPage.Pag.Generation;
  FODSHeaderInfo.SystemChangeNumber := LHeaderPage.Pag.SCN;
  FODSHeaderInfo.NextTransaction := CombineHighWord(LHeaderPage.TraHigh[0], LHeaderPage.NextTransaction);
  FODSHeaderInfo.OldestTransaction := CombineHighWord(LHeaderPage.TraHigh[1], LHeaderPage.OldestTransaction);
  FODSHeaderInfo.OldestActive := CombineHighWord(LHeaderPage.TraHigh[2], LHeaderPage.OldestActive);
  FODSHeaderInfo.OldestSnapshot := CombineHighWord(LHeaderPage.TraHigh[3], LHeaderPage.OldestSnapshot);
  FODSHeaderInfo.SequenceNumber := LHeaderPage.Sequence;
  FODSHeaderInfo.NextAttachmentID := CombineHighWord(Cardinal(LHeaderPage.AttHigh), LHeaderPage.AttachmentID);
  FODSHeaderInfo.ShadowCount := LHeaderPage.ShadowCount;
  FODSHeaderInfo.PageBuffers := LHeaderPage.PageBuffers;
  FODSHeaderInfo.NextHeaderPage := LHeaderPage.NextPage;
  FODSHeaderInfo.Dialect := DialectFromFlags(LHeaderPage.Flags, ODS_12_PLUS_FLAG_SQL_DIALECT_3);
  FODSHeaderInfo.Attributes := AttributesFromODS12PlusFlags(LHeaderPage.Flags);
  FODSHeaderInfo.CreationDate := ISCTimeStampToDateTime(LHeaderPage.CreationDate[0], LHeaderPage.CreationDate[1]);
end;

function TFirebirdODSHeaderReader.ReadHeaderPage14(const AStream: TStream): Boolean;
var
  LHeaderPage: TODSHeaderPage14;
  LAttributes: TFirebirdDatabaseAttributes;
begin
  Result := ReadRecord(AStream, LHeaderPage, SizeOf(LHeaderPage));

  if not Result then
    Exit;

  FODSHeaderInfo.MinorVersion := LHeaderPage.ODSMinor;
  FODSHeaderInfo.PageFlags := LHeaderPage.Pag.PageFlags;
  FODSHeaderInfo.Generation := LHeaderPage.Pag.Generation;
  FODSHeaderInfo.SystemChangeNumber := LHeaderPage.Pag.SCN;
  FODSHeaderInfo.NextTransaction := Int64(LHeaderPage.NextTransaction);
  FODSHeaderInfo.OldestTransaction := Int64(LHeaderPage.OldestTransaction);
  FODSHeaderInfo.OldestActive := Int64(LHeaderPage.OldestActive);
  FODSHeaderInfo.OldestSnapshot := Int64(LHeaderPage.OldestSnapshot);
  FODSHeaderInfo.NextAttachmentID := Int64(LHeaderPage.AttachmentID);
  FODSHeaderInfo.ShadowCount := LHeaderPage.ShadowCount;
  FODSHeaderInfo.PageBuffers := LHeaderPage.PageBuffers;
  FODSHeaderInfo.Dialect := DialectFromFlags(LHeaderPage.Flags, ODS_12_PLUS_FLAG_SQL_DIALECT_3);
  FODSHeaderInfo.CreationDate := ISCTimeStampToDateTime(LHeaderPage.CreationDate[0], LHeaderPage.CreationDate[1]);

  // ODS 14 dropped hdr_sequence and hdr_next_page - they stay "not available".

  LAttributes := AttributesFromODS12PlusFlags(LHeaderPage.Flags);

  // Backup / shutdown / replica state moved out of hdr_flags into their own bytes,
  // so drop whatever the shared mask decoding guessed and use the byte fields.
  LAttributes := LAttributes - [fdaBackupLock, fdaBackupMerge, fdaShutdownMulti, fdaShutdownFull,
    fdaShutdownSingle, fdaReplicaReadOnly, fdaReplicaReadWrite];

  case LHeaderPage.BackupMode of
    ODS_14_BACKUP_STALLED: Include(LAttributes, fdaBackupLock);
    ODS_14_BACKUP_MERGE:   Include(LAttributes, fdaBackupMerge);
  end;

  case LHeaderPage.ShutdownMode of
    ODS_14_SHUTDOWN_MULTI:  Include(LAttributes, fdaShutdownMulti);
    ODS_14_SHUTDOWN_SINGLE: Include(LAttributes, fdaShutdownSingle);
    ODS_14_SHUTDOWN_FULL:   Include(LAttributes, fdaShutdownFull);
  end;

  case LHeaderPage.ReplicaMode of
    ODS_14_REPLICA_READ_ONLY:  Include(LAttributes, fdaReplicaReadOnly);
    ODS_14_REPLICA_READ_WRITE: Include(LAttributes, fdaReplicaReadWrite);
  end;

  FODSHeaderInfo.Attributes := LAttributes;
end;

function TFirebirdODSHeaderReader.ReadHeaderPage(const AStream: TStream): Boolean;
begin
  Result := False;

  case FODSHeaderInfo.MajorVersion of
    10, 11: Result := ReadHeaderPage10_11(AStream);
    12:     Result := ReadHeaderPage12(AStream);
    13:     Result := ReadHeaderPage13(AStream);
    14:     Result := ReadHeaderPage14(AStream);
  end;
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
          Result := ReadHeaderPage(LFileStream);
    finally
      LFileStream.Free;
    end;

    if not Result then
      FODSHeaderInfo.Clear;
  except
    on EStreamError do
      FODSHeaderInfo.Clear;
  end;
end;

end.
