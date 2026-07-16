unit FHRTests.GStatDifferential;

// Differential tests: take a copy of a sample database, change what gfix can change,
// then check that the header reader reports exactly what that version's own
// "gstat -h" reports. gbak is used for the one setting gfix cannot touch - page size.
//
// These are the tests that would have caught reading hdr_ods_minor from the wrong
// offset: the shipped sample databases cannot tell 62 from 64 apart, but a database
// whose settings have actually been changed, checked against Firebird's own tool, can.
//
// Every test skips itself (reported as passed) when the Firebird distributions are
// not available, so the suite still runs on a machine without them.

interface

uses
  DUnitX.TestFramework, FHRTests.FirebirdTools, FHRUnit.HeaderReader, FHRUnit.HeaderReader.Types;

type
  [TestFixture]
  TGStatDifferentialTests = class
  strict private
    FReader: TFirebirdODSHeaderReader;
    function PrepareVersion(const AVersionCaption: string; out AInfo: TFirebirdVersionInfo;
      out ADistribution: TFirebirdDistribution): Boolean;
    procedure CompareAgainstGStat(const ADistribution: TFirebirdDistribution; const ADatabaseFileName: string;
      const AContext: string);
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    // Every combination of the header switches gfix can flip, per version.
    // Parameters: version, -write, -use, -mode.
    [Test]
    [TestCase('FB1.5 sync/full/rw',    'Firebird 1.5.x,sync,full,read_write')]
    [TestCase('FB1.5 async/reserve/ro','Firebird 1.5.x,async,reserve,read_only')]
    [TestCase('FB1.5 sync/reserve/rw', 'Firebird 1.5.x,sync,reserve,read_write')]
    [TestCase('FB1.5 async/full/ro',   'Firebird 1.5.x,async,full,read_only')]
    [TestCase('FB2.1 sync/full/rw',    'Firebird 2.1.x,sync,full,read_write')]
    [TestCase('FB2.1 async/reserve/ro','Firebird 2.1.x,async,reserve,read_only')]
    [TestCase('FB2.5 sync/full/rw',    'Firebird 2.5.x,sync,full,read_write')]
    [TestCase('FB2.5 async/reserve/ro','Firebird 2.5.x,async,reserve,read_only')]
    [TestCase('FB2.5 sync/reserve/rw', 'Firebird 2.5.x,sync,reserve,read_write')]
    [TestCase('FB2.5 async/full/ro',   'Firebird 2.5.x,async,full,read_only')]
    [TestCase('FB3.0 sync/full/rw',    'Firebird 3.0.x,sync,full,read_write')]
    [TestCase('FB3.0 async/reserve/ro','Firebird 3.0.x,async,reserve,read_only')]
    [TestCase('FB3.0 sync/reserve/rw', 'Firebird 3.0.x,sync,reserve,read_write')]
    [TestCase('FB3.0 async/full/ro',   'Firebird 3.0.x,async,full,read_only')]
    [TestCase('FB4.0 sync/full/rw',    'Firebird 4.0.x,sync,full,read_write')]
    [TestCase('FB4.0 async/reserve/ro','Firebird 4.0.x,async,reserve,read_only')]
    [TestCase('FB4.0 sync/reserve/rw', 'Firebird 4.0.x,sync,reserve,read_write')]
    [TestCase('FB4.0 async/full/ro',   'Firebird 4.0.x,async,full,read_only')]
    [TestCase('FB5.0 sync/full/rw',    'Firebird 5.0.x,sync,full,read_write')]
    [TestCase('FB5.0 async/reserve/ro','Firebird 5.0.x,async,reserve,read_only')]
    [TestCase('FB5.0 sync/reserve/rw', 'Firebird 5.0.x,sync,reserve,read_write')]
    [TestCase('FB5.0 async/full/ro',   'Firebird 5.0.x,async,full,read_only')]
    [TestCase('FB6.0 sync/full/rw',    'Firebird 6.0.x,sync,full,read_write')]
    [TestCase('FB6.0 async/reserve/ro','Firebird 6.0.x,async,reserve,read_only')]
    [TestCase('FB6.0 sync/reserve/rw', 'Firebird 6.0.x,sync,reserve,read_write')]
    [TestCase('FB6.0 async/full/ro',   'Firebird 6.0.x,async,full,read_only')]
    procedure MatchesGStat_ForEachGFixCombination(const AVersionCaption, AWriteMode, AUseMode, AAccessMode: string);

    // Page buffers is a plain number in the header, so check a couple of values.
    [Test]
    [TestCase('FB2.5 buffers 512',  'Firebird 2.5.x,512')]
    [TestCase('FB3.0 buffers 1024', 'Firebird 3.0.x,1024')]
    [TestCase('FB4.0 buffers 2048', 'Firebird 4.0.x,2048')]
    [TestCase('FB5.0 buffers 4096', 'Firebird 5.0.x,4096')]
    [TestCase('FB6.0 buffers 1024', 'Firebird 6.0.x,1024')]
    procedure MatchesGStat_ForPageBuffers(const AVersionCaption: string; const APageBuffers: Integer);

    // Page size can only be changed by a backup / restore cycle.
    [Test]
    [TestCase('FB3.0 page size 4096',  'Firebird 3.0.x,4096')]
    [TestCase('FB3.0 page size 16384', 'Firebird 3.0.x,16384')]
    [TestCase('FB4.0 page size 8192',  'Firebird 4.0.x,8192')]
    [TestCase('FB4.0 page size 32768', 'Firebird 4.0.x,32768')]
    [TestCase('FB5.0 page size 16384', 'Firebird 5.0.x,16384')]
    [TestCase('FB5.0 page size 32768', 'Firebird 5.0.x,32768')]
    procedure MatchesGStat_ForPageSizeAfterBackupRestore(const AVersionCaption: string; const APageSize: Integer);
  end;

implementation

uses
  System.SysUtils, System.IOUtils;

{ TGStatDifferentialTests }

procedure TGStatDifferentialTests.Setup;
begin
  FReader := TFirebirdODSHeaderReader.Create;
end;

procedure TGStatDifferentialTests.TearDown;
begin
  FreeAndNil(FReader);
end;

function TGStatDifferentialTests.PrepareVersion(const AVersionCaption: string; out AInfo: TFirebirdVersionInfo;
  out ADistribution: TFirebirdDistribution): Boolean;
begin
  Result := False;
  ADistribution := nil;

  if not TFirebirdTestEnvironment.Instance.IsAvailable then
  begin
    Assert.Pass('UnitTests\Firebird or UnitTests\TestData not found - differential tests skipped.');
    Exit;
  end;

  if not FirebirdVersionByCaption(AVersionCaption, AInfo) then
  begin
    Assert.Pass('Unknown Firebird version: ' + AVersionCaption);
    Exit;
  end;

  if not TFile.Exists(TFirebirdTestEnvironment.Instance.TestDataFileName(AInfo)) then
  begin
    Assert.Pass('Sample database missing (Git LFS not pulled?): ' + AInfo.TestDataRelPath);
    Exit;
  end;

  ADistribution := TFirebirdTestEnvironment.Instance.Distribution(AInfo);

  Result := True;
end;

// The heart of these tests: whatever gstat says, the reader must say too.
procedure TGStatDifferentialTests.CompareAgainstGStat(const ADistribution: TFirebirdDistribution;
  const ADatabaseFileName: string; const AContext: string);
var
  LGStat: TGStatHeaderInfo;
  LInfo: TFireBirdODSHeaderInfo;

  procedure CompareInt(const ACaption: string; const AGStatValue, AReaderValue: Int64);
  begin
    if AGStatValue = TGStatHeaderInfo.VALUE_NOT_PARSED then
      Exit; // gstat did not print this line for this version

    Assert.AreEqual(AGStatValue, AReaderValue, AContext + ' - ' + ACaption);
  end;

begin
  LGStat := ADistribution.ReadGStatHeader(ADatabaseFileName);

  Assert.IsTrue(FReader.ReadHeader(ADatabaseFileName), AContext + ' - ReadHeader');
  LInfo := FReader.ODSHeaderInfo;

  Assert.AreEqual(LGStat.ODSVersion, LInfo.ODSVersionStr, AContext + ' - ODS version');

  CompareInt('Flags', LGStat.Flags, LInfo.PageFlags);
  CompareInt('Generation', LGStat.Generation, LInfo.Generation);
  CompareInt('System Change Number', LGStat.SystemChangeNumber, LInfo.SystemChangeNumber);
  CompareInt('Page size', LGStat.PageSize, LInfo.PageSize);
  CompareInt('Oldest transaction', LGStat.OldestTransaction, LInfo.OldestTransaction);
  CompareInt('Oldest active', LGStat.OldestActive, LInfo.OldestActive);
  CompareInt('Oldest snapshot', LGStat.OldestSnapshot, LInfo.OldestSnapshot);
  CompareInt('Next transaction', LGStat.NextTransaction, LInfo.NextTransaction);
  CompareInt('Next attachment ID', LGStat.NextAttachmentID, LInfo.NextAttachmentID);
  CompareInt('Shadow count', LGStat.ShadowCount, LInfo.ShadowCount);
  CompareInt('Page buffers', LGStat.PageBuffers, LInfo.PageBuffers);
  CompareInt('Database dialect', LGStat.Dialect, LInfo.Dialect);

  // Sequence number is not printed by every gstat, and ODS 14 has no such field.
  if LInfo.SequenceNumber <> VALUE_NOT_AVAILABLE then
    CompareInt('Sequence number', LGStat.SequenceNumber, LInfo.SequenceNumber);

  Assert.AreEqual(LGStat.Attributes, LInfo.AttributesStr, AContext + ' - Attributes');
end;

procedure TGStatDifferentialTests.MatchesGStat_ForEachGFixCombination(const AVersionCaption, AWriteMode, AUseMode,
  AAccessMode: string);
var
  LInfo: TFirebirdVersionInfo;
  LDistribution: TFirebirdDistribution;
  LDatabaseFileName: string;
  LConnection: string;
  LTag: string;
begin
  if not PrepareVersion(AVersionCaption, LInfo, LDistribution) then
    Exit;

  LTag := AWriteMode + '_' + AUseMode + '_' + AAccessMode;
  LDatabaseFileName := LDistribution.PrepareDatabase(LTag);
  LConnection := LDistribution.ConnectionString(LDatabaseFileName);

  // read_only has to go last - a read only database will not accept further changes.
  LDistribution.RunToolChecked(ftkGFix, ['-user', 'SYSDBA', '-password', 'masterkey',
    '-write', AWriteMode, LConnection]);
  LDistribution.RunToolChecked(ftkGFix, ['-user', 'SYSDBA', '-password', 'masterkey',
    '-use', AUseMode, LConnection]);
  LDistribution.RunToolChecked(ftkGFix, ['-user', 'SYSDBA', '-password', 'masterkey',
    '-mode', AAccessMode, LConnection]);

  CompareAgainstGStat(LDistribution, LDatabaseFileName, AVersionCaption + ' ' + LTag);

  // gfix can report success and still change nothing - a missing ICU library made
  // exactly that happen. Without this the reader and gstat would simply agree on an
  // untouched database and the test would prove nothing, so check that the switches
  // really landed in the header.
  Assert.AreEqual(SameText(AWriteMode, 'sync'), fdaForceWrite in FReader.ODSHeaderInfo.Attributes,
    LTag + ' - gfix -write did not take effect');
  Assert.AreEqual(SameText(AUseMode, 'full'), fdaNoReserve in FReader.ODSHeaderInfo.Attributes,
    LTag + ' - gfix -use did not take effect');
  Assert.AreEqual(SameText(AAccessMode, 'read_only'), fdaReadOnly in FReader.ODSHeaderInfo.Attributes,
    LTag + ' - gfix -mode did not take effect');
end;

procedure TGStatDifferentialTests.MatchesGStat_ForPageBuffers(const AVersionCaption: string;
  const APageBuffers: Integer);
var
  LInfo: TFirebirdVersionInfo;
  LDistribution: TFirebirdDistribution;
  LDatabaseFileName: string;
begin
  if not PrepareVersion(AVersionCaption, LInfo, LDistribution) then
    Exit;

  LDatabaseFileName := LDistribution.PrepareDatabase('buffers' + APageBuffers.ToString);

  LDistribution.RunToolChecked(ftkGFix, ['-user', 'SYSDBA', '-password', 'masterkey',
    '-buffers', APageBuffers.ToString, LDistribution.ConnectionString(LDatabaseFileName)]);

  CompareAgainstGStat(LDistribution, LDatabaseFileName,
    AVersionCaption + ' buffers=' + APageBuffers.ToString);

  Assert.AreEqual(Int64(APageBuffers), FReader.ODSHeaderInfo.PageBuffers, 'PageBuffers actually changed');
end;

procedure TGStatDifferentialTests.MatchesGStat_ForPageSizeAfterBackupRestore(const AVersionCaption: string;
  const APageSize: Integer);
var
  LInfo: TFirebirdVersionInfo;
  LDistribution: TFirebirdDistribution;
  LSourceFileName: string;
  LBackupFileName: string;
  LRestoredFileName: string;
begin
  if not PrepareVersion(AVersionCaption, LInfo, LDistribution) then
    Exit;

  LSourceFileName := LDistribution.PrepareDatabase('ps' + APageSize.ToString + '_src');
  LBackupFileName := ChangeFileExt(LSourceFileName, '.fbk');
  LRestoredFileName := ChangeFileExt(LSourceFileName, '.restored.fdb');

  if TFile.Exists(LBackupFileName) then
    TFile.Delete(LBackupFileName);
  if TFile.Exists(LRestoredFileName) then
    TFile.Delete(LRestoredFileName);

  LDistribution.RunToolChecked(ftkGBak, ['-b', '-user', 'SYSDBA', '-password', 'masterkey',
    LDistribution.ConnectionString(LSourceFileName), LBackupFileName]);

  LDistribution.RunToolChecked(ftkGBak, ['-c', '-user', 'SYSDBA', '-password', 'masterkey',
    '-page_size', APageSize.ToString, LBackupFileName, LDistribution.ConnectionString(LRestoredFileName)]);

  CompareAgainstGStat(LDistribution, LRestoredFileName, AVersionCaption + ' page_size=' + APageSize.ToString);

  Assert.AreEqual(APageSize, FReader.ODSHeaderInfo.PageSize, 'PageSize actually changed');
end;

initialization

finalization
  TFirebirdTestEnvironment.ReleaseInstance;

end.
