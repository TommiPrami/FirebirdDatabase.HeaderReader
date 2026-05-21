program FirebirdDatabase.HeaderReader.Demo;

uses
  Vcl.Forms,
  FHRForm.DemoMain in 'FHRForm.DemoMain.pas' {FHRDemoMainForm},
  FHRUnit.HeaderReader in '..\Source\FHRUnit.HeaderReader.pas',
  FHRUnit.HeaderReader.Types in '..\Source\FHRUnit.HeaderReader.Types.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TFHRDemoMainForm, FHRDemoMainForm);
  Application.Run;
end.
