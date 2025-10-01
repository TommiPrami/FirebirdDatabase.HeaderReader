## FirebirdDatabase.HeaderReader

Library to read Firebired DataBase headrer. Can get then PageSize and ODS version. Mainly used for getting ODS version, without opening the database connection.

###Basic usage of the class.
```Delphi
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

```

## Includes commad line tool FireBirdOdsVersionChecker.exe.

Simple command line tool for checking or oputputting ODS version

### Usage

FireBirdOdsVersionChecker.exe -DataBase:"<filename>" [-ParamExpectedOdsVersion:"13.0"]

- Parameters
  - DataBase: Filename, mandatory
    - if paramter does not exist gives ExitCode 2
  - ParamExpectedOdsVersion: string, if given must be full version, like "13.0"
    - if value given and it does not match one got from the database, ExithCode will be 1
  
If can't read Database or its ODS version, or file is not type of Firebired Database, then ExitCode will be 4. 
In case of unexcepted exception ExitCode will be 5.



