unit frmMain;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, ExtCtrls, Menus, dglOpenGL, PngImageList, pngimage;

type
  TVec3f = array [0..3] of Single;

  TMainForm = class(TForm)
    RenderTimer: TTimer;
    OpenGLPopup: TPopupMenu;
    RenderPanel: TPanel;
    TexturePngCollection: TPngImageCollection;
    Textures2DMenuItem: TMenuItem;
    Light0MenuItem: TMenuItem;
    LightningMenuItem: TMenuItem;
    Skin1: TMenuItem;
    Skin1MenuItem: TMenuItem;
    Skin2MenuItem: TMenuItem;
    N1: TMenuItem;
    N2: TMenuItem;
    RenderAxisMenuItem: TMenuItem;
    errain1: TMenuItem;
    PanoramaMenuItem: TMenuItem;
    GroundMenuItem: TMenuItem;
    TerrainMenuItem: TMenuItem;
    N3: TMenuItem;
    TimerMenuItem: TMenuItem;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure RenderTimerEvent(Sender: TObject);
    procedure FormActivate(Sender: TObject);
    procedure FormResize(Sender: TObject);
    procedure FormKeyUp(Sender: TObject; var Key: Word;
      Shift: TShiftState);
    procedure Textures2DMenuItemClick(Sender: TObject);
    procedure Light0MenuItemClick(Sender: TObject);
    procedure LightningMenuItemClick(Sender: TObject);
    procedure Skin1MenuItemClick(Sender: TObject);
    procedure RenderPanelMouseMove(Sender: TObject; Shift: TShiftState; X,
      Y: Integer);
    procedure RenderPanelMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure RenderPanelMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure TimerMenuItemClick(Sender: TObject);
  private
    // ...
    ContextDC: HDC;
    RenderContext: HGLRC;
    AngleY: Single;
    AngleX: Single;
    CameraPosZ: Single;
    TexFace: array [0..5] of GLuint;
    TexBody: array [0..5] of GLuint;
    TexLArm: array [0..5] of GLuint;
    TexRArm: array [0..5] of GLuint;
    TexLLeg: array [0..5] of GLuint;
    TexRLeg: array [0..5] of GLuint;
    TexPanorama: array [0..5] of GLuint;
    TexBlockGrass: array [0..5] of GLuint;
    SkinTextureIndex: Integer;
    MouseDown: Boolean;
    MouseDownPosX: Integer;
    MouseDownPosY: Integer;
    LastAngleY: Single;
    LastAngleX: Single;
    ArmAngle: Single;
    LegAngle: Single;
    AnimationCircleAngle: Integer;
    Rotating: Boolean;
    StepZ: Single;
  protected
    procedure DoAnimation;
    procedure DoRender;
    procedure DoSceneResize;
    procedure R_Prepare;
    procedure DoOnIdle(Sender: TObject; var Done: Boolean);
    procedure PrepareTexture;
    procedure RenderPanorama;
    procedure RenderTerrain;
  end;

var
  P_APPTITLE: PChar;

implementation

{$R *.dfm}

uses
  Math, Types;

const
  R_FOV         : Double = 65.0;
  R_FAR_CLIP    : Double = 1000.0;
  R_NEAR_CLIP   : Double = 0.1;
  R_CLEARCOLOR  : TColor = $00F0F0F0;

  T_TOP     = 0;
  T_BOTTOM  = 1;
  T_FRONT   = 2;
  T_BACK    = 3;
  T_LEFT    = 4;
  T_RIGHT   = 5;

  SKIN_TEXTURE_W = 64;
  SKIN_TEXTURE_H = 32;

  BLOCK_TEXTURE_MAP_W = 64;
  BLOCK_TEXTURE_MAP_H = 16;

function GL_LoadTextureFromBuffer(const Width, Height: Integer;
  pData: Pointer): GLuint;
begin
  glGenTextures(1, @Result);
  glBindTexture(GL_TEXTURE_2D, Result);

  glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);

  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);

  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);

  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, Width, Height, 0, GL_RGB,
    GL_UNSIGNED_BYTE, pData);
end;

function TextureFragment(pMapTexture: Pointer; OffsetX, OffsetY, FragW, FragH,
  MapW, MapH: Cardinal): Pointer;
var
  Pixel: PByteArray;
  DestPixel: PByteArray;
  i: Integer;
  SrcOffset: Integer;
  DstOffset: Integer;
begin
  GetMem(Result, FragW * FragH * 3);

  Pixel := pMapTexture;
  DestPixel := Result;

  SrcOffset := OffsetY * MapW + OffsetX;
  DstOffset := 0;

  for i := 0 to FragH - 1 do
  begin
    CopyMemory(@DestPixel[DstOffset * 3], @Pixel[SrcOffset * 3], FragW * 3);
    
    Inc(DstOffset, FragW);
    Inc(SrcOffset, MapW);
  end;
end;

{ TMainForm }

procedure TMainForm.DoRender;
const
  L0_AMBIENT:  array [0..3] of Single = (0.1, 0.1, 0.1, 1.0);
  L0_DIFFUSE:  array [0..3] of Single = (1.0, 1.0, 1.0, 1.0);
  L0_SPECULAR: array [0..3] of Single = (1.0, 1.0, 1.0, 1.0);
  
  L0_POS: array [0..3] of Single = (0, 1.8, 1.5, 1.0);

  { Obsidian }
  M_AMBIENT : TVector4f = (0.05375, 0.05, 0.06625, 1.0);
  M_DIFFUSE : TVector4f = (0.18275, 0.17, 0.22525, 1.0);
  M_SPECULAR: TVector4f = (0.332741, 0.328634, 0.346435, 1.0);
begin
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT);

  DoSceneResize;

  glLoadIdentity();

  gluLookAt(1.50, 4.00, CameraPosZ, 0, 0, 0, 0, 1, 0);

  glLightfv(GL_LIGHT0, GL_POSITION, @L0_POS);
  glLightfv(GL_LIGHT0, GL_AMBIENT, @L0_AMBIENT);
  glLightfv(GL_LIGHT0, GL_DIFFUSE, @L0_DIFFUSE);
  // glLightfv(GL_LIGHT0, GL_SPECULAR, @L0_SPECULAR);

  glRotatef(-AngleY, 0.0, 1.0, 0.0);
  glRotatef(-AngleX, 1.0, 0.0, 0.0);

  {
    glBindTexture(...);
    Renderer.Normal(Nx, Ny, Nz);
    Renderer.VertexUV(X, Y, Z, U, V);
    Renderer.Render();

    CubeRenderer.Center(X, Y, Z);
    CubeRenderer.Size(W, H, D);
    CubeRenderer.Draw();
  }

  glBindTexture(GL_TEXTURE_2D, 0);

  // Axis //

  if RenderAxisMenuItem.Checked then
  begin
    glBegin(GL_LINES);
      glColor3f (1.0, 0.0, 0.0); // Red
      glVertex3f(0.0, 0.0, 0.0);
      glVertex3f(1.0, 0.0, 0.0); // X

      glColor3f (0.0, 1.0, 0.0); // Green
      glVertex3f(0.0, 0.0, 0.0);
      glVertex3f(0.0, 1.0, 0.0); // Y

      glColor3f (0.0, 0.0, 1.0); // Blue
      glVertex3f(0.0, 0.0, 0.0);
      glVertex3f(0.0, 0.0, 1.0); // Z
    glEnd();
  end;

  glMaterialfv(GL_FRONT, GL_AMBIENT, @M_AMBIENT);
  glMaterialfv(GL_FRONT, GL_DIFFUSE, @M_DIFFUSE);
  glMaterialfv(GL_FRONT, GL_SPECULAR, @M_SPECULAR);
  glMaterialf (GL_FRONT, GL_SHININESS, 0.3 * 128);

  glColor4f(1.0, 1.0, 1.0, 1.0);

  // Panorama //

  if GroundMenuItem.Checked then
    RenderTerrain
  else if PanoramaMenuItem.Checked then
    RenderPanorama;

  // Render Head //

  glPushMatrix(); // Man..

  glTranslatef(0.0, 1.00, 0.0);

  glPushMatrix();

  glBindTexture(GL_TEXTURE_2D, TexFace[T_TOP]);

  glTranslatef(0.0, 1.25, 0.0);

  glBegin(GL_QUADS);
    glNormal3f( 0.0,  1.0,  0.0); // Top
    glTexCoord2f(1.0, 0.0);
    glVertex3f( 0.5,  0.5, -0.5);
    glTexCoord2f(0.0, 0.0);
    glVertex3f(-0.5,  0.5, -0.5);
    glTexCoord2f(0.0, 1.0);
    glVertex3f(-0.5,  0.5,  0.5);
    glTexCoord2f(1.0, 1.0);
    glVertex3f( 0.5,  0.5,  0.5);
  glEnd();

  glBindTexture(GL_TEXTURE_2D, TexFace[T_BOTTOM]);

  glBegin(GL_QUADS);
    glNormal3f( 0.0, -1.0,  0.0); // Bottom
    glTexCoord2f(1.0, 0.0);
    glVertex3f( 0.5, -0.5,  0.5);
    glTexCoord2f(0.0, 0.0);
    glVertex3f(-0.5, -0.5,  0.5);
    glTexCoord2f(0.0, 1.0);
    glVertex3f(-0.5, -0.5, -0.5);
    glTexCoord2f(1.0, 1.0);
    glVertex3f( 0.5, -0.5, -0.5);
  glEnd();

  glBindTexture(GL_TEXTURE_2D, TexFace[T_FRONT]);

  glBegin(GL_QUADS);
    glNormal3f( 0.0,  0.0,  1.0); // Front
    glTexCoord2f(1.0, 0.0);
    glVertex3f( 0.5,  0.5,  0.5);
    glTexCoord2f(0.0, 0.0);
    glVertex3f(-0.5,  0.5,  0.5);
    glTexCoord2f(0.0, 1.0);
    glVertex3f(-0.5, -0.5,  0.5);
    glTexCoord2f(1.0, 1.0);
    glVertex3f( 0.5, -0.5,  0.5);
  glEnd();

  glBindTexture(GL_TEXTURE_2D, TexFace[T_BACK]);

  glBegin(GL_QUADS);
    glNormal3f( 0.0,  0.0, -1.0); // Back
    glTexCoord2f(0.0, 1.0);
    glVertex3f( 0.5, -0.5, -0.5);
    glTexCoord2f(1.0, 1.0);
    glVertex3f(-0.5, -0.5, -0.5);
    glTexCoord2f(1.0, 0.0);
    glVertex3f(-0.5,  0.5, -0.5);
    glTexCoord2f(0.0, 0.0);
    glVertex3f( 0.5,  0.5, -0.5);
  glEnd();

  glBindTexture(GL_TEXTURE_2D, TexFace[T_LEFT]);

  glBegin(GL_QUADS);
    glNormal3f(-1.0,  0.0,  0.0); // Left
    glTexCoord2f(0.0, 0.0);
    glVertex3f(-0.5,  0.5,  0.5);
    glTexCoord2f(1.0, 0.0);
    glVertex3f(-0.5,  0.5, -0.5);
    glTexCoord2f(1.0, 1.0);
    glVertex3f(-0.5, -0.5, -0.5);
    glTexCoord2f(0.0, 1.0);
    glVertex3f(-0.5, -0.5,  0.5);
  glEnd();

  glBindTexture(GL_TEXTURE_2D, TexFace[T_RIGHT]);

  glBegin(GL_QUADS);
    glNormal3f( 1.0,  0.0,  0.0); // Right
    glTexCoord2f(0.0, 0.0);
    glVertex3f( 0.5,  0.5, -0.5);
    glTexCoord2f(1.0, 0.0);
    glVertex3f( 0.5,  0.5,  0.5);
    glTexCoord2f(1.0, 1.0);
    glVertex3f( 0.5, -0.5,  0.5);
    glTexCoord2f(0.0, 1.0);
    glVertex3f( 0.5, -0.5, -0.5);
  glEnd;

  glPopMatrix();

  // Render Body //

  glPushMatrix();

  glBindTexture(GL_TEXTURE_2D, TexBody[T_TOP]);

  glBegin(GL_QUADS);
    glNormal3f( 0.0,  1.0,  0.0); // Top
    glTexCoord2f(1.0, 0.0);
    glVertex3f( 0.5,  0.75, -0.25);
    glTexCoord2f(0.0, 0.0);
    glVertex3f(-0.5,  0.75, -0.25);
    glTexCoord2f(0.0, 1.0);
    glVertex3f(-0.5,  0.75,  0.25);
    glTexCoord2f(1.0, 1.0);
    glVertex3f( 0.5,  0.75,  0.25);
  glEnd();

  glBindTexture(GL_TEXTURE_2D, TexBody[T_BOTTOM]);

  glBegin(GL_QUADS);
    glNormal3f( 0.0, -1.0,  0.0); // Bottom
    glTexCoord2f(1.0, 0.0);
    glVertex3f( 0.5, -0.75,  0.25);
    glTexCoord2f(0.0, 0.0);
    glVertex3f(-0.5, -0.75,  0.25);
    glTexCoord2f(0.0, 1.0);
    glVertex3f(-0.5, -0.75, -0.25);
    glTexCoord2f(1.0, 1.0);
    glVertex3f( 0.5, -0.75, -0.25);
  glEnd();

  glBindTexture(GL_TEXTURE_2D, TexBody[T_FRONT]);

  glBegin(GL_QUADS);
    glNormal3f( 0.0,  0.0,  0.5); // Front
    glTexCoord2f(1.0, 0.0);
    glVertex3f( 0.5,  0.75,  0.25);
    glTexCoord2f(0.0, 0.0);
    glVertex3f(-0.5,  0.75,  0.25);
    glTexCoord2f(0.0, 1.0);
    glVertex3f(-0.5, -0.75,  0.25);
    glTexCoord2f(1.0, 1.0);
    glVertex3f( 0.5, -0.75,  0.25);
  glEnd();

  glBindTexture(GL_TEXTURE_2D, TexBody[T_BACK]);

  glBegin(GL_QUADS);
    glNormal3f( 0.0,  0.0, -0.5); // Back
    glTexCoord2f(0.0, 1.0);
    glVertex3f( 0.5, -0.75, -0.25);
    glTexCoord2f(1.0, 1.0);
    glVertex3f(-0.5, -0.75, -0.25);
    glTexCoord2f(1.0, 0.0);
    glVertex3f(-0.5,  0.75, -0.25);
    glTexCoord2f(0.0, 0.0);
    glVertex3f( 0.5,  0.75, -0.25);
  glEnd();

  glBindTexture(GL_TEXTURE_2D, TexBody[T_LEFT]);

  glBegin(GL_QUADS);
    glNormal3f(-1.0,  0.0,  0.0); // Left
    glTexCoord2f(0.0, 0.0);
    glVertex3f(-0.5,  0.75,  0.25);
    glTexCoord2f(1.0, 0.0);
    glVertex3f(-0.5,  0.75, -0.25);
    glTexCoord2f(1.0, 1.0);
    glVertex3f(-0.5, -0.75, -0.25);
    glTexCoord2f(0.0, 1.0);
    glVertex3f(-0.5, -0.75,  0.25);
  glEnd();

  glBindTexture(GL_TEXTURE_2D, TexBody[T_RIGHT]);

  glBegin(GL_QUADS);
    glNormal3f( 1.0,  0.0,  0.0); // Right
    glTexCoord2f(1.0, 0.0);
    glVertex3f( 0.5,  0.75, -0.25);
    glTexCoord2f(0.0, 0.0);
    glVertex3f( 0.5,  0.75,  0.25);
    glTexCoord2f(0.0, 1.0);
    glVertex3f( 0.5, -0.75,  0.25);
    glTexCoord2f(1.0, 1.0);
    glVertex3f( 0.5, -0.75, -0.25);
  glEnd;

  glPopMatrix();

  // Render LEFT ARM //

  glPushMatrix();

  glTranslatef(-0.750, 0.500, 0.000);
  glRotatef(-ArmAngle, 1.0, 0.0, 0.0);

  glBindTexture(GL_TEXTURE_2D, TexLArm[T_TOP]);
  glBegin(GL_QUADS);
    glNormal3f(  0.0,   1.0,   0.0); // Top
    glTexCoord2f(1.0, 0.0);
    glVertex3f( 0.25,  0.25, -0.25);
    glTexCoord2f(0.0, 0.0);
    glVertex3f(-0.25,  0.25, -0.25);
    glTexCoord2f(0.0, 1.0);
    glVertex3f(-0.25,  0.25,  0.25);
    glTexCoord2f(1.0, 1.0);
    glVertex3f( 0.25,  0.25,  0.25);
  glEnd();

  glBindTexture(GL_TEXTURE_2D, TexLArm[T_BOTTOM]);
  glBegin(GL_QUADS);
    glNormal3f(  0.0,  -1.0,   0.0); // Bottom
    glTexCoord2f(1.0, 0.0);
    glVertex3f( 0.25, -1.25,  0.25);
    glTexCoord2f(0.0, 0.0);
    glVertex3f(-0.25, -1.25,  0.25);
    glTexCoord2f(0.0, 1.0);
    glVertex3f(-0.25, -1.25, -0.25);
    glTexCoord2f(1.0, 1.0);
    glVertex3f( 0.25, -1.25, -0.25);
  glEnd();

  glBindTexture(GL_TEXTURE_2D, TexLArm[T_FRONT]);
  glBegin(GL_QUADS);
    glNormal3f(  0.0,   0.0,   1.0); // Front
    glTexCoord2f(1.0, 0.0);
    glVertex3f( 0.25,  0.25,  0.25);
    glTexCoord2f(0.0, 0.0);
    glVertex3f(-0.25,  0.25,  0.25);
    glTexCoord2f(0.0, 1.0);
    glVertex3f(-0.25, -1.25,  0.25);
    glTexCoord2f(1.0, 1.0);
    glVertex3f( 0.25, -1.25,  0.25);
  glEnd();

  glBindTexture(GL_TEXTURE_2D, TexLArm[T_BACK]);
  glBegin(GL_QUADS);
    glNormal3f(  0.0,   0.0,  -1.0); // Back
    glTexCoord2f(1.0, 0.0);
    glVertex3f(-0.25,  0.25, -0.25);
    glTexCoord2f(0.0, 0.0);
    glVertex3f( 0.25,  0.25, -0.25);
    glTexCoord2f(0.0, 1.0);
    glVertex3f( 0.25, -1.25, -0.25);
    glTexCoord2f(1.0, 1.0);
    glVertex3f(-0.25, -1.25, -0.25);
  glEnd();

  glBindTexture(GL_TEXTURE_2D, TexLArm[T_LEFT]);
  glBegin(GL_QUADS);
    glNormal3f( -1.0,   0.0,   0.0); // Left
    glTexCoord2f(1.0, 0.0);
    glVertex3f(-0.25,  0.25,  0.25);
    glTexCoord2f(0.0, 0.0);
    glVertex3f(-0.25,  0.25, -0.25);
    glTexCoord2f(0.0, 1.0);
    glVertex3f(-0.25, -1.25, -0.25);
    glTexCoord2f(1.0, 1.0);
    glVertex3f(-0.25, -1.25,  0.25);
  glEnd();

  glBindTexture(GL_TEXTURE_2D, TexLArm[T_RIGHT]);
  glBegin(GL_QUADS);
    glNormal3f(  1.0,   0.0,   0.0); // Right
    glTexCoord2f(1.0, 0.0);
    glVertex3f( 0.25,  0.25, -0.25);
    glTexCoord2f(0.0, 0.0);
    glVertex3f( 0.25,  0.25,  0.25);
    glTexCoord2f(0.0, 1.0);
    glVertex3f( 0.25, -1.25,  0.25);
    glTexCoord2f(1.0, 1.0);
    glVertex3f( 0.25, -1.25, -0.25);
  glEnd();
  
  glPopMatrix();

  // Render RIGHT ARM //

  glPushMatrix();

  glTranslatef(0.750, 0.500, 0.000);
  glRotatef(+ArmAngle, 1.0, 0.0, 0.0);

  glBindTexture(GL_TEXTURE_2D, TexRArm[T_TOP]);
  glBegin(GL_QUADS);
    glNormal3f(  0.0,   1.0,   0.0); // Top
    glTexCoord2f(0.0, 0.0);
    glVertex3f( 0.25,  0.25, -0.25);
    glTexCoord2f(1.0, 0.0);
    glVertex3f(-0.25,  0.25, -0.25);
    glTexCoord2f(1.0, 1.0);
    glVertex3f(-0.25,  0.25,  0.25);
    glTexCoord2f(0.0, 1.0);
    glVertex3f( 0.25,  0.25,  0.25);
  glEnd();

  glBindTexture(GL_TEXTURE_2D, TexRArm[T_BOTTOM]);
  glBegin(GL_QUADS);
    glNormal3f(  0.0,  -1.0,   0.0); // Bottom
    glTexCoord2f(0.0, 0.0);
    glVertex3f( 0.25, -1.25,  0.25);
    glTexCoord2f(1.0, 0.0);
    glVertex3f(-0.25, -1.25,  0.25);
    glTexCoord2f(1.0, 1.0);
    glVertex3f(-0.25, -1.25, -0.25);
    glTexCoord2f(0.0, 1.0);
    glVertex3f( 0.25, -1.25, -0.25);
  glEnd();

  glBindTexture(GL_TEXTURE_2D, TexRArm[T_FRONT]);
  glBegin(GL_QUADS);
    glNormal3f(  0.0,   0.0,   1.0); // Front
    glTexCoord2f(0.0, 0.0);
    glVertex3f( 0.25,  0.25,  0.25);
    glTexCoord2f(1.0, 0.0);
    glVertex3f(-0.25,  0.25,  0.25);
    glTexCoord2f(1.0, 1.0);
    glVertex3f(-0.25, -1.25,  0.25);
    glTexCoord2f(0.0, 1.0);
    glVertex3f( 0.25, -1.25,  0.25);
  glEnd();

  glBindTexture(GL_TEXTURE_2D, TexRArm[T_BACK]);
  glBegin(GL_QUADS);
    glNormal3f(  0.0,   0.0,  -1.0); // Back
    glTexCoord2f(0.0, 0.0);
    glVertex3f(-0.25,  0.25, -0.25);
    glTexCoord2f(1.0, 0.0);
    glVertex3f( 0.25,  0.25, -0.25);
    glTexCoord2f(1.0, 1.0);
    glVertex3f( 0.25, -1.25, -0.25);
    glTexCoord2f(0.0, 1.0);
    glVertex3f(-0.25, -1.25, -0.25);
  glEnd();

  glBindTexture(GL_TEXTURE_2D, TexRArm[T_LEFT]);
  glBegin(GL_QUADS);
    glNormal3f( -1.0,   0.0,   0.0); // Left
    glTexCoord2f(0.0, 0.0);
    glVertex3f(-0.25,  0.25,  0.25);
    glTexCoord2f(1.0, 0.0);
    glVertex3f(-0.25,  0.25, -0.25);
    glTexCoord2f(1.0, 1.0);
    glVertex3f(-0.25, -1.25, -0.25);
    glTexCoord2f(0.0, 1.0);
    glVertex3f(-0.25, -1.25,  0.25);
  glEnd();

  glBindTexture(GL_TEXTURE_2D, TexRArm[T_RIGHT]);
  glBegin(GL_QUADS);
    glNormal3f(  1.0,   0.0,   0.0); // Right
    glTexCoord2f(0.0, 0.0);
    glVertex3f( 0.25,  0.25, -0.25);
    glTexCoord2f(1.0, 0.0);
    glVertex3f( 0.25,  0.25,  0.25);
    glTexCoord2f(1.0, 1.0);
    glVertex3f( 0.25, -1.25,  0.25);
    glTexCoord2f(0.0, 1.0);
    glVertex3f( 0.25, -1.25, -0.25);
  glEnd();
  
  glPopMatrix();

  // Render LEFT LEG //

  glPushMatrix();

  glTranslatef(-0.250, -1.000, 0.000);
  glRotatef(LegAngle, 1.0, 0.0, 0.0);

  glBindTexture(GL_TEXTURE_2D, TexLLeg[T_TOP]);
  glBegin(GL_QUADS);
    glNormal3f(  0.0,   1.0,   0.0); // Top
    glTexCoord2f(1.0, 0.0);
    glVertex3f( 0.25,  0.25, -0.25);
    glTexCoord2f(0.0, 0.0);
    glVertex3f(-0.25,  0.25, -0.25);
    glTexCoord2f(0.0, 1.0);
    glVertex3f(-0.25,  0.25,  0.25);
    glTexCoord2f(1.0, 1.0);
    glVertex3f( 0.25,  0.25,  0.25);
  glEnd();

  glBindTexture(GL_TEXTURE_2D, TexLLeg[T_BOTTOM]);
  glBegin(GL_QUADS);
    glNormal3f(  0.0,  -1.0,   0.0); // Bottom
    glTexCoord2f(1.0, 0.0);
    glVertex3f( 0.25, -1.25,  0.25);
    glTexCoord2f(0.0, 0.0);
    glVertex3f(-0.25, -1.25,  0.25);
    glTexCoord2f(0.0, 1.0);
    glVertex3f(-0.25, -1.25, -0.25);
    glTexCoord2f(1.0, 1.0);
    glVertex3f( 0.25, -1.25, -0.25);
  glEnd();

  glBindTexture(GL_TEXTURE_2D, TexLLeg[T_FRONT]);
  glBegin(GL_QUADS);
    glNormal3f(  0.0,   0.0,   1.0); // Front
    glTexCoord2f(1.0, 0.0);
    glVertex3f( 0.25,  0.25,  0.25);
    glTexCoord2f(0.0, 0.0);
    glVertex3f(-0.25,  0.25,  0.25);
    glTexCoord2f(0.0, 1.0);
    glVertex3f(-0.25, -1.25,  0.25);
    glTexCoord2f(1.0, 1.0);
    glVertex3f( 0.25, -1.25,  0.25);
  glEnd();

  glBindTexture(GL_TEXTURE_2D, TexLLeg[T_BACK]);
  glBegin(GL_QUADS);
    glNormal3f(  0.0,   0.0,  -1.0); // Back
    glTexCoord2f(1.0, 0.0);
    glVertex3f(-0.25,  0.25, -0.25);
    glTexCoord2f(0.0, 0.0);
    glVertex3f( 0.25,  0.25, -0.25);
    glTexCoord2f(0.0, 1.0);
    glVertex3f( 0.25, -1.25, -0.25);
    glTexCoord2f(1.0, 1.0);
    glVertex3f(-0.25, -1.25, -0.25);
  glEnd();

  glBindTexture(GL_TEXTURE_2D, TexLLeg[T_LEFT]);
  glBegin(GL_QUADS);
    glNormal3f( -1.0,   0.0,   0.0); // Left
    glTexCoord2f(1.0, 0.0);
    glVertex3f(-0.25,  0.25,  0.25);
    glTexCoord2f(0.0, 0.0);
    glVertex3f(-0.25,  0.25, -0.25);
    glTexCoord2f(0.0, 1.0);
    glVertex3f(-0.25, -1.25, -0.25);
    glTexCoord2f(1.0, 1.0);
    glVertex3f(-0.25, -1.25,  0.25);
  glEnd();

  glBindTexture(GL_TEXTURE_2D, TexLLeg[T_RIGHT]);
  glBegin(GL_QUADS);
    glNormal3f(  1.0,   0.0,   0.0); // Right
    glTexCoord2f(1.0, 0.0);
    glVertex3f( 0.25,  0.25, -0.25);
    glTexCoord2f(0.0, 0.0);
    glVertex3f( 0.25,  0.25,  0.25);
    glTexCoord2f(0.0, 1.0);
    glVertex3f( 0.25, -1.25,  0.25);
    glTexCoord2f(1.0, 1.0);
    glVertex3f( 0.25, -1.25, -0.25);
  glEnd();
  
  glPopMatrix();

  // Render RIGHT LEG //

  glPushMatrix();

  glTranslatef(0.250, -1.000, 0.000);
  glRotatef(-LegAngle, 1.0, 0.0, 0.0);

  glBindTexture(GL_TEXTURE_2D, TexRLeg[T_TOP]);
  glBegin(GL_QUADS);
    glNormal3f(  0.0,   1.0,   0.0); // Top
    glTexCoord2f(0.0, 0.0);
    glVertex3f( 0.25,  0.25, -0.25);
    glTexCoord2f(1.0, 0.0);
    glVertex3f(-0.25,  0.25, -0.25);
    glTexCoord2f(1.0, 1.0);
    glVertex3f(-0.25,  0.25,  0.25);
    glTexCoord2f(0.0, 1.0);
    glVertex3f( 0.25,  0.25,  0.25);
  glEnd();

  glBindTexture(GL_TEXTURE_2D, TexRLeg[T_BOTTOM]);
  glBegin(GL_QUADS);
    glNormal3f(  0.0,  -1.0,   0.0); // Bottom
    glTexCoord2f(0.0, 0.0);
    glVertex3f( 0.25, -1.25,  0.25);
    glTexCoord2f(1.0, 0.0);
    glVertex3f(-0.25, -1.25,  0.25);
    glTexCoord2f(1.0, 1.0);
    glVertex3f(-0.25, -1.25, -0.25);
    glTexCoord2f(0.0, 1.0);
    glVertex3f( 0.25, -1.25, -0.25);
  glEnd();

  glBindTexture(GL_TEXTURE_2D, TexRLeg[T_FRONT]);
  glBegin(GL_QUADS);
    glNormal3f(  0.0,   0.0,   1.0); // Front
    glTexCoord2f(0.0, 0.0);
    glVertex3f( 0.25,  0.25,  0.25);
    glTexCoord2f(1.0, 0.0);
    glVertex3f(-0.25,  0.25,  0.25);
    glTexCoord2f(1.0, 1.0);
    glVertex3f(-0.25, -1.25,  0.25);
    glTexCoord2f(0.0, 1.0);
    glVertex3f( 0.25, -1.25,  0.25);
  glEnd();

  glBindTexture(GL_TEXTURE_2D, TexRLeg[T_BACK]);
  glBegin(GL_QUADS);
    glNormal3f(  0.0,   0.0,  -1.0); // Back
    glTexCoord2f(0.0, 0.0);
    glVertex3f(-0.25,  0.25, -0.25);
    glTexCoord2f(1.0, 0.0);
    glVertex3f( 0.25,  0.25, -0.25);
    glTexCoord2f(1.0, 1.0);
    glVertex3f( 0.25, -1.25, -0.25);
    glTexCoord2f(0.0, 1.0);
    glVertex3f(-0.25, -1.25, -0.25);
  glEnd();

  glBindTexture(GL_TEXTURE_2D, TexRLeg[T_LEFT]);
  glBegin(GL_QUADS);
    glNormal3f( -1.0,   0.0,   0.0); // Left
    glTexCoord2f(0.0, 0.0);
    glVertex3f(-0.25,  0.25,  0.25);
    glTexCoord2f(1.0, 0.0);
    glVertex3f(-0.25,  0.25, -0.25);
    glTexCoord2f(1.0, 1.0);
    glVertex3f(-0.25, -1.25, -0.25);
    glTexCoord2f(0.0, 1.0);
    glVertex3f(-0.25, -1.25,  0.25);
  glEnd();

  glBindTexture(GL_TEXTURE_2D, TexRLeg[T_RIGHT]);
  glBegin(GL_QUADS);
    glNormal3f(  1.0,   0.0,   0.0); // Right
    glTexCoord2f(0.0, 0.0);
    glVertex3f( 0.25,  0.25, -0.25);
    glTexCoord2f(1.0, 0.0);
    glVertex3f( 0.25,  0.25,  0.25);
    glTexCoord2f(1.0, 1.0);
    glVertex3f( 0.25, -1.25,  0.25);
    glTexCoord2f(0.0, 1.0);
    glVertex3f( 0.25, -1.25, -0.25);
  glEnd();
  
  glPopMatrix();

  glPopMatrix(); // ..Man

  SwapBuffers(ContextDC);
end;

procedure TMainForm.FormCreate(Sender: TObject);
const
  E_CONALLOC_FAILED = 'Console allocation has failed!';
begin
  {
  if not AllocConsole() then
    MessageBox(Handle, PChar(E_CONALLOC_FAILED), P_APPTITLE,
      MB_ICONEXCLAMATION);
  }

  ContextDC := 0;

  if not InitOpenGL() then
  begin
    MessageBox(Handle, PChar(E_CONALLOC_FAILED), P_APPTITLE,
      MB_ICONEXCLAMATION);
    Application.Terminate();  
    Exit;
  end;

  ContextDC := GetDC(RenderPanel.Handle);
  RenderContext := CreateRenderingContext(ContextDC, [opDoubleBuffered],
    32 {ColorBits}, 24 {ZBits}, 0, 0, 0, 0);

  ActivateRenderingContext(ContextDC, RenderContext);

  R_Prepare;
  PrepareTexture;

  CameraPosZ := 6.00;
  SkinTextureIndex := 0;
  MouseDown := False;
  ArmAngle := 0;
  LegAngle := ArmAngle;
  AnimationCircleAngle := 0;
  Rotating := True;
  StepZ := 0;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  // Delete loaded textures? No! >:[

  DeactivateRenderingContext;
  DestroyRenderingContext(RenderContext);
  ReleaseDC(RenderPanel.Handle, ContextDC);
  
  // FreeConsole;
end;

procedure TMainForm.RenderTimerEvent(Sender: TObject);
begin
  if not Self.Active then
    Exit;

  if Rotating then
    DoAnimation;
  
  DoRender;
end;

procedure TMainForm.FormActivate(Sender: TObject);
begin
  RenderTimer.Enabled := True;
end;

procedure TMainForm.DoSceneResize;
var
  Aspect: Double;
begin
  glViewport(0, 0, RenderPanel.Width, RenderPanel.Height);
  glMatrixMode(GL_PROJECTION);
  glLoadIdentity();

  if RenderPanel.ClientHeight <> 0 then
    Aspect := RenderPanel.ClientWidth / RenderPanel.ClientHeight
  else
    Aspect := 1;

  gluPerspective(R_FOV, Aspect, R_NEAR_CLIP, R_FAR_CLIP);

  glMatrixMode(GL_MODELVIEW);
  glLoadIdentity();
end;

procedure TMainForm.R_Prepare;
const
  E_TEXTURE_LOAD = 'Unable to load a texture';
  FOG_COLOR: TVec3f = (0.5, 0.5, 0.5, 1.0); 
begin
  glClearColor(
    GetRValue(R_CLEARCOLOR) / 255,
    GetGValue(R_CLEARCOLOR) / 255,
    GetBValue(R_CLEARCOLOR) / 255,
    0.0
  );
  
  glEnable(GL_DEPTH_TEST); // Р. теста глубины
  glEnable(GL_CULL_FACE);  // Р. отображения только передних поверхностей

  glDepthFunc(GL_LESS);

  glEnable(GL_LIGHTING);
  glEnable(GL_LIGHT0);

  glEnable(GL_COLOR_MATERIAL);
  glEnable(GL_NORMALIZE);

  glEnable(GL_TEXTURE_2D);

  DoSceneResize;
end;

procedure TMainForm.FormResize(Sender: TObject);
begin
  DoSceneResize;
end;

procedure TMainForm.DoAnimation;
const
  ANIM_STEP_ANGLE = 5; // Deg
begin
  // Camera Rotation //

  if CompareValue(AngleY, 360.0) = EqualsValue then
    AngleY := 0;

  AngleY := AngleY + 0.5;

  // Model //

  if CompareValue(AnimationCircleAngle, 360) = EqualsValue then
    AnimationCircleAngle := 0;

  AnimationCircleAngle := AnimationCircleAngle + ANIM_STEP_ANGLE;
  ArmAngle := 45 * Sin(DegToRad(AnimationCircleAngle));

  ArmAngle := ArmAngle * 0.80;
  LegAngle := ArmAngle;

  // Terrain //

  if CompareValue(StepZ, 2.00, 0.00001) = EqualsValue  then
    StepZ := 0;

  StepZ := StepZ + 0.05; 
end;

procedure TMainForm.DoOnIdle;
begin
  RenderTimerEvent(nil);
  Done := False;
end;

procedure TMainForm.FormKeyUp(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
    Close
  else
  if Key = VK_UP then
    CameraPosZ := CameraPosZ - 0.25
  else
  if Key = VK_DOWN then
    CameraPosZ := CameraPosZ + 0.25;
end;

procedure TMainForm.PrepareTexture;
const
  HEAD_SIZE = 8;
  BODY_H_SIZE = 12;
  BODY_D_SIZE = 4;
  BODY_W_SIZE = 8;
  ARM_D_SIZE = BODY_D_SIZE;
  ARM_H_SIZE = BODY_H_SIZE;
  ARM_W_SIZE = 4;
  BLOCK_SIZE = 16;
  PANORAMA_TEX_SIZE = 256;
  BLOCK_TEX_SIZE = 16;
var
  PngMap: TPNGObject;
  Data: PByteArray;

  function _Map(const X, Y, W, H: Integer): GLuint;
  var
    TextureData: Pointer;
  begin
    TextureData := TextureFragment(Data, X, Y, W, H, SKIN_TEXTURE_W,
      SKIN_TEXTURE_H);
    Result := GL_LoadTextureFromBuffer(W, H, TextureData);
    FreeMem(TextureData);
  end;

  procedure _FillDataFromPng;
  var
    iW: Integer;
    iH: Integer;
    Pixel: Integer;
    PxIndex: Integer;
  begin
    PxIndex := 0;

    for iH := 0 to PngMap.Height - 1 do
      for iW := 0 to PngMap.Width - 1 do
      begin
        Pixel := PngMap.Pixels[iW, iH];
        Data[PxIndex * 3 + 0] := GetRValue(Pixel);
        Data[PxIndex * 3 + 1] := GetGValue(Pixel);
        Data[PxIndex * 3 + 2] := GetBValue(Pixel);
        PxIndex := PxIndex + 1;
      end;
  end;

begin
  // Skin //

  PngMap := TexturePngCollection.Items.Items[SkinTextureIndex].PngImage;

  try
    GetMem(Data, PngMap.Width * PngMap.Height * 3);

    _FillDataFromPng;

    TexFace[T_TOP]    := _Map(8 , 0 , HEAD_SIZE, HEAD_SIZE);
    TexFace[T_BOTTOM] := _Map(16, 0 , HEAD_SIZE, HEAD_SIZE);
    TexFace[T_FRONT]  := _Map(8 , 8 , HEAD_SIZE, HEAD_SIZE);
    TexFace[T_BACK]   := _Map(24, 8 , HEAD_SIZE, HEAD_SIZE);
    TexFace[T_LEFT]   := _Map(16, 8 , HEAD_SIZE, HEAD_SIZE);
    TexFace[T_RIGHT]  := _Map(0 , 8 , HEAD_SIZE, HEAD_SIZE);

    TexBody[T_TOP]    := _Map(20, 16, BODY_W_SIZE, BODY_D_SIZE);
    TexBody[T_BOTTOM] := _Map(28, 16, BODY_W_SIZE, BODY_D_SIZE);
    TexBody[T_FRONT]  := _Map(20, 20, BODY_W_SIZE, BODY_H_SIZE);
    TexBody[T_BACK]   := _Map(32, 20, BODY_W_SIZE, BODY_H_SIZE);
    TexBody[T_LEFT]   := _Map(16, 20, BODY_D_SIZE, BODY_H_SIZE);
    TexBody[T_RIGHT]  := _Map(28, 20, BODY_D_SIZE, BODY_H_SIZE);

    TexLArm[T_TOP]    := _Map(44, 16, ARM_W_SIZE, ARM_D_SIZE);
    TexLArm[T_BOTTOM] := _Map(48, 16, ARM_W_SIZE, ARM_D_SIZE);
    TexLArm[T_FRONT]  := _Map(44, 20, ARM_W_SIZE, ARM_H_SIZE);
    TexLArm[T_BACK]   := _Map(52, 20, ARM_W_SIZE, ARM_H_SIZE);
    TexLArm[T_LEFT]   := _Map(40, 20, ARM_D_SIZE, ARM_H_SIZE);
    TexLArm[T_RIGHT]  := _Map(48, 20, ARM_D_SIZE, ARM_H_SIZE);

    TexRArm[T_TOP]    := TexLArm[T_TOP];
    TexRArm[T_BOTTOM] := TexLArm[T_BOTTOM];
    TexRArm[T_FRONT]  := TexLArm[T_FRONT];
    TexRArm[T_BACK]   := TexLArm[T_BACK];
    TexRArm[T_LEFT]   := TexLArm[T_RIGHT];
    TexRArm[T_RIGHT]  := TexLArm[T_LEFT];

    TexLLeg[T_TOP]    := _Map( 4, 16, ARM_W_SIZE, ARM_D_SIZE);
    TexLLeg[T_BOTTOM] := _Map( 8, 16, ARM_W_SIZE, ARM_D_SIZE);
    TexLLeg[T_FRONT]  := _Map( 4, 20, ARM_W_SIZE, ARM_H_SIZE);
    TexLLeg[T_BACK]   := _Map(12, 20, ARM_W_SIZE, ARM_H_SIZE);
    TexLLeg[T_LEFT]   := _Map( 8, 20, ARM_D_SIZE, ARM_H_SIZE);
    TexLLeg[T_RIGHT]  := _Map( 0, 20, ARM_D_SIZE, ARM_H_SIZE);

    TexRLeg[T_TOP]    := TexLLeg[T_TOP];
    TexRLeg[T_BOTTOM] := TexLLeg[T_BOTTOM];
    TexRLeg[T_FRONT]  := TexLLeg[T_FRONT];
    TexRLeg[T_BACK]   := TexLLeg[T_BACK];
    TexRLeg[T_LEFT]   := TexLLeg[T_RIGHT];
    TexRLeg[T_RIGHT]  := TexLLeg[T_LEFT];
  finally
    FreeMem(Data);
  end;

  // Panorama //

  try
    GetMem(Data, PANORAMA_TEX_SIZE * PANORAMA_TEX_SIZE * 3);

    PngMap := TexturePngCollection.Items.Items[2].PngImage;
    _FillDataFromPng;
    TexPanorama[T_LEFT]   := GL_LoadTextureFromBuffer(PANORAMA_TEX_SIZE,
      PANORAMA_TEX_SIZE, Data);

    PngMap := TexturePngCollection.Items.Items[3].PngImage;
    _FillDataFromPng;
    TexPanorama[T_FRONT]  := GL_LoadTextureFromBuffer(PANORAMA_TEX_SIZE,
      PANORAMA_TEX_SIZE, Data);

    PngMap := TexturePngCollection.Items.Items[4].PngImage;
    _FillDataFromPng;
    TexPanorama[T_RIGHT]  := GL_LoadTextureFromBuffer(PANORAMA_TEX_SIZE,
      PANORAMA_TEX_SIZE, Data);

    PngMap := TexturePngCollection.Items.Items[5].PngImage;
    _FillDataFromPng;
    TexPanorama[T_BACK]   := GL_LoadTextureFromBuffer(PANORAMA_TEX_SIZE,
      PANORAMA_TEX_SIZE, Data);

    PngMap := TexturePngCollection.Items.Items[6].PngImage;
    _FillDataFromPng;
    TexPanorama[T_TOP]    := GL_LoadTextureFromBuffer(PANORAMA_TEX_SIZE,
      PANORAMA_TEX_SIZE, Data);

    PngMap := TexturePngCollection.Items.Items[7].PngImage;
    _FillDataFromPng;
    TexPanorama[T_BOTTOM] := GL_LoadTextureFromBuffer(PANORAMA_TEX_SIZE,
      PANORAMA_TEX_SIZE, Data);
  finally
    FreeMem(Data);
  end;

  // Grass //

  try
    GetMem(Data, BLOCK_TEX_SIZE * BLOCK_TEX_SIZE * 3);

    PngMap := TexturePngCollection.Items.Items[9].PngImage;
    _FillDataFromPng;
    TexBlockGrass[T_TOP] := GL_LoadTextureFromBuffer(BLOCK_TEX_SIZE,
      BLOCK_TEX_SIZE, Data);
  finally
    FreeMem(Data);
  end;
end;

procedure TMainForm.Textures2DMenuItemClick(Sender: TObject);
begin
  if Textures2DMenuItem.Checked then
    glEnable(GL_TEXTURE_2D)
  else
    glDisable(GL_TEXTURE_2D);
end;

procedure TMainForm.Light0MenuItemClick(Sender: TObject);
begin
  if Light0MenuItem.Checked then
    glEnable(GL_LIGHT0)
  else
    glDisable(GL_LIGHT0);
end;

procedure TMainForm.LightningMenuItemClick(Sender: TObject);
begin
  if LightningMenuItem.Checked then
    glEnable(GL_LIGHTING)
  else
    glDisable(GL_LIGHTING);
    
  Light0MenuItem.Enabled := LightningMenuItem.Checked;
end;

procedure TMainForm.Skin1MenuItemClick(Sender: TObject);
begin
  SkinTextureIndex := TMenuItem(Sender).Tag;
  PrepareTexture;
end;

procedure TMainForm.RenderPanelMouseMove(Sender: TObject;
  Shift: TShiftState; X, Y: Integer);
const
  HCOEFF = 0.25;
var
  DeltaX: Integer;
  DeltaY: Integer;
begin
  if not MouseDown then
    Exit;

  DeltaX := 0;
  DeltaY := 0;

  if ssShift in Shift then
  begin
    DeltaY := Y - MouseDownPosY;
    AngleX := LastAngleX - HCOEFF * DeltaY;
  end
  else
  begin
    DeltaX := X - MouseDownPosX;
    AngleY := LastAngleY - HCOEFF * DeltaX;
  end;

  if (Abs(DeltaX) > 5) or (Abs(DeltaY) > 5) then
    DoRender;
end;

procedure TMainForm.RenderPanelMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  RenderTimer.Enabled := False;
  MouseDown := True;
  MouseDownPosX := X;
  MouseDownPosY := Y;
  LastAngleY := AngleY;
  LastAngleX := AngleX;
end;

procedure TMainForm.RenderPanelMouseUp(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  MouseDown := False;
  RenderTimer.Enabled := True;
end;

procedure TMainForm.RenderPanorama;
const
  BV: Single = 512;
begin
  glPushMatrix();

    glBindTexture(GL_TEXTURE_2D, TexPanorama[T_LEFT]);

    glBegin(GL_QUADS);
      glNormal3f(1, 0, 0);
      glTexCoord2d(1, 0);
      glVertex3f(-BV,  BV, -BV);
      glTexCoord2d(0, 0);
      glVertex3f(-BV,  BV,  BV);
      glTexCoord2d(0, 1);
      glVertex3f(-BV, -BV,  BV);
      glTexCoord2d(1, 1);
      glVertex3f(-BV, -BV, -BV);
    glEnd();

    glBindTexture(GL_TEXTURE_2D, TexPanorama[T_FRONT]);

    glBegin(GL_QUADS);
      glNormal3f(0, 0, 1);
      glTexCoord2d(1, 0);
      glVertex3f( BV,  BV, -BV);
      glTexCoord2d(0, 0);
      glVertex3f(-BV,  BV, -BV);
      glTexCoord2d(0, 1);
      glVertex3f(-BV, -BV, -BV);
      glTexCoord2d(1, 1);
      glVertex3f( BV, -BV, -BV);
    glEnd();

    glBindTexture(GL_TEXTURE_2D, TexPanorama[T_RIGHT]);

    glBegin(GL_QUADS);
      glNormal3f(-1, 0, 0);
      glTexCoord2d(1, 0);
      glVertex3f( BV,  BV,  BV);
      glTexCoord2d(0, 0);
      glVertex3f( BV,  BV, -BV);
      glTexCoord2d(0, 1);
      glVertex3f( BV, -BV, -BV);
      glTexCoord2d(1, 1);
      glVertex3f( BV, -BV,  BV);
    glEnd();

    glBindTexture(GL_TEXTURE_2D, TexPanorama[T_BACK]);

    glBegin(GL_QUADS);
      glNormal3f(0, 0, -1);
      glTexCoord2d(1, 0);
      glVertex3f(-BV,  BV,  BV);
      glTexCoord2d(0, 0);
      glVertex3f( BV,  BV,  BV);
      glTexCoord2d(0, 1);
      glVertex3f( BV, -BV,  BV);
      glTexCoord2d(1, 1);
      glVertex3f(-BV, -BV,  BV);
    glEnd();

    glBindTexture(GL_TEXTURE_2D, TexPanorama[T_TOP]);

    glBegin(GL_QUADS);
      glNormal3f(0, -1, 0);
      glTexCoord2d(0, 0);
      glVertex3f( BV,  BV,  BV);
      glTexCoord2d(0, 1);
      glVertex3f(-BV,  BV,  BV);
      glTexCoord2d(1, 1);
      glVertex3f(-BV,  BV, -BV);
      glTexCoord2d(1, 0);
      glVertex3f( BV,  BV, -BV);
    glEnd();

    glBindTexture(GL_TEXTURE_2D, TexPanorama[T_BOTTOM]);

    glBegin(GL_QUADS);
      glNormal3f(0, 1, 0);
      glTexCoord2d(1, 1);
      glVertex3f( BV, -BV, -BV);
      glTexCoord2d(1, 0);
      glVertex3f(-BV, -BV, -BV);
      glTexCoord2d(0, 0);
      glVertex3f(-BV, -BV,  BV);
      glTexCoord2d(0, 1);
      glVertex3f( BV, -BV,  BV);
    glEnd();

  glPopMatrix();
end;

procedure TMainForm.RenderTerrain;
const
  BLOCK_SIZE = 2.00;
  HSIZE = 1.00;
  MAP_SIZE = 21;
var
  GndSize: Single;
  RC: Single; // Repeat count
begin
  glPushMatrix();

    glTranslatef(0.0, -1.25, -StepZ * BLOCK_SIZE);

    glBindTexture(GL_TEXTURE_2D, TexBlockGrass[T_TOP]);

    GndSize := MAP_SIZE * BLOCK_SIZE;
    RC := MAP_SIZE;

    glBegin(GL_QUADS);
      glNormal3f(0, 1, 0);
      glTexCoord2d(RC, 0);
      glVertex3f( GndSize, 0, -GndSize);
      glTexCoord2d(0, 0);
      glVertex3f(-GndSize, 0, -GndSize);
      glTexCoord2d(0, RC);
      glVertex3f(-GndSize, 0,  GndSize);
      glTexCoord2d(RC, RC);
      glVertex3f( GndSize, 0,  GndSize);
    glEnd();

  glPopMatrix();
end;

procedure TMainForm.TimerMenuItemClick(Sender: TObject);
begin
  Rotating := not Rotating;

  if Rotating then
    TimerMenuItem.Caption := 'Pause'
  else
    TimerMenuItem.Caption := 'Continue';
end;

initialization
  P_APPTITLE := PChar(Application.Title);

end.
