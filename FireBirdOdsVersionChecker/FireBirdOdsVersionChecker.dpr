program FireBirdOdsVersionChecker;

{$APPTYPE CONSOLE}

// Disable the "new" RTTI to make exe smaller
{$WEAKLINKRTTI ON}

{$IF DECLARED(TVisibilityClasses)}
  {$RTTI EXPLICIT METHODS([]) PROPERTIES([]) FIELDS([])}
{$ENDIF}

{$R *.res}

uses
  System.SysUtils,
  FHRUnit.HeaderReader in '..\Source\FHRUnit.HeaderReader.pas',
  FHRUnit.HeaderReader.Types in '..\Source\FHRUnit.HeaderReader.Types.pas';

const
  EXIT_CODE_ODS_DOES_NOT_MATCH = 1;
  EXIT_CODE_PARAM_NOT_FOUND = 2;
  EXIT_CODE_PARAM_VALUE_ERROR = 3;
  EXIT_CODE_FILE_NOT_DATABASE = 4;
  EXIT_CODE_EXCEPTION = 5;

function GetCmdLineSwitch(const ASwitchName: string; var ASwitchValue: string; const AParamIsMandatory: Boolean = True): Boolean;
begin
  Result := FindCmdLineSwitch(ASwitchName, ASwitchValue);

  Result := Result and not ASwitchValue.IsEmpty;

  if not Result and AParamIsMandatory then
  begin
    Writeln('Parameter ' + ASwitchName.QuotedString('"') + ' not found or don''t have value');
    ExitCode := EXIT_CODE_PARAM_NOT_FOUND;
  end;
end;

procedure SetParamValueError(const AParamName, AErrorSuffix: string);
begin
  Writeln('Error in Parameter ' + AParamName.QuotedString('"') + ' - ' + AErrorSuffix);
  ExitCode := EXIT_CODE_PARAM_VALUE_ERROR;
end;

procedure WriteOdsVersionText(const ADataBaseOdsVersion: string);
begin
  Writeln('DataBase ODS Version: ' + ADataBaseOdsVersion.QuotedString('"'));
end;

function GetDBOdsVersion(const ADataBaseFileName: string; var AODSVersion: string): Boolean;
begin
  var LHeaderReader := TFirebirdODSHeaderReader.Create;
  try
    Result := LHeaderReader.ReadHeader(ADataBaseFileName);

    if Result then
      AODSVersion := LHeaderReader.ODSHeaderInfo.ODSVersionStr;
  finally
    LHeaderReader.Free;
  end;
end;

const
  PARAM_DATABASE = 'DataBase';
  PARAM_EXPECTED_ODS_VERSION = 'ParamExpectedOdsVersion';
begin
  try
    var LDataBase: string;
    if not GetCmdLineSwitch(PARAM_DATABASE, LDataBase) then
      Exit;

    if not FileExists(LDataBase) then
    begin
      SetParamValueError(PARAM_DATABASE, 'DataBase does not exists');
      Exit;
    end;

    var LParamExpectedOdsVersionStr: string;
    GetCmdLineSwitch(PARAM_EXPECTED_ODS_VERSION, LParamExpectedOdsVersionStr, False);

    var LDataBaseOdsVersion: string;

    if GetDBOdsVersion(LDataBase, LDataBaseOdsVersion) then
    begin
      if LParamExpectedOdsVersionStr.IsEmpty then
        WriteOdsVersionText(LDataBaseOdsVersion)
      else
      begin
        WriteOdsVersionText(LDataBaseOdsVersion);

        if not SameText(LParamExpectedOdsVersionStr, LDataBaseOdsVersion) then
        begin
          WriteLn('  - Error: ODS versions don''t match, expected ' + LParamExpectedOdsVersionStr.QuotedString('"')
            + ' but got ' + LDataBaseOdsVersion.QuotedString('"'));

          ExitCode := EXIT_CODE_ODS_DOES_NOT_MATCH;
          Exit;
        end;
      end;
    end
    else
    begin
      ExitCode := EXIT_CODE_FILE_NOT_DATABASE;
      Exit;
    end;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := EXIT_CODE_EXCEPTION;
    end;
  end;
end.

