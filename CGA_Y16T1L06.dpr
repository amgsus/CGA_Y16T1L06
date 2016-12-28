program CGA_Y16T1L06;

uses
  Forms,
  frmMain in 'frmMain.pas' {MainForm};

{$R *.res}

var
  MainForm: TMainForm;

begin
  Application.Initialize;
  Application.Title := 'CGA_Y16T1L06';
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
