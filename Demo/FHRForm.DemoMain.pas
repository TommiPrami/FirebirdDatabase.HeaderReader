unit FHRForm.DemoMain;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls;

type
  TSupportedFBVersion = (sfbvUnknown, sfbvFB10x, sfbvFB15x, sfbvFB20x, sfbvFB21x, sfbvFB25x, sfbvFB30x, sfbvFB40x,
    sfbvFB50x, sfbvFB60x);

  TForm35 = class(TForm)
    Panel1: TPanel;
    ButtonReadHeader: TButton;
    PanelClient: TPanel;
    MemoHeaderInfo: TMemo;
    PanelTop: TPanel;
    EditFirebirdDatabaseFilename: TEdit;
    ComboBoxFirebirdVersion: TComboBox;
    LabelDatabasePath: TLabel;
    procedure ButtonReadHeaderClick(Sender: TObject);
    procedure ComboBoxFirebirdVersionChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private
    procedure InitDBPath(const AFBVersion: TSupportedFBVersion);
    function ItemIndexToFirebirdVersion: TSupportedFBVersion;
    function GetODSVersionStrForFirebirdVersion(const AFBVersion: TSupportedFBVersion): string;
  end;

var
  Form35: TForm35;

implementation

{$R *.dfm}

uses
  FHRUnit.HeaderReader;

const
  DATABASE_PATH_PREFIX = '..\..\..\UnitTests\TestData\';

procedure RaiseUnkownOrUnsupportedFirebirdVersion;
begin
  raise Exception.Create('Unnown or unsupported Firebird version');
end;

procedure TForm35.ButtonReadHeaderClick(Sender: TObject);
var
  LHRaderReader: TFirebirdODSHeaderReader;
  LFirebierdVersion: TSupportedFBVersion;
  LODSVersionFromTheFile: string;
  LExpectedFirebirdVersionStr: string;
begin
  MemoHeaderInfo.Clear;
  LFirebierdVersion := ItemIndexToFirebirdVersion;
  LExpectedFirebirdVersionStr := GetODSVersionStrForFirebirdVersion(LFirebierdVersion);

  LHRaderReader := TFirebirdODSHeaderReader.Create;
  try
    if LHRaderReader.ReadHeader(EditFirebirdDatabaseFilename.Text) then
    begin
      LHRaderReader.ODSHeaderInfo.ToStrings(MemoHeaderInfo.Lines);
      LODSVersionFromTheFile := LHRaderReader.ODSHeaderInfo.ODSVersionStr;

      if LExpectedFirebirdVersionStr <> LODSVersionFromTheFile then
        MemoHeaderInfo.Font.Color := clMaroon
      else
        MemoHeaderInfo.Font.Color := clGreen;
    end;
  finally
    LHRaderReader.Free;
  end;
end;

procedure TForm35.ComboBoxFirebirdVersionChange(Sender: TObject);
begin
  InitDBPAth(ItemIndexToFirebirdVersion);
end;

procedure TForm35.FormCreate(Sender: TObject);
begin
  ComboBoxFirebirdVersion.ItemIndex := 0;

  ComboBoxFirebirdVersionChange(ComboBoxFirebirdVersion);
end;

function TForm35.GetODSVersionStrForFirebirdVersion(const AFBVersion: TSupportedFBVersion): string;
begin
  Result := '';

  case AFBVersion of
    sfbvFB10x: Result := '10.0';
    sfbvFB15x: Result := '10.1';
    sfbvFB20x: Result := '11.0';
    sfbvFB21x: Result := '11.1';
    sfbvFB25x: Result := '11.2';
    sfbvFB30x: Result := '12.0';
    sfbvFB40x: Result := '13.0';
    sfbvFB50x: Result := '13.1';
    sfbvFB60x: Result := '14.0';
    else
      RaiseUnkownOrUnsupportedFirebirdVersion;
  end;
end;

procedure TForm35.InitDBPath(const AFBVersion: TSupportedFBVersion);
var
  LDBPath: string;
begin
  case AFBVersion of
    sfbvFB25x: LDBPath := 'fb25x\Employee_Fb2.5.9.fdb';
    sfbvFB30x: LDBPath := 'fb30x\Employee_Fb3.0.12.fdb';
    sfbvFB40x: LDBPath := 'fb40x\Employee_Fb4.0.5.fdb';
    sfbvFB50x: LDBPath := 'fb50x\Employee_Fb5.0.2.fdb';
    sfbvFB60x: LDBPath := 'fb60x\Employee_Fb6.x.x.fdb';
    else
      RaiseUnkownOrUnsupportedFirebirdVersion;
  end;

  EditFirebirdDatabaseFilename.Text := DATABASE_PATH_PREFIX + LDBPath;

  if not FileExists(EditFirebirdDatabaseFilename.Text) then
    raise EFileNotFoundException.Create('Database file not found', EditFirebirdDatabaseFilename.Text);
end;

function TForm35.ItemIndexToFirebirdVersion: TSupportedFBVersion;
begin
  Result := sfbvUnknown;

  case ComboBoxFirebirdVersion.ItemIndex of
    0: Result := sfbvFB25x;
    1: Result := sfbvFB30x;
    2: Result := sfbvFB40x;
    3: Result := sfbvFB50x;
    4: Result := sfbvFB60x;
    else
      RaiseUnkownOrUnsupportedFirebirdVersion;
  end;
end;

end.
