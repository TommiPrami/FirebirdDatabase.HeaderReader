unit FHRForm.DemoMain;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls;

type
  TSupportedFBVersion = (sfbvUnknown, sfbvFB10x, sfbvFB15x, sfbvFB20x, sfbvFB21x, sfbvFB25x, sfbvFB30x, sfbvFB40x,
    sfbvFB50x, sfbvFB60x);

  TFHRDemoMainForm = class(TForm)
    ButtonReadHeader: TButton;
    ButtonRunAllTests: TButton;
    ComboBoxFirebirdVersion: TComboBox;
    EditFirebirdDatabaseFilename: TEdit;
    LabelDatabasePath: TLabel;
    MemoHeaderInfo: TMemo;
    PanelButtons: TPanel;
    PanelClient: TPanel;
    PanelTop: TPanel;
    procedure ButtonReadHeaderClick(Sender: TObject);
    procedure ButtonRunAllTestsClick(Sender: TObject);
    procedure ComboBoxFirebirdVersionChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private
    function GetODSVersionStrForFirebirdVersion(const AFBVersion: TSupportedFBVersion): string;
    function ItemIndexToFirebirdVersion: TSupportedFBVersion;
    procedure InitDBPath(const AFBVersion: TSupportedFBVersion);
    procedure ReadSelectedHeader;
  end;

var
  FHRDemoMainForm: TFHRDemoMainForm;

implementation

{$R *.dfm}

uses
  FHRUnit.HeaderReader;

const
  DATABASE_PATH_PREFIX = '..\..\..\UnitTests\TestData\';

procedure RaiseUnkownOrUnsupportedFirebirdVersion;
begin
  raise Exception.Create('Unknown or unsupported Firebird version');
end;

procedure TFHRDemoMainForm.ButtonReadHeaderClick(Sender: TObject);
begin
  MemoHeaderInfo.Clear;

  ReadSelectedHeader;
end;

procedure TFHRDemoMainForm.ButtonRunAllTestsClick(Sender: TObject);
begin
  MemoHeaderInfo.Clear;

  var LSelected := ComboBoxFirebirdVersion.ItemIndex;
  try
    for var LIndex := 0 to ComboBoxFirebirdVersion.ITems.Count - 1 do
    begin
      ComboBoxFirebirdVersion.ItemIndex := LIndex;

      ComboBoxFirebirdVersionChange(ComboBoxFirebirdVersion);

      ReadSelectedHeader;
    end;
  finally
    ComboBoxFirebirdVersion.ItemIndex := LSelected;
  end;

end;

procedure TFHRDemoMainForm.ComboBoxFirebirdVersionChange(Sender: TObject);
begin
  InitDBPAth(ItemIndexToFirebirdVersion);
end;

procedure TFHRDemoMainForm.FormCreate(Sender: TObject);
begin
  ComboBoxFirebirdVersion.ItemIndex := 0;

  ComboBoxFirebirdVersionChange(ComboBoxFirebirdVersion);
end;

function TFHRDemoMainForm.GetODSVersionStrForFirebirdVersion(const AFBVersion: TSupportedFBVersion): string;
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

procedure TFHRDemoMainForm.InitDBPath(const AFBVersion: TSupportedFBVersion);
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

function TFHRDemoMainForm.ItemIndexToFirebirdVersion: TSupportedFBVersion;
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

procedure TFHRDemoMainForm.ReadSelectedHeader;
var
  LHeaderReader: TFirebirdODSHeaderReader;
  LFirebirdVersion: TSupportedFBVersion;
  LODSVersionFromTheFile: string;
  LExpectedFirebirdVersionStr: string;
begin
  LFirebirdVersion := ItemIndexToFirebirdVersion;
  LExpectedFirebirdVersionStr := GetODSVersionStrForFirebirdVersion(LFirebirdVersion);

  LHeaderReader := TFirebirdODSHeaderReader.Create;
  try
    if LHeaderReader.ReadHeader(EditFirebirdDatabaseFilename.Text) then
    begin
      LHeaderReader.ODSHeaderInfo.ToStrings(MemoHeaderInfo.Lines);
      LODSVersionFromTheFile := LHeaderReader.ODSHeaderInfo.ODSVersionStr;

      if LExpectedFirebirdVersionStr <> LODSVersionFromTheFile then
        MemoHeaderInfo.Font.Color := clMaroon
      else
        MemoHeaderInfo.Font.Color := clGreen;
    end;
  finally
    LHeaderReader.Free;
  end;

end;

end.
