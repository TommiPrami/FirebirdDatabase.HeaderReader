# FirebirdDatabase.HeaderReader

Library to read a Firebird database header page. It reports most of what
`gstat -h` prints - ODS version, page size, transaction counters, page buffers,
attributes and so on - *without* opening a database connection, by reading only the
first bytes of the file.

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

`ReadHeader` returns `False` - it does not raise - when the file is missing, is not
a Firebird database, or cannot be opened because a running server holds it locked.

## Header information

`ODSHeaderInfo` exposes the decoded header page; `ToStrings` renders it as a
`gstat -h` style report.

| Property | `gstat -h` line | Notes |
|--------------------------|------------------------|--------------------------------------|
| `PageFlags`              | Flags                  | `pag_flags`, not `hdr_flags`         |
| `Generation`             | Generation             |                                      |
| `SystemChangeNumber`     | System Change Number   |                                      |
| `PageSize`               | Page size              |                                      |
| `MajorVersion`/`MinorVersion`/`ODSVersionStr` | ODS version |                        |
| `OldestTransaction`      | Oldest transaction     |                                      |
| `OldestActive`           | Oldest active          |                                      |
| `OldestSnapshot`         | Oldest snapshot        |                                      |
| `NextTransaction`        | Next transaction       |                                      |
| `SequenceNumber`         | Sequence number        | not in ODS 14                        |
| `NextAttachmentID`       | Next attachment ID     |                                      |
| `ShadowCount`            | Shadow count           |                                      |
| `PageBuffers`            | Page buffers           |                                      |
| `NextHeaderPage`         | Next header page       | not in ODS 14                        |
| `Dialect`                | Database dialect       |                                      |
| `CreationDate`           | Creation date          | `TDateTime`                          |
| `Attributes`/`AttributesStr` | Attributes         | force write, read only, shutdown, .. |

Transaction counters and the attachment id are 64 bit: ODS 12/13 store the high
words separately and they are combined here, ODS 14 stores them as native 64 bit
values.

Fields a given ODS generation does not have report `VALUE_NOT_AVAILABLE` (`-1`), and
`ToStrings` prints them as `n/a`. The Database GUID and sweep interval live in the
variable part of the header page and are not parsed (yet).

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
