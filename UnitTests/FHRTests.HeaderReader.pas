unit FHRTests.HeaderReader;

interface

uses
  Winapi.Windows, System.Classes, System.SysUtils, DUnitX.TestFramework, FHRUnit.HeaderReader, FHRUnit.HeaderReader.Types;

type
  // Tests for the plain value object that carries the decoded header information.
  [TestFixture]
  TFireBirdODSHeaderInfoTests = class
  strict private
    FHeaderInfo: TFireBirdODSHeaderInfo;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure FreshInstance_IsUninitialized;
    [Test]
    procedure Clear_ResetsEveryField;
    [Test]
    procedure ODSVersionStr_IsEmpty_WhenUninitialized;
    [Test]
    procedure ODSVersionStr_Formats_AsMajorDotMinor;
    [Test]
    procedure ToStrings_ContainsVersionAndPageSize;
  end;

  // Tests that drive the reader with hand-built headers, so every branch and every
  // supported / rejected version can be checked without shipping a real database.
  [TestFixture]
  TFirebirdODSHeaderReaderSyntheticTests = class
  strict private
  const
    HEADER_BUFFER_SIZE = 1024;
    FIREBIRD_FLAG = $8000;
    PAGE_TYPE_HEADER = 1;
  strict private
    FReader: TFirebirdODSHeaderReader;
    FCreatedFiles: TStringList;
    function BuildHeader(const APageType: Byte; const APageSize, AEncodedOds: Word; const AByteAt20, AByteAt62, 
      AByteAt64: Byte): TBytes;
    function WriteTempFile(const ABytes: TBytes): string;
    function WriteHeaderFile(const APageType: Byte; const APageSize, AEncodedOds: Word; const AByteAt20, AByteAt62, 
      AByteAt64: Byte): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    // Firebird 1.x / ODS 10 - accepted even though the Firebird flag is absent.
    [Test]
    procedure Reads_Ods10_0_Firebird10;
    [Test]
    procedure Reads_Ods10_1_Firebird15;

    // The bug this project was reviewed for: the minor version must come from
    // hdr_ods_minor (offset 64), not the hdr_cc byte (offset 62).
    [Test]
    procedure Reads_Ods11_MinorFromOffset64_IgnoringHdrCcAtOffset62;

    [Test]
    procedure Reads_Ods12_0;
    [Test]
    procedure Reads_Ods13_1;

    // ODS 14 moved hdr_ods_minor to offset 20; offset 64 must be ignored.
    [Test]
    procedure Reads_Ods14_MinorFromOffset20_IgnoringOffset64;
    [Test]
    procedure Reads_Ods14_0;

    [Test]
    procedure Reports_PageSize;
    [Test]
    procedure RecognizedDatabase_IsFlaggedAsFirebird;

    // ODS 11+ without the Firebird flag is InterBase and must be rejected.
    [Test]
    procedure Rejects_Ods11_WithoutFirebirdFlag;
    [Test]
    procedure Rejects_Ods12_WithoutFirebirdFlag;

    [Test]
    procedure Rejects_WhenPageTypeIsNotHeader;
    [Test]
    procedure Rejects_UnsupportedMajorVersion_TooHigh;
    [Test]
    procedure Rejects_UnsupportedMajorVersion_TooLow;

    [Test]
    procedure Rejects_FileShorterThanStaticHeader;
    [Test]
    procedure Rejects_FileTooShortForMinorVersionOffset;
    [Test]
    procedure Rejects_EmptyFile;
    [Test]
    procedure Rejects_NonExistentFile;

    // Reusing one reader for several files must not leak state between reads.
    [Test]
    procedure Reader_CanBeReused_WithoutLeakingState;
  end;

  // Tests against the real sample databases in UnitTests\TestData. They are skipped
  // (reported as passed) when the data is not present, e.g. Git LFS not pulled.
  [TestFixture]
  TFirebirdODSHeaderReaderRealFileTests = class
  strict private
    FReader: TFirebirdODSHeaderReader;
    FTestDataDir: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    [TestCase('Firebird 1.5.x', 'fb15x\Employee_Fb1.5.6.fdb,10.1,10,1,4096')]
    [TestCase('Firebird 2.1.x', 'fb21x\Employee_Fb2.1.7.fdb,11.1,11,1,4096')]
    [TestCase('Firebird 2.5.x', 'fb25x\Employee_Fb2.5.9.fdb,11.2,11,2,4096')]
    [TestCase('Firebird 3.0.x', 'fb30x\Employee_Fb3.0.12.fdb,12.0,12,0,8192')]
    [TestCase('Firebird 4.0.x', 'fb40x\Employee_Fb4.0.5.fdb,13.0,13,0,8192')]
    [TestCase('Firebird 5.0.x', 'fb50x\Employee_Fb5.0.2.fdb,13.1,13,1,8192')]
    [TestCase('Firebird 6.0.x', 'fb60x\Employee_Fb6.x.x.fdb,14.0,14,0,8192')]
    procedure Reads_ExpectedValues_FromRealDatabase(const ARelativePath, AExpectedOdsVersion: string;
      const AExpectedMajor, AExpectedMinor, AExpectedPageSize: Integer);
  end;

implementation

uses
  System.IOUtils;

function FindTestDataDir(out ATestDataDir: string): Boolean;

  function SearchUpwardsFor(const AStartDir: string): string;
  var
    LDir: string;
    LCandidate: string;
    LLevel: Integer;
  begin
    Result := '';
    LDir := AStartDir;

    for LLevel := 0 to 8 do
    begin
      if LDir.IsEmpty then
        Break;

      LCandidate := TPath.Combine(LDir, 'TestData');
      if TDirectory.Exists(LCandidate) then
        Exit(LCandidate);

      LDir := TPath.GetDirectoryName(LDir);
    end;
  end;

begin
  ATestDataDir := SearchUpwardsFor(TPath.GetDirectoryName(ParamStr(0)));

  if ATestDataDir.IsEmpty then
    ATestDataDir := SearchUpwardsFor(TDirectory.GetCurrentDirectory);

  Result := not ATestDataDir.IsEmpty;
end;

{ TFireBirdODSHeaderInfoTests }

procedure TFireBirdODSHeaderInfoTests.Setup;
begin
  FHeaderInfo := TFireBirdODSHeaderInfo.Create;
end;

procedure TFireBirdODSHeaderInfoTests.TearDown;
begin
  FreeAndNil(FHeaderInfo);
end;

procedure TFireBirdODSHeaderInfoTests.FreshInstance_IsUninitialized;
begin
  Assert.IsFalse(FHeaderInfo.IsFirebirdDatabase, 'IsFirebirdDatabase');
  Assert.AreEqual(UNINITIALIZED_VERSION, FHeaderInfo.MajorVersion, 'MajorVersion');
  Assert.AreEqual(UNINITIALIZED_VERSION, FHeaderInfo.MinorVersion, 'MinorVersion');
  Assert.AreEqual(0, FHeaderInfo.PageSize, 'PageSize');
end;

procedure TFireBirdODSHeaderInfoTests.Clear_ResetsEveryField;
begin
  FHeaderInfo.IsFirebirdDatabase := True;
  FHeaderInfo.MajorVersion := 13;
  FHeaderInfo.MinorVersion := 1;
  FHeaderInfo.PageSize := 8192;

  FHeaderInfo.Clear;

  Assert.IsFalse(FHeaderInfo.IsFirebirdDatabase, 'IsFirebirdDatabase');
  Assert.AreEqual(UNINITIALIZED_VERSION, FHeaderInfo.MajorVersion, 'MajorVersion');
  Assert.AreEqual(UNINITIALIZED_VERSION, FHeaderInfo.MinorVersion, 'MinorVersion');
  Assert.AreEqual(0, FHeaderInfo.PageSize, 'PageSize');
end;

procedure TFireBirdODSHeaderInfoTests.ODSVersionStr_IsEmpty_WhenUninitialized;
begin
  Assert.AreEqual('', FHeaderInfo.ODSVersionStr);
end;

procedure TFireBirdODSHeaderInfoTests.ODSVersionStr_Formats_AsMajorDotMinor;
begin
  FHeaderInfo.MajorVersion := 13;
  FHeaderInfo.MinorVersion := 1;

  Assert.AreEqual('13.1', FHeaderInfo.ODSVersionStr);
end;

procedure TFireBirdODSHeaderInfoTests.ToStrings_ContainsVersionAndPageSize;
var
  LStrings: TStringList;
begin
  FHeaderInfo.MajorVersion := 12;
  FHeaderInfo.MinorVersion := 0;
  FHeaderInfo.PageSize := 8192;

  LStrings := TStringList.Create;
  try
    FHeaderInfo.ToStrings(LStrings);

    Assert.AreEqual('ODS version = 12.0', LStrings[0]);
    Assert.AreEqual('Page size = 8192', LStrings[1]);
  finally
    LStrings.Free;
  end;
end;

{ TFirebirdODSHeaderReaderSyntheticTests }

procedure TFirebirdODSHeaderReaderSyntheticTests.Setup;
begin
  FReader := TFirebirdODSHeaderReader.Create;
  FCreatedFiles := TStringList.Create;
end;

procedure TFirebirdODSHeaderReaderSyntheticTests.TearDown;
var
  LFileName: string;
begin
  for LFileName in FCreatedFiles do
    if TFile.Exists(LFileName) then
      TFile.Delete(LFileName);

  FreeAndNil(FCreatedFiles);
  FreeAndNil(FReader);
end;

function TFirebirdODSHeaderReaderSyntheticTests.BuildHeader(const APageType: Byte; const APageSize, AEncodedOds: Word;
  const AByteAt20, AByteAt62, AByteAt64: Byte): TBytes;
begin
  SetLength(Result, HEADER_BUFFER_SIZE); // dynamic array is zero-initialised

  Result[0] := APageType;                         // pag_type
  Result[16] := Byte(APageSize and $FF);          // hdr_page_size (low byte)
  Result[17] := Byte((APageSize shr 8) and $FF);  // hdr_page_size (high byte)
  Result[18] := Byte(AEncodedOds and $FF);        // hdr_ods_version (low byte)
  Result[19] := Byte((AEncodedOds shr 8) and $FF);// hdr_ods_version (high byte, holds the Firebird flag)
  Result[20] := AByteAt20;                         // hdr_ods_minor for ODS 14
  Result[62] := AByteAt62;                         // hdr_cc  - deliberately NOT the minor version
  Result[64] := AByteAt64;                         // hdr_ods_minor for ODS 10..13
end;

function TFirebirdODSHeaderReaderSyntheticTests.WriteTempFile(const ABytes: TBytes): string;
begin
  Result := TPath.GetTempFileName; // creates a unique, empty file
  TFile.WriteAllBytes(Result, ABytes);
  FCreatedFiles.Add(Result);
end;

function TFirebirdODSHeaderReaderSyntheticTests.WriteHeaderFile(const APageType: Byte; const APageSize, AEncodedOds: Word;
  const AByteAt20, AByteAt62, AByteAt64: Byte): string;
begin
  Result := WriteTempFile(BuildHeader(APageType, APageSize, AEncodedOds, AByteAt20, AByteAt62, AByteAt64));
end;

procedure TFirebirdODSHeaderReaderSyntheticTests.Reads_Ods10_0_Firebird10;
var
  LFileName: string;
begin
  LFileName := WriteHeaderFile(PAGE_TYPE_HEADER, 4096, 10, 0, 0, 0);

  Assert.IsTrue(FReader.ReadHeader(LFileName), 'ReadHeader');
  Assert.AreEqual('10.0', FReader.ODSHeaderInfo.ODSVersionStr);
end;

procedure TFirebirdODSHeaderReaderSyntheticTests.Reads_Ods10_1_Firebird15;
var
  LFileName: string;
begin
  LFileName := WriteHeaderFile(PAGE_TYPE_HEADER, 4096, 10, 0, 0, 1);

  Assert.IsTrue(FReader.ReadHeader(LFileName), 'ReadHeader');
  Assert.AreEqual('10.1', FReader.ODSHeaderInfo.ODSVersionStr);
  Assert.AreEqual(10, FReader.ODSHeaderInfo.MajorVersion, 'MajorVersion');
  Assert.AreEqual(1, FReader.ODSHeaderInfo.MinorVersion, 'MinorVersion');
end;

procedure TFirebirdODSHeaderReaderSyntheticTests.Reads_Ods11_MinorFromOffset64_IgnoringHdrCcAtOffset62;
var
  LFileName: string;
begin
  // hdr_cc (offset 62) = 9, real hdr_ods_minor (offset 64) = 1. Must report 11.1.
  LFileName := WriteHeaderFile(PAGE_TYPE_HEADER, 4096, 11 or FIREBIRD_FLAG, 0, 9, 1);

  Assert.IsTrue(FReader.ReadHeader(LFileName), 'ReadHeader');
  Assert.AreEqual('11.1', FReader.ODSHeaderInfo.ODSVersionStr);
end;

procedure TFirebirdODSHeaderReaderSyntheticTests.Reads_Ods12_0;
var
  LFileName: string;
begin
  LFileName := WriteHeaderFile(PAGE_TYPE_HEADER, 8192, 12 or FIREBIRD_FLAG, 0, 0, 0);

  Assert.IsTrue(FReader.ReadHeader(LFileName), 'ReadHeader');
  Assert.AreEqual('12.0', FReader.ODSHeaderInfo.ODSVersionStr);
end;

procedure TFirebirdODSHeaderReaderSyntheticTests.Reads_Ods13_1;
var
  LFileName: string;
begin
  LFileName := WriteHeaderFile(PAGE_TYPE_HEADER, 8192, 13 or FIREBIRD_FLAG, 0, 0, 1);

  Assert.IsTrue(FReader.ReadHeader(LFileName), 'ReadHeader');
  Assert.AreEqual('13.1', FReader.ODSHeaderInfo.ODSVersionStr);
end;

procedure TFirebirdODSHeaderReaderSyntheticTests.Reads_Ods14_MinorFromOffset20_IgnoringOffset64;
var
  LFileName: string;
begin
  // For ODS 14 the minor version lives at offset 20; offset 64 must be ignored.
  LFileName := WriteHeaderFile(PAGE_TYPE_HEADER, 8192, 14 or FIREBIRD_FLAG, 1, 0, 9);

  Assert.IsTrue(FReader.ReadHeader(LFileName), 'ReadHeader');
  Assert.AreEqual('14.1', FReader.ODSHeaderInfo.ODSVersionStr);
end;

procedure TFirebirdODSHeaderReaderSyntheticTests.Reads_Ods14_0;
var
  LFileName: string;
begin
  LFileName := WriteHeaderFile(PAGE_TYPE_HEADER, 8192, 14 or FIREBIRD_FLAG, 0, 0, 0);

  Assert.IsTrue(FReader.ReadHeader(LFileName), 'ReadHeader');
  Assert.AreEqual('14.0', FReader.ODSHeaderInfo.ODSVersionStr);
end;

procedure TFirebirdODSHeaderReaderSyntheticTests.Reports_PageSize;
var
  LFileName: string;
begin
  LFileName := WriteHeaderFile(PAGE_TYPE_HEADER, 16384, 12 or FIREBIRD_FLAG, 0, 0, 0);

  Assert.IsTrue(FReader.ReadHeader(LFileName), 'ReadHeader');
  Assert.AreEqual(16384, FReader.ODSHeaderInfo.PageSize);
end;

procedure TFirebirdODSHeaderReaderSyntheticTests.RecognizedDatabase_IsFlaggedAsFirebird;
var
  LFileName: string;
begin
  LFileName := WriteHeaderFile(PAGE_TYPE_HEADER, 8192, 13 or FIREBIRD_FLAG, 0, 0, 0);

  Assert.IsTrue(FReader.ReadHeader(LFileName), 'ReadHeader');
  Assert.IsTrue(FReader.ODSHeaderInfo.IsFirebirdDatabase, 'IsFirebirdDatabase');
end;

procedure TFirebirdODSHeaderReaderSyntheticTests.Rejects_Ods11_WithoutFirebirdFlag;
var
  LFileName: string;
begin
  // ODS 11 without the Firebird flag is an InterBase database - not supported.
  LFileName := WriteHeaderFile(PAGE_TYPE_HEADER, 8192, 11, 0, 0, 1);

  Assert.IsFalse(FReader.ReadHeader(LFileName), 'ReadHeader');
  Assert.IsFalse(FReader.ODSHeaderInfo.IsFirebirdDatabase, 'IsFirebirdDatabase');
end;

procedure TFirebirdODSHeaderReaderSyntheticTests.Rejects_Ods12_WithoutFirebirdFlag;
var
  LFileName: string;
begin
  LFileName := WriteHeaderFile(PAGE_TYPE_HEADER, 8192, 12, 0, 0, 0);

  Assert.IsFalse(FReader.ReadHeader(LFileName), 'ReadHeader');
end;

procedure TFirebirdODSHeaderReaderSyntheticTests.Rejects_WhenPageTypeIsNotHeader;
var
  LFileName: string;
begin
  // pag_type 7 is not a header page, even though the version bytes look valid.
  LFileName := WriteHeaderFile(7, 8192, 13 or FIREBIRD_FLAG, 0, 0, 1);

  Assert.IsFalse(FReader.ReadHeader(LFileName), 'ReadHeader');
end;

procedure TFirebirdODSHeaderReaderSyntheticTests.Rejects_UnsupportedMajorVersion_TooHigh;
var
  LFileName: string;
begin
  LFileName := WriteHeaderFile(PAGE_TYPE_HEADER, 8192, 15 or FIREBIRD_FLAG, 0, 0, 0);

  Assert.IsFalse(FReader.ReadHeader(LFileName), 'ReadHeader');
end;

procedure TFirebirdODSHeaderReaderSyntheticTests.Rejects_UnsupportedMajorVersion_TooLow;
var
  LFileName: string;
begin
  LFileName := WriteHeaderFile(PAGE_TYPE_HEADER, 8192, 9 or FIREBIRD_FLAG, 0, 0, 0);

  Assert.IsFalse(FReader.ReadHeader(LFileName), 'ReadHeader');
end;

procedure TFirebirdODSHeaderReaderSyntheticTests.Rejects_FileShorterThanStaticHeader;
var
  LFileName: string;
  LBytes: TBytes;
begin
  LBytes := BuildHeader(PAGE_TYPE_HEADER, 8192, 13 or FIREBIRD_FLAG, 0, 0, 1);
  LFileName := WriteTempFile(Copy(LBytes, 0, 10)); // only 10 bytes, static header needs 20

  Assert.IsFalse(FReader.ReadHeader(LFileName), 'ReadHeader');
end;

procedure TFirebirdODSHeaderReaderSyntheticTests.Rejects_FileTooShortForMinorVersionOffset;
var
  LFileName: string;
  LBytes: TBytes;
begin
  // Static header (20 bytes) is present and decodes to ODS 13, but the file ends
  // before offset 64 where hdr_ods_minor would be.
  LBytes := BuildHeader(PAGE_TYPE_HEADER, 8192, 13 or FIREBIRD_FLAG, 0, 0, 1);
  LFileName := WriteTempFile(Copy(LBytes, 0, 64));

  Assert.IsFalse(FReader.ReadHeader(LFileName), 'ReadHeader');
end;

procedure TFirebirdODSHeaderReaderSyntheticTests.Rejects_EmptyFile;
var
  LFileName: string;
begin
  LFileName := WriteTempFile([]);

  Assert.IsFalse(FReader.ReadHeader(LFileName), 'ReadHeader');
end;

procedure TFirebirdODSHeaderReaderSyntheticTests.Rejects_NonExistentFile;
begin
  Assert.IsFalse(FReader.ReadHeader(TPath.Combine(TPath.GetTempPath, 'no_such_database_2f8c.fdb')));
end;

procedure TFirebirdODSHeaderReaderSyntheticTests.Reader_CanBeReused_WithoutLeakingState;
var
  LValidOds12: string;
  LValidOds10: string;
begin
  LValidOds12 := WriteHeaderFile(PAGE_TYPE_HEADER, 8192, 12 or FIREBIRD_FLAG, 0, 0, 0);
  LValidOds10 := WriteHeaderFile(PAGE_TYPE_HEADER, 4096, 10, 0, 0, 1);

  // 1) A valid ODS 12 database.
  Assert.IsTrue(FReader.ReadHeader(LValidOds12), 'first ReadHeader');
  Assert.AreEqual('12.0', FReader.ODSHeaderInfo.ODSVersionStr, 'first version');
  Assert.AreEqual(8192, FReader.ODSHeaderInfo.PageSize, 'first page size');

  // 2) A failing read must clear the previous result, including the page size.
  Assert.IsFalse(FReader.ReadHeader(TPath.Combine(TPath.GetTempPath, 'missing_af71.fdb')), 'missing ReadHeader');
  Assert.AreEqual('', FReader.ODSHeaderInfo.ODSVersionStr, 'version after failure');
  Assert.AreEqual(0, FReader.ODSHeaderInfo.PageSize, 'page size after failure');

  // 3) A different valid database reads correctly afterwards.
  Assert.IsTrue(FReader.ReadHeader(LValidOds10), 'third ReadHeader');
  Assert.AreEqual('10.1', FReader.ODSHeaderInfo.ODSVersionStr, 'third version');
  Assert.AreEqual(4096, FReader.ODSHeaderInfo.PageSize, 'third page size');
end;

{ TFirebirdODSHeaderReaderRealFileTests }

procedure TFirebirdODSHeaderReaderRealFileTests.Setup;
begin
  FReader := TFirebirdODSHeaderReader.Create;
  FindTestDataDir(FTestDataDir);
end;

procedure TFirebirdODSHeaderReaderRealFileTests.TearDown;
begin
  FreeAndNil(FReader);
end;

procedure TFirebirdODSHeaderReaderRealFileTests.Reads_ExpectedValues_FromRealDatabase(const ARelativePath,
  AExpectedOdsVersion: string; const AExpectedMajor, AExpectedMinor, AExpectedPageSize: Integer);
var
  LFileName: string;
begin
  if FTestDataDir.IsEmpty then
    Assert.Pass('TestData folder not found - real database tests skipped.');

  LFileName := TPath.Combine(FTestDataDir, ARelativePath);

  if not TFile.Exists(LFileName) then
    Assert.Pass('Sample database not present (Git LFS not pulled?): ' + ARelativePath);

  Assert.IsTrue(FReader.ReadHeader(LFileName), 'ReadHeader ' + ARelativePath);
  Assert.IsTrue(FReader.ODSHeaderInfo.IsFirebirdDatabase, 'IsFirebirdDatabase');
  Assert.AreEqual(AExpectedOdsVersion, FReader.ODSHeaderInfo.ODSVersionStr, 'ODSVersionStr');
  Assert.AreEqual(AExpectedMajor, FReader.ODSHeaderInfo.MajorVersion, 'MajorVersion');
  Assert.AreEqual(AExpectedMinor, FReader.ODSHeaderInfo.MinorVersion, 'MinorVersion');
  Assert.AreEqual(AExpectedPageSize, FReader.ODSHeaderInfo.PageSize, 'PageSize');
end;

end.
