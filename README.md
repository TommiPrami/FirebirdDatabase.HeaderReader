# FirebirdDatabase.HeaderReader

Library to read a Firebird database header. It can read the page size and the ODS
(On-Disk Structure) version. It is mainly used to get the ODS version *without*
opening a database connection - it only reads the first bytes of the file.

## Basic usage of the class

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

## Supported versions

| Firebird       | ODS version |
|----------------|-------------|
| 1.0.x          | 10.0        |
| 1.5.x          | 10.1        |
| 2.0.x          | 11.0        |
| 2.1.x          | 11.1        |
| 2.5.x          | 11.2        |
| 3.0.x          | 12.0        |
| 4.0.x          | 13.0        |
| 5.0.x          | 13.1        |
| 6.0.x          | 14.0        |

Firebird 2.0+ (ODS 11 and newer) sets a flag in the header that distinguishes its
on-disk structure from InterBase, so those databases are recognised unambiguously.
Firebird 1.0 / 1.5 (ODS 10) predate that flag; they share their format with
InterBase 6, so an ODS 10 file is read as Firebird even though it could technically
be an InterBase 6 database. InterBase 7+ (which reuses the ODS 11+ numbers *without*
the Firebird flag) is reported as *not a Firebird database*.

## Command line tool - FireBirdOdsVersionChecker.exe

Simple command line tool for printing, or verifying, the ODS version of a database.

### Usage

```
FireBirdOdsVersionChecker.exe -DataBase:"<filename>" [-ParamExpectedOdsVersion:"13.0"]
```

- `DataBase` (mandatory): the database file name.
- `ParamExpectedOdsVersion` (optional): if given, it must be the full ODS version,
  like `13.0`. When it does not match the version read from the database, the exit
  code is `1`.

### Exit codes

| Code | Meaning                                                                        |
|------|--------------------------------------------------------------------------------|
| 0    | Success. If an expected ODS version was given, it matched.                     |
| 1    | The expected ODS version did not match the one read from the database.         |
| 2    | The mandatory `DataBase` parameter was missing or empty.                       |
| 3    | The `DataBase` file does not exist.                                            |
| 4    | The file could not be read as a Firebird database - not a Firebird file, in use / locked, or the ODS version was not found. |
| 5    | An unexpected exception occurred.                                              |

## Tests

`UnitTests\FirebirdDatabase.HeaderReader.Tests.dproj` is a DUnitX project. It runs as
a console application out of the box (define `TESTINSIGHT` to use the IDE plugin
instead). It covers the header-info value object, hand-built headers for every
supported and rejected version, and the real sample databases under
`UnitTests\TestData` (those cases are skipped if the data is not present, e.g. Git
LFS was not pulled).
