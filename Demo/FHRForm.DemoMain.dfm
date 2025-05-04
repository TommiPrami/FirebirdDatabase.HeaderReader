object Form35: TForm35
  Left = 0
  Top = 0
  Caption = 'Form35'
  ClientHeight = 441
  ClientWidth = 720
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  OnCreate = FormCreate
  TextHeight = 15
  object Panel1: TPanel
    Left = 583
    Top = 0
    Width = 137
    Height = 441
    Align = alRight
    BevelOuter = bvNone
    ShowCaption = False
    TabOrder = 0
    object ButtonReadHeader: TButton
      AlignWithMargins = True
      Left = 3
      Top = 3
      Width = 131
      Height = 25
      Align = alTop
      Caption = 'Read Header'
      TabOrder = 0
      OnClick = ButtonReadHeaderClick
    end
  end
  object PanelClient: TPanel
    Left = 0
    Top = 0
    Width = 583
    Height = 441
    Align = alClient
    BevelOuter = bvNone
    ShowCaption = False
    TabOrder = 1
    object MemoHeaderInfo: TMemo
      Left = 0
      Top = 121
      Width = 583
      Height = 320
      Align = alClient
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -15
      Font.Name = 'Courier New'
      Font.Style = []
      ParentFont = False
      TabOrder = 0
    end
    object PanelTop: TPanel
      Left = 0
      Top = 0
      Width = 583
      Height = 121
      Align = alTop
      BevelOuter = bvNone
      ShowCaption = False
      TabOrder = 1
      object LabelDatabasePath: TLabel
        AlignWithMargins = True
        Left = 3
        Top = 74
        Width = 577
        Height = 15
        Align = alBottom
        Caption = 'Label Database Path'
      end
      object EditFirebirdDatabaseFilename: TEdit
        AlignWithMargins = True
        Left = 3
        Top = 95
        Width = 577
        Height = 23
        Align = alBottom
        TabOrder = 0
        Text = '..\..\..\UnitTests\TestData\fb25x\EMPLOYEE_Fb259.fdb'
      end
      object ComboBoxFirebirdVersion: TComboBox
        AlignWithMargins = True
        Left = 3
        Top = 45
        Width = 577
        Height = 23
        Align = alBottom
        Style = csDropDownList
        ItemIndex = 0
        TabOrder = 1
        Text = 'Firebird 2.5.x'
        OnChange = ComboBoxFirebirdVersionChange
        Items.Strings = (
          'Firebird 2.5.x'
          'Firebird 3.0.x'
          'Firebird 4.0.x'
          'Firebird 5.0.x'
          'Firebird 6.0.x')
      end
    end
  end
end
