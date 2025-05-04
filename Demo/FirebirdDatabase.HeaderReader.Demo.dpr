program FirebirdDatabase.HeaderReader.Demo;

uses
  Vcl.Forms,
  FHRForm.DemoMain in 'FHRForm.DemoMain.pas' {Form35},
  FHRUnit.HeaderReader in '..\Source\FHRUnit.HeaderReader.pas',
  FHRUnit.HeaderReader.Types in '..\Source\FHRUnit.HeaderReader.Types.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TForm35, Form35);
  Application.Run;
end.
