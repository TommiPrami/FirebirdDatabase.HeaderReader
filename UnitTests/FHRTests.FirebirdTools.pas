unit FHRTests.FirebirdTools;

// Support code for the differential tests: drives a real Firebird distribution per
// version through gfix / gbak / isql, and parses "gstat -h" output so the header
// reader can be compared against what Firebird's own tools report.
//
// Everything comes from UnitTests\Firebird\<version>\ - the zips next to those
// folders are only kept for reference. Two ways of reaching a database are used:
//
//   Firebird 3.0+ - plugins\engine1x.dll makes embedded access work, so gfix is
//                   given the plain file name. It must also be given "-user SYSDBA"
//                   or it fails on a missing USE_GFIX_UTILITY system privilege.
//   Firebird 2.5- - no embedded engine exists, so fbserver.exe is started on a
//                   private port and gfix connects over localhost.
//
// A version folder is copied into the system temp folder before use: the legacy
// servers write to their security database, and the repository must stay clean.

interface

uses
  System.Classes, System.SysUtils, System.Generics.Collections;

type
  TFirebirdToolKind = (ftkGStat, ftkGFix, ftkGBak, ftkISql);

  TFirebirdVersionInfo = record
    Caption: string;          // 'Firebird 5.0.x'
    DistributionDir: string;  // version folder under UnitTests\Firebird
    ToolSubDir: string;       // where the exes live inside that folder ('' or 'bin')
    TestDataRelPath: string;
    NeedsServer: Boolean;     // True below Firebird 3.0 - no embedded engine
    ODSMajor: Integer;
    ODSMinor: Integer;
  end;

  // Values parsed out of "gstat -h". Unset entries stay at VALUE_NOT_PARSED so a
  // comparison can tell "gstat did not print this" from "gstat printed 0".
  TGStatHeaderInfo = record
  public
  const
    VALUE_NOT_PARSED = -2;
  public
    Attributes: string;
    Dialect: Int64;
    Flags: Int64;
    Generation: Int64;
    NextAttachmentID: Int64;
    NextTransaction: Int64;
    OldestActive: Int64;
    OldestSnapshot: Int64;
    OldestTransaction: Int64;
    ODSVersion: string;
    PageBuffers: Int64;
    PageSize: Int64;
    SequenceNumber: Int64;
    ShadowCount: Int64;
    SystemChangeNumber: Int64;

    procedure Clear;
  end;

  EFirebirdToolError = class(Exception);

  // One prepared Firebird distribution, plus the server process when one is needed.
  TFirebirdDistribution = class(TObject)
  strict private
    FInfo: TFirebirdVersionInfo;
    FRootDir: string;
    FServerHandle: THandle;
    FServerPort: Integer;
    function ToolFileName(const AKind: TFirebirdToolKind): string;
    procedure StartServer;
    procedure StopServer;
  public
    constructor Create(const AInfo: TFirebirdVersionInfo; const ARootDir: string);
    destructor Destroy; override;

    // Path as gfix / gbak must be given it - plain path when embedded, localhost
    // syntax when the version needs a server.
    function ConnectionString(const ADatabaseFileName: string): string;
    function RunTool(const AKind: TFirebirdToolKind; const AParameters: array of string;
      out AOutput: string): Integer;
    procedure RunToolChecked(const AKind: TFirebirdToolKind; const AParameters: array of string);
    function ReadGStatHeader(const ADatabaseFileName: string): TGStatHeaderInfo;
    // Creates an empty database with this version's own isql. Not used by the tests
    // below, but the tools are here and SQL driven checks may want it.
    procedure CreateDatabase(const ADatabaseFileName: string; const APageSize: Integer);
    // A fresh, writable copy of the sample database to work on.
    function PrepareDatabase(const ATag: string): string;

    property Info: TFirebirdVersionInfo read FInfo;
    property RootDir: string read FRootDir;
  end;

  TFirebirdTestEnvironment = class(TObject)
  strict private class var
    FInstance: TFirebirdTestEnvironment;
  strict private
    FDistributions: TObjectDictionary<string, TFirebirdDistribution>;
    FUnitTestsDir: string;
    FWorkDir: string;
    function ExtractDistribution(const AInfo: TFirebirdVersionInfo): string;
  public
    class function Instance: TFirebirdTestEnvironment;
    class procedure ReleaseInstance;

    constructor Create;
    destructor Destroy; override;

    function IsAvailable: Boolean;
    function Distribution(const AInfo: TFirebirdVersionInfo): TFirebirdDistribution;
    function TestDataFileName(const AInfo: TFirebirdVersionInfo): string;
    // Fresh, writable copy of the pristine sample database.
    function CopyTestDatabase(const AInfo: TFirebirdVersionInfo; const ATag: string): string;

    property UnitTestsDir: string read FUnitTestsDir;
    property WorkDir: string read FWorkDir;
  end;

function AllFirebirdVersions: TArray<TFirebirdVersionInfo>;
function FirebirdVersionByCaption(const ACaption: string; out AInfo: TFirebirdVersionInfo): Boolean;

implementation

uses
  Winapi.Windows, System.IOUtils, System.Zip, System.StrUtils;

const
  SERVER_START_PORT = 3055;
  SERVER_START_TIMEOUT_MS = 8000;
  TOOL_TIMEOUT_MS = 120000;

function AllFirebirdVersions: TArray<TFirebirdVersionInfo>;

  function Make(const ACaption, ADistributionDir, AToolSubDir, ATestDataRelPath: string;
    const ANeedsServer: Boolean; const AODSMajor, AODSMinor: Integer): TFirebirdVersionInfo;
  begin
    Result.Caption := ACaption;
    Result.DistributionDir := ADistributionDir;
    Result.ToolSubDir := AToolSubDir;
    Result.TestDataRelPath := ATestDataRelPath;
    Result.NeedsServer := ANeedsServer;
    Result.ODSMajor := AODSMajor;
    Result.ODSMinor := AODSMinor;
  end;

begin
  Result := [
    Make('Firebird 1.5.x', '1.5.6.5026', 'bin', 'fb15x\Employee_Fb1.5.6.fdb', True, 10, 1),
    Make('Firebird 2.1.x', '2.1.7.18553', 'bin', 'fb21x\Employee_Fb2.1.7.fdb', True, 11, 1),
    Make('Firebird 2.5.x', '2.5.9.27139', 'Bin', 'fb25x\Employee_Fb2.5.9.fdb', True, 11, 2),
    Make('Firebird 3.0.x', '3.0.14.33856', '', 'fb30x\Employee_Fb3.0.12.fdb', False, 12, 0),
    Make('Firebird 4.0.x', '4.0.7.3271', '', 'fb40x\Employee_Fb4.0.5.fdb', False, 13, 0),
    Make('Firebird 5.0.x', '5.0.4.1812', '', 'fb50x\Employee_Fb5.0.2.fdb', False, 13, 1),
    Make('Firebird 6.0.x', '6.0.0.2076', '', 'fb60x\Employee_Fb6.x.x.fdb', False, 14, 0)
  ];
end;

function FirebirdVersionByCaption(const ACaption: string; out AInfo: TFirebirdVersionInfo): Boolean;
var
  LInfo: TFirebirdVersionInfo;
begin
  for LInfo in AllFirebirdVersions do
    if SameText(LInfo.Caption, ACaption) then
    begin
      AInfo := LInfo;
      Exit(True);
    end;

  Result := False;
end;

// Runs a console tool and captures everything it writes, so gstat output can be
// parsed and gfix failures can be reported with their real message.
function RunProcessCaptured(const AExeFileName, ACommandLine, AWorkingDir: string; const ATimeOutMs: Cardinal;
  out AOutput: string): Integer;
var
  LSecurityAttributes: TSecurityAttributes;
  LStartupInfo: TStartupInfo;
  LProcessInfo: TProcessInformation;
  LReadPipe, LWritePipe: THandle;
  LCommandLine: string;
  LBuffer: TBytes;
  LBytesRead: DWORD;
  LAvailable: DWORD;
  LOutput: TStringBuilder;
  LExitCode: DWORD;
  LWaitResult: DWORD;
  LDone: Boolean;
begin
  FillChar(LSecurityAttributes, SizeOf(LSecurityAttributes), 0);
  LSecurityAttributes.nLength := SizeOf(LSecurityAttributes);
  LSecurityAttributes.bInheritHandle := True;

  if not CreatePipe(LReadPipe, LWritePipe, @LSecurityAttributes, 0) then
    raise EFirebirdToolError.Create('CreatePipe failed');

  LOutput := TStringBuilder.Create;
  try
    SetHandleInformation(LReadPipe, HANDLE_FLAG_INHERIT, 0);

    FillChar(LStartupInfo, SizeOf(LStartupInfo), 0);
    LStartupInfo.cb := SizeOf(LStartupInfo);
    LStartupInfo.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    LStartupInfo.wShowWindow := SW_HIDE;
    LStartupInfo.hStdOutput := LWritePipe;
    LStartupInfo.hStdError := LWritePipe;
    LStartupInfo.hStdInput := GetStdHandle(STD_INPUT_HANDLE);

    LCommandLine := '"' + AExeFileName + '" ' + ACommandLine;

    if not CreateProcess(nil, PChar(LCommandLine), nil, nil, True, CREATE_NO_WINDOW, nil,
      PChar(AWorkingDir), LStartupInfo, LProcessInfo) then
      raise EFirebirdToolError.Create('Could not start ' + AExeFileName + ': ' + SysErrorMessage(GetLastError));

    CloseHandle(LWritePipe);
    LWritePipe := 0;

    SetLength(LBuffer, 4096);
    LDone := False;
    try
      repeat
        // Drain whatever the tool has written so the pipe never fills up and blocks it.
        while PeekNamedPipe(LReadPipe, nil, 0, nil, @LAvailable, nil) and (LAvailable > 0) do
          if ReadFile(LReadPipe, LBuffer[0], Length(LBuffer), LBytesRead, nil) and (LBytesRead > 0) then
            LOutput.Append(TEncoding.ANSI.GetString(LBuffer, 0, LBytesRead))
          else
            Break;

        LWaitResult := WaitForSingleObject(LProcessInfo.hProcess, 50);
        LDone := LWaitResult = WAIT_OBJECT_0;
      until LDone or (WaitForSingleObject(LProcessInfo.hProcess, 0) = WAIT_FAILED);

      if not LDone then
        TerminateProcess(LProcessInfo.hProcess, 1);

      // Anything still buffered after the process ended.
      while PeekNamedPipe(LReadPipe, nil, 0, nil, @LAvailable, nil) and (LAvailable > 0) do
        if ReadFile(LReadPipe, LBuffer[0], Length(LBuffer), LBytesRead, nil) and (LBytesRead > 0) then
          LOutput.Append(TEncoding.ANSI.GetString(LBuffer, 0, LBytesRead))
        else
          Break;

      GetExitCodeProcess(LProcessInfo.hProcess, LExitCode);
      Result := Integer(LExitCode);
    finally
      CloseHandle(LProcessInfo.hThread);
      CloseHandle(LProcessInfo.hProcess);
    end;

    AOutput := LOutput.ToString;
  finally
    LOutput.Free;
    if LWritePipe <> 0 then
      CloseHandle(LWritePipe);
    CloseHandle(LReadPipe);
  end;
end;

{ TGStatHeaderInfo }

procedure TGStatHeaderInfo.Clear;
begin
  Attributes := '';
  Dialect := VALUE_NOT_PARSED;
  Flags := VALUE_NOT_PARSED;
  Generation := VALUE_NOT_PARSED;
  NextAttachmentID := VALUE_NOT_PARSED;
  NextTransaction := VALUE_NOT_PARSED;
  OldestActive := VALUE_NOT_PARSED;
  OldestSnapshot := VALUE_NOT_PARSED;
  OldestTransaction := VALUE_NOT_PARSED;
  ODSVersion := '';
  PageBuffers := VALUE_NOT_PARSED;
  PageSize := VALUE_NOT_PARSED;
  SequenceNumber := VALUE_NOT_PARSED;
  ShadowCount := VALUE_NOT_PARSED;
  SystemChangeNumber := VALUE_NOT_PARSED;
end;

{ TFirebirdDistribution }

constructor TFirebirdDistribution.Create(const AInfo: TFirebirdVersionInfo; const ARootDir: string);
begin
  inherited Create;

  FInfo := AInfo;
  FRootDir := ARootDir;
  FServerHandle := 0;
  FServerPort := 0;

  if FInfo.NeedsServer then
    StartServer;
end;

destructor TFirebirdDistribution.Destroy;
begin
  StopServer;

  inherited Destroy;
end;

function TFirebirdDistribution.ToolFileName(const AKind: TFirebirdToolKind): string;
const
  TOOL_EXE_NAMES: array [TFirebirdToolKind] of string = ('gstat.exe', 'gfix.exe', 'gbak.exe', 'isql.exe');
var
  LDir: string;
begin
  LDir := FRootDir;

  if not FInfo.ToolSubDir.IsEmpty then
    LDir := TPath.Combine(LDir, FInfo.ToolSubDir);

  Result := TPath.Combine(LDir, TOOL_EXE_NAMES[AKind]);
end;

procedure TFirebirdDistribution.StartServer;
var
  LStartupInfo: TStartupInfo;
  LProcessInfo: TProcessInformation;
  LCommandLine: string;
  LServerExe: string;
  LDir: string;
  LWaited: Integer;
  LOutput: string;
begin
  LDir := TPath.Combine(FRootDir, FInfo.ToolSubDir);
  LServerExe := TPath.Combine(LDir, 'fbserver.exe');

  if not TFile.Exists(LServerExe) then
    raise EFirebirdToolError.Create('Server not found for ' + FInfo.Caption + ': ' + LServerExe);

  // A private port keeps this away from any Firebird the machine already runs.
  FServerPort := SERVER_START_PORT + Ord(FInfo.ODSMajor) + FInfo.ODSMinor;

  FillChar(LStartupInfo, SizeOf(LStartupInfo), 0);
  LStartupInfo.cb := SizeOf(LStartupInfo);
  LStartupInfo.dwFlags := STARTF_USESHOWWINDOW;
  LStartupInfo.wShowWindow := SW_HIDE;

  LCommandLine := '"' + LServerExe + '" -a -p ' + FServerPort.ToString;

  if not CreateProcess(nil, PChar(LCommandLine), nil, nil, False, CREATE_NO_WINDOW, nil, PChar(LDir),
    LStartupInfo, LProcessInfo) then
    raise EFirebirdToolError.Create('Could not start server for ' + FInfo.Caption);

  CloseHandle(LProcessInfo.hThread);
  FServerHandle := LProcessInfo.hProcess;

  // Wait until it actually answers, rather than guessing with a fixed sleep.
  LWaited := 0;
  while LWaited < SERVER_START_TIMEOUT_MS do
  begin
    Sleep(250);
    Inc(LWaited, 250);

    if RunTool(ftkGFix, ['-user', 'SYSDBA', '-password', 'masterkey', '-h',
      'localhost/' + FServerPort.ToString + ':nonexistent_probe.fdb'], LOutput) <> 0 then
      // Any answer that is not a connection failure means the server is listening.
      if not ContainsText(LOutput, 'Unable to complete network request') then
        Exit;
  end;
end;

procedure TFirebirdDistribution.StopServer;
begin
  if FServerHandle = 0 then
    Exit;

  TerminateProcess(FServerHandle, 0);
  WaitForSingleObject(FServerHandle, 5000);
  CloseHandle(FServerHandle);
  FServerHandle := 0;
end;

function TFirebirdDistribution.ConnectionString(const ADatabaseFileName: string): string;
begin
  if FInfo.NeedsServer then
    Result := 'localhost/' + FServerPort.ToString + ':' + ADatabaseFileName
  else
    Result := ADatabaseFileName;
end;

function TFirebirdDistribution.RunTool(const AKind: TFirebirdToolKind; const AParameters: array of string;
  out AOutput: string): Integer;
var
  LCommandLine: string;
  LParameter: string;
  LDir: string;
begin
  LCommandLine := '';

  for LParameter in AParameters do
  begin
    if not LCommandLine.IsEmpty then
      LCommandLine := LCommandLine + ' ';

    if LParameter.Contains(' ') then
      LCommandLine := LCommandLine + '"' + LParameter + '"'
    else
      LCommandLine := LCommandLine + LParameter;
  end;

  LDir := FRootDir;
  if not FInfo.ToolSubDir.IsEmpty then
    LDir := TPath.Combine(LDir, FInfo.ToolSubDir);

  Result := RunProcessCaptured(ToolFileName(AKind), LCommandLine, LDir, TOOL_TIMEOUT_MS, AOutput);
end;

procedure TFirebirdDistribution.RunToolChecked(const AKind: TFirebirdToolKind; const AParameters: array of string);
const
  TOOL_CAPTIONS: array [TFirebirdToolKind] of string = ('gstat', 'gfix', 'gbak', 'isql');
var
  LOutput: string;
  LExitCode: Integer;
begin
  LExitCode := RunTool(AKind, AParameters, LOutput);

  if LExitCode <> 0 then
    raise EFirebirdToolError.CreateFmt('%s failed for %s (exit %d): %s',
      [TOOL_CAPTIONS[AKind], FInfo.Caption, LExitCode, LOutput.Trim]);
end;

function TFirebirdDistribution.ReadGStatHeader(const ADatabaseFileName: string): TGStatHeaderInfo;
var
  LOutput: string;
  LLine: string;
  LCaption: string;
  LValue: string;
  LExitCode: Integer;

  // gstat separates caption and value with runs of whitespace / tabs.
  function SplitCaptionAndValue(const ALine: string; out ACaption, AValue: string): Boolean;
  var
    LTrimmed: string;
    I: Integer;
  begin
    LTrimmed := ALine.Trim;
    Result := False;

    for I := 1 to Length(LTrimmed) - 1 do
      if (LTrimmed[I] = #9) or ((LTrimmed[I] = ' ') and (LTrimmed[I + 1] = ' ')) then
      begin
        ACaption := LTrimmed.Substring(0, I - 1).Trim;
        AValue := LTrimmed.Substring(I - 1).Trim;
        Exit(not ACaption.IsEmpty);
      end;

    // Captions with no value at all, e.g. an empty "Attributes" line.
    ACaption := LTrimmed;
    AValue := '';
    Result := not ACaption.IsEmpty;
  end;

  procedure AssignInt(const AText: string; var ATarget: Int64);
  var
    LParsed: Int64;
  begin
    if TryStrToInt64(AText.Trim, LParsed) then
      ATarget := LParsed;
  end;

begin
  Result.Clear;

  LExitCode := RunTool(ftkGStat, ['-h', ADatabaseFileName], LOutput);

  if LExitCode <> 0 then
    raise EFirebirdToolError.CreateFmt('gstat -h failed for %s (exit %d): %s',
      [FInfo.Caption, LExitCode, LOutput.Trim]);

  for LLine in LOutput.Split([sLineBreak, #10]) do
  begin
    if not SplitCaptionAndValue(LLine, LCaption, LValue) then
      Continue;

    if SameText(LCaption, 'Flags') then
      AssignInt(LValue, Result.Flags)
    else if SameText(LCaption, 'Generation') then
      AssignInt(LValue, Result.Generation)
    else if SameText(LCaption, 'System Change Number') then
      AssignInt(LValue, Result.SystemChangeNumber)
    else if SameText(LCaption, 'Page size') then
      AssignInt(LValue, Result.PageSize)
    else if SameText(LCaption, 'ODS version') then
      Result.ODSVersion := LValue
    else if SameText(LCaption, 'Oldest transaction') then
      AssignInt(LValue, Result.OldestTransaction)
    else if SameText(LCaption, 'Oldest active') then
      AssignInt(LValue, Result.OldestActive)
    else if SameText(LCaption, 'Oldest snapshot') then
      AssignInt(LValue, Result.OldestSnapshot)
    else if SameText(LCaption, 'Next transaction') then
      AssignInt(LValue, Result.NextTransaction)
    else if SameText(LCaption, 'Sequence number') then
      AssignInt(LValue, Result.SequenceNumber)
    else if SameText(LCaption, 'Next attachment ID') then
      AssignInt(LValue, Result.NextAttachmentID)
    else if SameText(LCaption, 'Shadow count') then
      AssignInt(LValue, Result.ShadowCount)
    else if SameText(LCaption, 'Page buffers') then
      AssignInt(LValue, Result.PageBuffers)
    else if SameText(LCaption, 'Database dialect') then
      AssignInt(LValue, Result.Dialect)
    else if SameText(LCaption, 'Attributes') then
      Result.Attributes := LValue;
  end;
end;

procedure TFirebirdDistribution.CreateDatabase(const ADatabaseFileName: string; const APageSize: Integer);
var
  LScriptFileName: string;
  LScript: string;
begin
  if TFile.Exists(ADatabaseFileName) then
    TFile.Delete(ADatabaseFileName);

  LScriptFileName := ADatabaseFileName + '.sql';

  LScript := 'CREATE DATABASE ' + QuotedStr(ConnectionString(ADatabaseFileName)) +
    ' PAGE_SIZE ' + APageSize.ToString + ' USER ' + QuotedStr('SYSDBA') +
    ' PASSWORD ' + QuotedStr('masterkey') + ';' + sLineBreak + 'QUIT;' + sLineBreak;

  TFile.WriteAllText(LScriptFileName, LScript, TEncoding.ANSI);
  try
    RunToolChecked(ftkISql, ['-q', '-i', LScriptFileName]);

    if not TFile.Exists(ADatabaseFileName) then
      raise EFirebirdToolError.Create('isql did not create ' + ADatabaseFileName);
  finally
    if TFile.Exists(LScriptFileName) then
      TFile.Delete(LScriptFileName);
  end;
end;

function TFirebirdDistribution.PrepareDatabase(const ATag: string): string;
begin
  Result := TFirebirdTestEnvironment.Instance.CopyTestDatabase(FInfo, ATag);
end;

{ TFirebirdTestEnvironment }

class function TFirebirdTestEnvironment.Instance: TFirebirdTestEnvironment;
begin
  if not Assigned(FInstance) then
    FInstance := TFirebirdTestEnvironment.Create;

  Result := FInstance;
end;

class procedure TFirebirdTestEnvironment.ReleaseInstance;
begin
  FreeAndNil(FInstance);
end;

constructor TFirebirdTestEnvironment.Create;

  // Walk up from the executable (and the current directory) looking for the folder
  // that holds both TestData and Firebird.
  function FindUnitTestsDir: string;

    function SearchUpwards(const AStartDir: string): string;
    var
      LDir: string;
      LLevel: Integer;
    begin
      Result := '';
      LDir := AStartDir;

      for LLevel := 0 to 8 do
      begin
        if LDir.IsEmpty then
          Break;

        if TDirectory.Exists(TPath.Combine(LDir, 'TestData')) and TDirectory.Exists(TPath.Combine(LDir, 'Firebird')) then
          Exit(LDir);

        LDir := TPath.GetDirectoryName(LDir);
      end;
    end;

  begin
    Result := SearchUpwards(TPath.GetDirectoryName(ParamStr(0)));

    if Result.IsEmpty then
      Result := SearchUpwards(TDirectory.GetCurrentDirectory);
  end;

begin
  inherited Create;

  FDistributions := TObjectDictionary<string, TFirebirdDistribution>.Create([doOwnsValues]);
  FUnitTestsDir := FindUnitTestsDir;

  FWorkDir := TPath.Combine(TPath.GetTempPath, 'FHRTests_' + GetCurrentProcessId.ToString);
  TDirectory.CreateDirectory(FWorkDir);
end;

destructor TFirebirdTestEnvironment.Destroy;
begin
  FDistributions.Free; // stops any servers

  try
    if TDirectory.Exists(FWorkDir) then
      TDirectory.Delete(FWorkDir, True);
  except
    // A leftover temp folder must never fail a test run.
  end;

  inherited Destroy;
end;

function TFirebirdTestEnvironment.IsAvailable: Boolean;
begin
  Result := not FUnitTestsDir.IsEmpty;
end;

function TFirebirdTestEnvironment.ExtractDistribution(const AInfo: TFirebirdVersionInfo): string;
var
  LSourceDir: string;
  LMarkerFileName: string;
  LSourceFileName: string;
  LTargetFileName: string;
begin
  // Copied rather than used in place: the legacy servers write to their security
  // database, and nothing here may dirty the repository. Cached per process.
  Result := TPath.Combine(FWorkDir, 'fb_' + AInfo.DistributionDir);
  LMarkerFileName := TPath.Combine(Result, '.prepared');

  if TFile.Exists(LMarkerFileName) then
    Exit;

  LSourceDir := TPath.Combine(TPath.Combine(FUnitTestsDir, 'Firebird'), AInfo.DistributionDir);

  if not TDirectory.Exists(LSourceDir) then
    raise EFirebirdToolError.Create('Firebird tools not found: ' + LSourceDir);

  TDirectory.CreateDirectory(Result);

  for LSourceFileName in TDirectory.GetFiles(LSourceDir, '*', TSearchOption.soAllDirectories) do
  begin
    LTargetFileName := TPath.Combine(Result, LSourceFileName.Substring(LSourceDir.Length + 1));
    TDirectory.CreateDirectory(TPath.GetDirectoryName(LTargetFileName));
    TFile.Copy(LSourceFileName, LTargetFileName, True);
    TFile.SetAttributes(LTargetFileName, []);
  end;

  TFile.WriteAllText(LMarkerFileName, 'ok');
end;

function TFirebirdTestEnvironment.Distribution(const AInfo: TFirebirdVersionInfo): TFirebirdDistribution;
var
  LDistribution: TFirebirdDistribution;
begin
  if FDistributions.TryGetValue(AInfo.Caption, Result) then
    Exit;

  LDistribution := TFirebirdDistribution.Create(AInfo, ExtractDistribution(AInfo));
  FDistributions.Add(AInfo.Caption, LDistribution);

  Result := LDistribution;
end;

function TFirebirdTestEnvironment.TestDataFileName(const AInfo: TFirebirdVersionInfo): string;
begin
  Result := TPath.Combine(TPath.Combine(FUnitTestsDir, 'TestData'), AInfo.TestDataRelPath);
end;

function TFirebirdTestEnvironment.CopyTestDatabase(const AInfo: TFirebirdVersionInfo; const ATag: string): string;
var
  LSourceFileName: string;
begin
  LSourceFileName := TestDataFileName(AInfo);

  Result := TPath.Combine(FWorkDir, AInfo.DistributionDir + '_' + ATag + '.fdb');

  TFile.Copy(LSourceFileName, Result, True);
  // The originals can be read-only in the repository, gfix must be able to write.
  TFile.SetAttributes(Result, []);
end;

end.
