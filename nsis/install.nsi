; Installation script for KiCad
;
; This installation script requires NSIS (Nullsoft Scriptable Install System)
; version 3.x http://nsis.sourceforge.net/Main_Page
;
; This script is provided as is with no warranties.
;
; Copyright (C) 2006 Alastair Hoyle <ahoyle@hoylesolutions.co.uk>
; Copyright (C) 2015-2021 Nick Østergaard
; Copyright (C) 2015 Brian Sidebotham <brian.sidebotham@gmail.com>
; Copyright (C) 2016 Bevan Weiss <bevan.weiss@gmail.com>
; Copyright (C) 2019 Andrew Lutsenko
; Copyright (C) 2020-2022 Mark Roszko <mark.roszko@gmail.com>
;
; This program is free software; you can redistribute it and/or modify it
; under the terms of the GNU General Public License as published by the Free
; Software Foundation. This program is distributed in the hope that it will be
; useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General
; Public License for more details.
;
; This script should be in a subdirectory of the full build directory
; (Kicad/NSIS by default). When the build is updated the product and installer
; versions should be updated before recompiling the installation file
;
; This script expects the install.ico, uninstall.ico, language and license
; files to be in the same directory as this script

!addplugindir /x86-ansi "./plugins/x86-ansi"
!addplugindir /x86-unicode "./plugins/x86-unicode"
!addincludedir ".\includes"

!include "x64.nsh"
!include "winmessages.nsh"
!include "WinVer.nsh"
!include "nsProcess.nsh"
!include "NsisMultiUser.nsh"
!include "StdUtils.nsh"
!include "RecFind.nsh"

; General Product Description Definitions
!define PRODUCT_NAME "KiCad"
!define KICAD_MAIN_SITE "www.kicad.org/"
!define COMPANY_NAME "KiCad"
!define TRADE_MARKS ""
!define COPYRIGHT "Kicad Developers Team"
!define COMMENTS ""

; MultiUser plugin config
; WARNING, WE PATCHED NsisMultiUser.nsh because it fails to use the \Programs
; subfolder under LocalAppData, this is the folder microsoft enshrines for app installs
!define MULTIUSER_INSTALLMODE_ALLOW_BOTH_INSTALLATIONS 0
!define MULTIUSER_INSTALLMODE_ALLOW_ELEVATION 1
!define MULTIUSER_INSTALLMODE_ALLOW_ELEVATION_IF_SILENT 1 ; required for silent-mode allusers-uninstall to work, when using the workaround for Windows elevation bug
!define MULTIUSER_INSTALLMODE_DEFAULT_ALLUSERS 1
!define MULTIUSER_INSTALLMODE_64_BIT 1  ; it's ridiculous the plugin controls the program files view
!define KICAD_MULTIUSER_INSTALLMODE_64_BIT_32BITVIEW 0 ; unsure the 32-bit hack is off
!define MULTIUSER_INSTALLMODE_INSTDIR "KiCad\${KICAD_VERSION}" ; the appended path we get installed to
!define MULTIUSER_INSTALLMODE_UNINSTALL_REGISTRY_KEY "${PRODUCT_NAME} ${KICAD_VERSION}"
!define MULTIUSER_INSTALLMODE_DISPLAYNAME "${PRODUCT_NAME} ${KICAD_VERSION}"
!define PROGEXE "bin/kicad.exe"     ; used by the plugin
!define VERSION "${PACKAGE_VERSION}" ; used by the plugin

!define FILE_ASSOC_PREFIX	"KiCad"
!define SOFTWARE_CLASSES_ROOT_KEY 'SHCTX'

!define gflag ;Needed to use ifdef and such
;Define on command line //DPACKAGE_VERSION=42
!ifndef PACKAGE_VERSION
  !define PACKAGE_VERSION "unknown"
!endif

!ifndef OPTION_STRING
  !define OPTION_STRING "unknown"
!endif

!ifndef KICAD_VERSION
  !define KICAD_VERSION "unknown"
!endif

!define PRODUCT_UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME} ${KICAD_VERSION}"
!define UNINST_ROOT "SHCTX"

;Define libraries download urls
!ifdef LIBRARIES_TAG
Var DELETE_DOWNLOADED_FILES
!define KICAD_SYMBOLS_FILE "kicad-symbols-${LIBRARIES_TAG}.zip"
!define KICAD_SYMBOLS_FOLDER "kicad-symbols-${LIBRARIES_TAG}"
!define KICAD_SYMBOLS_URL "https://gitlab.com/kicad/libraries/kicad-symbols/-/archive/${LIBRARIES_TAG}/kicad-symbols-${LIBRARIES_TAG}.zip"
!define KICAD_FOOTPRINTS_FILE "kicad-footprints-${LIBRARIES_TAG}.zip"
!define KICAD_FOOTPRINTS_FOLDER "kicad-footprints-${LIBRARIES_TAG}"
!define KICAD_FOOTPRINTS_URL "https://gitlab.com/kicad/libraries/kicad-footprints/-/archive/${LIBRARIES_TAG}/kicad-footprints-${LIBRARIES_TAG}.zip"
!define KICAD_PACKAGES3D_FILE "kicad-packages3D-${LIBRARIES_TAG}.zip"
!define KICAD_PACKAGES3D_FOLDER "kicad-packages3D-${LIBRARIES_TAG}"
!define KICAD_PACKAGES3D_URL "https://gitlab.com/kicad/libraries/kicad-packages3D/-/archive/${LIBRARIES_TAG}/kicad-packages3D-${LIBRARIES_TAG}.zip"
!endif

;Properly display all languages (Installer will not work on Windows 95, 98 or ME!)
Unicode true

CRCCheck force
;XPStyle on
Name "${PRODUCT_NAME} ${PACKAGE_VERSION}"

!ifndef OUTFILE
  !define OUTFILE "kicad-${PACKAGE_VERSION}-${OPTION_STRING}.exe"
!endif
OutFile ${OUTFILE}

; Define a variable with start menu path for later use
!define SMPATH "$SMPROGRAMS\KiCad ${KICAD_VERSION}"

ShowInstDetails nevershow
ShowUnInstDetails nevershow
BrandingText "KiCad installer for Windows"

; MUI 2 compatible ------
!include "MUI2.nsh"
!include "${NSISDIR}\Examples\System\System.nsh"

; MUI Settings
!define MUI_ABORTWARNING
!define MUI_ICON "install.ico"
!define MUI_UNICON "uninstall.ico"
!define MUI_HEADERIMAGE
!define MUI_HEADERIMAGE_BITMAP "kicad-header.bmp" ; optional
!define MUI_WELCOMEFINISHPAGE_BITMAP "kicad-welcome.bmp"

; Language Selection Dialog Settings
!define MUI_LANGDLL_REGISTRY_ROOT SHCTX
!define MUI_LANGDLL_REGISTRY_KEY "${PRODUCT_UNINST_KEY}"
!define MUI_LANGDLL_REGISTRY_VALUENAME "NSIS:Language"

; Installer pages
!define MUI_CUSTOMFUNCTION_UNGUIINIT un.onMyGuiInit
!define MUI_WELCOMEPAGE_TEXT $(WELCOME_PAGE_TEXT)
!define MUI_WELCOMEPAGE_TITLE_3LINES

; Pages
!define MUI_PAGE_CUSTOMFUNCTION_PRE PageWelcomeLicensePre
!insertmacro MUI_PAGE_WELCOME

!insertmacro MULTIUSER_PAGE_INSTALLMODE
;!insertmacro MUI_PAGE_LICENSE $(MUILicense)
!insertmacro MUI_PAGE_COMPONENTS

!define MUI_PAGE_CUSTOMFUNCTION_LEAVE onDirectoryPageLeave
!insertmacro MUI_PAGE_DIRECTORY

!insertmacro MUI_PAGE_INSTFILES
!define MUI_PAGE_CUSTOMFUNCTION_SHOW ModifyFinishPage
!insertmacro MUI_PAGE_FINISH

; Uninstaller pages
!insertmacro MULTIUSER_UNPAGE_INSTALLMODE
!insertmacro MUI_UNPAGE_INSTFILES

; Language files
; - To add another language; add an insert macro line here and include a language file as below
; - This must be after all page macros have been inserted
!insertmacro MUI_LANGUAGE "English" ;first language is the default language
!insertmacro MUI_LANGUAGE "German"
!insertmacro MUI_LANGUAGE "Italian"
!insertmacro MUI_LANGUAGE "Spanish"
!insertmacro MUI_LANGUAGE "Greek"
!insertmacro MUI_LANGUAGE "SimpChinese"

!include "lang\English.nsh"
!include "lang\German.nsh"
!include "lang\Italian.nsh"
!include "lang\Spanish.nsh"
!include "lang\Greek.nsh"
!include "lang\Chinese.nsh"
!include "NsisMultiUserLang.nsh"

VIProductVersion "0.0.0.0" ; Dummy version, because this can only be X.X.X.X
VIAddVersionKey "ProductName" "${COMPANY_NAME}"
VIAddVersionKey "CompanyName" "${COMPANY_NAME}"
VIAddVersionKey "LegalCopyright" "${COMPANY_NAME}"
VIAddVersionKey "FileDescription" "Installer for the KiCad EDA Suite"
VIAddVersionKey "ProductVersion" "${PACKAGE_VERSION}"
VIAddVersionKey "FileVersion" "${PACKAGE_VERSION}"

;--------------------------------
;Reserve Files

  ;If you are using solid compression, files that are required before
  ;the actual installation should be stored first in the data block,
  ;because this will make your installer start faster.

  !insertmacro MUI_RESERVEFILE_LANGDLL

; MUI end ------

!include "includes\file-association.nsh"
!include "includes\process-check.nsh"

;--------------------------------

!define SetEnvironmentVariable "Kernel32::SetEnvironmentVariable(t, t)i"

Function .onInit
	${ifnot} ${UAC_IsInnerInstance}
    Call PreventMultiInstances
	${endif}

  !insertmacro MULTIUSER_INIT

  !if ${ARCH} == 'arm64'
    ${IfNot} ${IsNativeARM64}
      MessageBox MB_OK|MB_TOPMOST $(ERROR_WRONG_ARCH)
      Quit
    ${endif}
  !endif

  !if ${ARCH} == 'x86_64'
    SetRegView 64
  !else if ${ARCH} == 'arm64'
    SetRegView 64
  !else
    SetRegView 32
  !endif

  !ifdef MSVC
  ; MSVC builds use python 3.8+ which dropped windows 7 support and will crash
  ${IfNot} ${AtLeastWin8.1}
      MessageBox MB_OK|MB_TOPMOST $(ERROR_WIN_MIN)
      Quit
  ${EndIf}
  !endif

  !ifdef LIBRARIES_TAG
  StrCpy $DELETE_DOWNLOADED_FILES "unknown"
  !endif

  ReserveFile "install.ico"
  ReserveFile "uninstall.ico"
  ReserveFile "${NSISDIR}\Plugins\x86-unicode\LangDLL.dll"
  ReserveFile "${NSISDIR}\Plugins\x86-unicode\System.dll"
  ;!insertmacro MUI_LANGDLL_DISPLAY
  Goto done

  done:
    Call EnableLiteMode

FunctionEnd

; This handles skipping the welcome/license pages when UAC escalates to the inner installer
Function PageWelcomeLicensePre
	${if} $InstallShowPagesBeforeComponents = 0
		Abort ; don't display the Welcome and License pages
	${endif}
FunctionEnd

Function ModifyFinishPage
  ; resize the Text control, otherwise we get clipping on the top and bottom
  ; Create RECT struct
  System::Call "*${stRECT} .r1"
  ; Find Window info for the window we're displaying
  System::Call "User32::GetWindowRect(i, i) i ($mui.FinishPage.ShowReadme, r1) .r2"
  ; Get left/top/right/bottom
  System::Call "*$1${stRECT} (.r2, .r3, .r4, .r5)"
  System::Free $1
  ; calculate the width, we'll keep this the same
  IntOp $6 $4 - $2
  ; then calculate the height, and we'll make this 4 times as high
  IntOp $7 $5 - $3
  IntOp $7 6 * $7
  ; then we finally update the control size.. we don't want to move it, or change its z-order however
  System::Call "User32::SetWindowPos(i $mui.FinishPage.ShowReadme, i 0, i 0, i 0, i $6, i $7, i ${SWP_NOMOVE} | ${SWP_NOZORDER})"
FunctionEnd

!macro KiCadRunningProccessesCheck
  ${RunningProcessCheck} "kicad.exe" $(APP_NAME_KICAD)
  ${RunningProcessCheck} "pcbnew.exe" $(APP_NAME_PCBNEW)
  ${RunningProcessCheck} "eeschema.exe" $(APP_NAME_EESCHEMA)
  ${RunningProcessCheck} "pl_editor.exe" $(APP_NAME_PLEDITOR)
  ${RunningProcessCheck} "pcb_calculator.exe" $(APP_NAME_PCBCALCULATOR)
  ${RunningProcessCheck} "bitmap2component.exe" $(APP_NAME_BITMAP2COMPONENT)
  ${RunningProcessCheck} "gerbview.exe" $(APP_NAME_GERBVIEW)
!macroend

!macro DownloadAndExtract File Url What ZippedName DestinationBase DestinationName
  ${If} $DELETE_DOWNLOADED_FILES == "unknown"
    StrCpy $DELETE_DOWNLOADED_FILES "no"
    ; ask this only once
    MessageBox MB_ICONQUESTION|MB_YESNO|MB_DEFBUTTON1|MB_TOPMOST $(CLEANUP_PROMPT) /SD IDYES IDNO +2
      StrCpy $DELETE_DOWNLOADED_FILES "yes"
  ${Endif}

  CreateDirectory "${DestinationBase}${DestinationName}"

  IfFileExists "$EXEDIR\${File}" unzip download

  download:
  !insertmacro ExclusiveDetailPrint "Downloading ${Url}"
  inetc::get /caption "Downloading ${What}" /popup "" ${Url} "$EXEDIR\${File}" /end
  Pop $R0
  StrCmp $R0 "OK" complete
    MessageBox MB_ICONEXCLAMATION|MB_ABORTRETRYIGNORE|MB_DEFBUTTON2|MB_TOPMOST "Download failed: $R0" /SD IDIGNORE IDRETRY download IDIGNORE +2
      Abort "Installation aborted."
      Return

  complete:
  !insertmacro ExclusiveDetailPrint "Downloaded ${What} archive to $EXEDIR\${File}"

  unzip:
  nsisunz::UnzipToLog "$EXEDIR\${File}" "${DestinationBase}"
  Pop $R0
  ${If} $R0 == "success"
    CopyFiles /SILENT "${DestinationBase}${ZippedName}\*" "${DestinationBase}${DestinationName}"
    RMDir /r "${DestinationBase}${ZippedName}"
    ${If} $DELETE_DOWNLOADED_FILES == "yes"
      Delete "$EXEDIR\${File}"
    ${EndIf}
  ${Else}
    !insertmacro ExclusiveDetailPrint "Extracting ${What} failed: $R0"
    MessageBox MB_ICONEXCLAMATION|MB_OK|MB_TOPMOST "Extracting ${What} failed: $R0"
    Abort "Installation aborted."
  ${EndIf}
!macroend

!macro ExclusiveDetailPrint Msg
	SetDetailsPrint textonly
	DetailPrint "${Msg}"
	SetDetailsPrint none
!macroend

Function onDirectoryPageLeave
  !insertmacro KiCadRunningProccessesCheck

  ${nsProcess::Unload}
FunctionEnd

!ifdef MSVC
Section -Prerequisites
  !define VCRUNTIME_MINIMUM_BLD 32532 
  !if ${ARCH} == 'x86_64'
    ReadRegDword $R1 HKLM "SOFTWARE\Wow6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x64" "Installed"
    ReadRegDword $R2 HKLM "SOFTWARE\Wow6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x64" "Bld"
    !define VC_REDIST "VC_redist.x64.exe"
  !else if ${ARCH} == 'arm64'
    ReadRegDword $R1 HKLM "SOFTWARE\Wow6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\ARM64" "Installed"
    ReadRegDword $R2 HKLM "SOFTWARE\Wow6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\ARM64" "Bld"
    !define VC_REDIST "VC_redist.arm64.exe"
  !else
    ReadRegDword $R1 HKLM "SOFTWARE\Wow6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x86" "Installed"
    ReadRegDword $R2 HKLM "SOFTWARE\Wow6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x86" "Bld"
    !define VC_REDIST "VC_redist.x86.exe"
  !endif

  SetOutPath "$INSTDIR"

  ${If} $R1 != "1"
    ${OrIf} $R2 < ${VCRUNTIME_MINIMUM_BLD}
      File "vcredist\${VC_REDIST}"
      ${If} ${Silent}
      ExecWait '"$INSTDIR\${VC_REDIST}" /install /quiet /norestart'
      ${Else}
      ExecWait '"$INSTDIR\${VC_REDIST}" /install /passive /norestart'
      ${EndIf}
      Delete "$INSTDIR\${VC_REDIST}"
  ${EndIf}
SectionEnd
!endif

Section $(TITLE_SEC_MAIN) SEC01
  SectionIn RO
  SetOverwrite try
  
  !insertmacro ExclusiveDetailPrint $(INSTALLING_APPS)
  ; delete contents of \bin\ itself to avoid any weird conflicts between versions
  ; not a foolproof solution for all conflicts that could occur
  Delete "$INSTDIR\bin\*.*"
  
  ; clean contents of python because otherwise out of date things can remain and get loaded
  RMDir /r "$INSTDIR\bin\DLLs\"
  RMDir /r "$INSTDIR\bin\Lib\"
  RMDir /r "$INSTDIR\bin\Scripts\"
  RMDir /r "$INSTDIR\bin\plugins\"

  ; clean contents of old names for symbols/footprints
  RMDir /r "$INSTDIR\share\kicad\library"
  RMDir /r "$INSTDIR\share\kicad\modules"

  SetOutPath "$INSTDIR"
  File /nonfatal "..\AUTHORS.txt"
  File /nonfatal "..\COPYRIGHT.txt"
  File /nonfatal "..\license_for_documentation.txt"

  SetOutPath "$INSTDIR\bin"
  File /r "..\bin\*"

  SetOutPath "$INSTDIR\lib"
  File /r "..\lib\*"
  
  SetOutPath "$INSTDIR\etc"
  File /r "..\etc\*"

  SetOutPath "$INSTDIR\share\kicad\internat"
  File /nonfatal /r "..\share\kicad\internat\*"

  SetOutPath "$INSTDIR\share\kicad\template"
  File /nonfatal /r "..\share\kicad\template\*"
  
  SetOutPath "$INSTDIR\share\kicad\resources"
  File /nonfatal /r "..\share\kicad\resources\*"

  SetOutPath "$INSTDIR\share\kicad\schemas"
  File /nonfatal /r "..\share\kicad\schemas\*"

!ifdef MSVC
  !insertmacro ExclusiveDetailPrint $(INSTALLING_PIP)

  StrCpy $R0 "";
  System::Call '${SetEnvironmentVariable}("PYTHONPATH", "$R0").r0'

  StrCpy $R0 "$INSTDIR\bin";
  System::Call '${SetEnvironmentVariable}("PYTHONHOME", "$R0").r0'

  nsExec::Exec '"$INSTDIR\bin\python.exe" -m pip install --upgrade --force-reinstall pip'
  Pop $0 # return value/error/timeout
  Pop $1 # printed text, up to ${NSIS_MAX_STRLEN}
  DetailPrint "$1"
!endif

  SetOutPath "$INSTDIR\share\kicad\scripting\kicad_pyshell"
  File /nonfatal /r "..\share\kicad\scripting\kicad_pyshell\*"

  SetOutPath "$INSTDIR\share\kicad\scripting\plugins"
  File /nonfatal /r "..\share\kicad\scripting\plugins\*"

  ${RegisterApplication} "kicad.exe" "$(APP_FRIENDLY_KICAD) ${KICAD_VERSION}"
  ${RegisterApplication} "pcbnew.exe" "$(APP_FRIENDLY_PCBNEW) ${KICAD_VERSION}"
  ${RegisterApplication} "eeschema.exe" "$(APP_FRIENDLY_EESCHEMA) ${KICAD_VERSION}"
  ${RegisterApplication} "pl_editor.exe" "$(APP_FRIENDLY_PLEDITOR) ${KICAD_VERSION}"
SectionEnd

!macro RecursiveReadOnlyFlagFiles BasePath
    ${if} $MultiUser.InstallMode == "CurrentUser"
      ${RecFindOpen} "${BasePath}" $R0 $R1
      ${RecFindFirst}
        SetFileAttributes "${BasePath}\$R0\$R1" READONLY
      ${RecFindNext}
      ${RecFindClose}
    ${endif}
!macroend

SectionGroup /e $(TITLE_SEC_LIBRARIES) SEC03
  !ifndef LIBRARIES_TAG
  Section $(TITLE_SEC_SCHLIB) SEC03_SCHLIB
    SetOverwrite try
    !insertmacro ExclusiveDetailPrint $(INSTALLING_SCH_LIBS)
    SetOutPath "$INSTDIR\share\kicad\symbols"
    File /nonfatal /r "..\share\kicad\symbols\*"
  
    !insertmacro RecursiveReadOnlyFlagFiles "$INSTDIR\share\kicad\symbols\"
  SectionEnd
  !else
  Section /o $(TITLE_SEC_SCHLIB) SEC03_SCHLIB
    AddSize 24576 ; 24MB
    !insertmacro DownloadAndExtract "${KICAD_SYMBOLS_FILE}" "${KICAD_SYMBOLS_URL}" "symbols" "${KICAD_SYMBOLS_FOLDER}" "$INSTDIR\share\kicad\" "symbols"

    !insertmacro RecursiveReadOnlyFlagFiles "$INSTDIR\share\kicad\symbols\"
  SectionEnd
  !endif

  !ifndef LIBRARIES_TAG
  Section $(TITLE_SEC_FPLIB) SEC03_FOOTPRINTS
    SetOverwrite try
    !insertmacro ExclusiveDetailPrint $(INSTALLING_PCB_LIBS)
    SetOutPath "$INSTDIR\share\kicad\footprints"
    File /nonfatal /r "..\share\kicad\footprints\*"

    !insertmacro RecursiveReadOnlyFlagFiles "$INSTDIR\share\kicad\footprints\"
  SectionEnd
  !else
  Section /o $(TITLE_SEC_FPLIB) SEC03_FOOTPRINTS
    AddSize 81920 ; 80MB
    !insertmacro DownloadAndExtract "${KICAD_FOOTPRINTS_FILE}" "${KICAD_FOOTPRINTS_URL}" "footprints" "${KICAD_FOOTPRINTS_FOLDER}" "$INSTDIR\share\kicad\" "footprints"

    !insertmacro RecursiveReadOnlyFlagFiles "$INSTDIR\share\kicad\footprints\"
  SectionEnd
  !endif

  !ifndef LIBRARIES_TAG
  Section $(TITLE_SEC_PACKAGES3D) SEC03_PACKAGES3D
    SetOverwrite try
    !insertmacro ExclusiveDetailPrint $(INSTALLING_3D_MODELS)
    SetOutPath "$INSTDIR\share\kicad\3dmodels"
    File /nonfatal /r "..\share\kicad\3dmodels\*"
    
    !insertmacro RecursiveReadOnlyFlagFiles "$INSTDIR\share\kicad\3dmodels\"
  SectionEnd
  !else
  Section /o $(TITLE_SEC_PACKAGES3D) SEC03_PACKAGES3D
    AddSize 5767168 ; 5.5GB
    !insertmacro DownloadAndExtract "${KICAD_PACKAGES3D_FILE}" "${KICAD_PACKAGES3D_URL}" "3d models" "${KICAD_PACKAGES3D_FOLDER}" "$INSTDIR\share\kicad\" "3dmodels"

    !insertmacro RecursiveReadOnlyFlagFiles "$INSTDIR\share\kicad\3dmodels\"
  SectionEnd
  !endif
SectionGroupEnd

Section $(TITLE_SEC_DEMOS) SEC05
  SetOverwrite try
  !insertmacro ExclusiveDetailPrint $(INSTALLING_DEMOS)
  SetOutPath "$INSTDIR\share\kicad\demos"
  File /nonfatal /r "..\share\kicad\demos\*"
  SetOutPath "$INSTDIR\share\doc\kicad\tutorials"
  File /nonfatal /r "..\share\doc\kicad\tutorials\*"
SectionEnd

SectionGroup $(TITLE_SEC_DOCS) SEC06
  Section $(LANGUAGE_NAME_EN) SEC06_EN
	!insertmacro ExclusiveDetailPrint $(INSTALLING_DOCUMENTATION)
    SetOverwrite try
    SetOutPath "$INSTDIR\share\doc\kicad\help\en"
    File /nonfatal /r "..\share\doc\kicad\help\en\*"
  SectionEnd
  Section $(LANGUAGE_NAME_DE) SEC06_DE
	!insertmacro ExclusiveDetailPrint $(INSTALLING_DOCUMENTATION)
    SetOverwrite try
    SetOutPath "$INSTDIR\share\doc\kicad\help\de"
    File /nonfatal /r "..\share\doc\kicad\help\de\*"
  SectionEnd
  Section $(LANGUAGE_NAME_ES) SEC06_ES
	!insertmacro ExclusiveDetailPrint $(INSTALLING_DOCUMENTATION)
    SetOverwrite try
    SetOutPath "$INSTDIR\share\doc\kicad\help\es"
    File /nonfatal /r "..\share\doc\kicad\help\es\*"
  SectionEnd
  Section $(LANGUAGE_NAME_FR) SEC06_FR
	!insertmacro ExclusiveDetailPrint $(INSTALLING_DOCUMENTATION)
    SetOverwrite try
    SetOutPath "$INSTDIR\share\doc\kicad\help\fr"
    File /nonfatal /r "..\share\doc\kicad\help\fr\*"
  SectionEnd
  Section $(LANGUAGE_NAME_IT) SEC06_IT
	!insertmacro ExclusiveDetailPrint $(INSTALLING_DOCUMENTATION)
    SetOverwrite try
    SetOutPath "$INSTDIR\share\doc\kicad\help\it"
    File /nonfatal /r "..\share\doc\kicad\help\it\*"
  SectionEnd
  Section $(LANGUAGE_NAME_JA) SEC06_JA
	!insertmacro ExclusiveDetailPrint $(INSTALLING_DOCUMENTATION)
    SetOverwrite try
    SetOutPath "$INSTDIR\share\doc\kicad\help\ja"
    File /nonfatal /r "..\share\doc\kicad\help\ja\*"
  SectionEnd
  Section $(LANGUAGE_NAME_NL) SEC06_NL
	!insertmacro ExclusiveDetailPrint $(INSTALLING_DOCUMENTATION)
    SetOverwrite try
    SetOutPath "$INSTDIR\share\doc\kicad\help\nl"
    File /nonfatal /r "..\share\doc\kicad\help\nl\*"
  SectionEnd
  Section $(LANGUAGE_NAME_PL) SEC06_PL
	!insertmacro ExclusiveDetailPrint $(INSTALLING_DOCUMENTATION)
    SetOverwrite try
    SetOutPath "$INSTDIR\share\doc\kicad\help\pl"
    File /nonfatal /r "..\share\doc\kicad\help\pl\*"
  SectionEnd
  Section $(LANGUAGE_NAME_ZH) SEC06_ZH
	!insertmacro ExclusiveDetailPrint $(INSTALLING_DOCUMENTATION)
    SetOverwrite try
    SetOutPath "$INSTDIR\share\doc\kicad\help\zh"
    File /nonfatal /r "..\share\doc\kicad\help\zh\*"
  SectionEnd
SectionGroupEnd

Section $(TITLE_SEC_FILE_ASSOC) SEC07
  !insertmacro ExclusiveDetailPrint $(SETTING_FILE_ASSOCS)
  ${CreateFileAssociation} "kicad_pcb" "pcbnew.exe" "$(FILE_DESC_KICAD_PCB) ${KICAD_VERSION}" "icon_pcbnew"
  ${CreateFileAssociation} "sch" "eeschema.exe" "$(FILE_DESC_SCH) ${KICAD_VERSION}" "icon_eeschema"
  ${CreateFileAssociation} "kicad_sch" "eeschema.exe" "$(FILE_DESC_SCH) ${KICAD_VERSION}" "icon_eeschema"
  ${CreateFileAssociation} "pro" "kicad.exe" "$(FILE_DESC_PRO) ${KICAD_VERSION}" "icon_kicad"
  ${CreateFileAssociation} "kicad_pro" "kicad.exe" "$(FILE_DESC_PRO) ${KICAD_VERSION}" "icon_kicad"
  ${CreateFileAssociation} "kicad_wks" "pl_editor.exe" "$(FILE_DESC_KICAD_WKS) ${KICAD_VERSION}" "icon_pagelayout_editor"

  WriteRegDWORD ${UNINST_ROOT} "${PRODUCT_UNINST_KEY}" "FileAssocInstalled" "1"
SectionEnd

Section -CreateShortcuts
  !insertmacro ExclusiveDetailPrint $(CREATING_SHORTCUTS)
  SetOutPath $INSTDIR

  RMDir /r "${SMPATH}"
  CreateDirectory "${SMPATH}"
  CreateShortCut "${SMPATH}\Uninstall.lnk" "$INSTDIR\uninstaller.exe"
  CreateShortCut "${SMPATH}\KiCad ${KICAD_VERSION}.lnk" "$INSTDIR\bin\kicad.exe"
  CreateShortCut "${SMPATH}\Schematic Editor ${KICAD_VERSION}.lnk" "$INSTDIR\bin\eeschema.exe"
  CreateShortCut "${SMPATH}\PCB Editor ${KICAD_VERSION}.lnk" "$INSTDIR\bin\pcbnew.exe"
  CreateShortCut "${SMPATH}\Gerber Viewer ${KICAD_VERSION}.lnk" "$INSTDIR\bin\gerbview.exe"
  CreateShortCut "${SMPATH}\Image Converter ${KICAD_VERSION}.lnk" "$INSTDIR\bin\bitmap2component.exe"
  CreateShortCut "${SMPATH}\Calculator Tools ${KICAD_VERSION}.lnk" "$INSTDIR\bin\pcb_calculator.exe"
  CreateShortCut "${SMPATH}\Drawing Sheet Editor ${KICAD_VERSION}.lnk" "$INSTDIR\bin\pl_editor.exe"
  CreateShortCut "${SMPATH}\KiCad ${KICAD_VERSION} Command Prompt.lnk" "%comspec%" '/k "$INSTDIR\bin\kicad-cmd.bat"'

  CreateShortCut "$DESKTOP\KiCad ${KICAD_VERSION}.lnk" "$INSTDIR\bin\kicad.exe"
SectionEnd

Section -CreateAddRemoveEntry
	SetOutPath $INSTDIR
  WriteUninstaller "${UNINSTALL_FILENAME}"

  !insertmacro MULTIUSER_RegistryAddInstallInfo ; add registry keys
SectionEnd

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC01} $(DESC_SEC_MAIN)
  !ifdef LIBRARIES_TAG
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC03_SCHLIB} $(DESC_SEC_SCHLIB_DOWNLOAD)
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC03_FOOTPRINTS} $(DESC_SEC_FPLIB_DOWNLOAD)
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC03_PACKAGES3D} $(DESC_SEC_PACKAGES3D_DOWNLOAD)
  !else
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC03_SCHLIB} $(DESC_SEC_SCHLIB)
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC03_FOOTPRINTS} $(DESC_SEC_FPLIB)
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC03_PACKAGES3D} $(DESC_SEC_PACKAGES3D)
  !endif
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC05} $(DESC_SEC_DEMOS)
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC06} $(DESC_SEC_DOCS)
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC06_EN} $(DESC_SEC_DOCS_EN)
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC06_DE} $(DESC_SEC_DOCS_DE)
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC06_ES} $(DESC_SEC_DOCS_ES)
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC06_FR} $(DESC_SEC_DOCS_FR)
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC06_IT} $(DESC_SEC_DOCS_IT)
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC06_JA} $(DESC_SEC_DOCS_JA)
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC06_NL} $(DESC_SEC_DOCS_NL)
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC06_PL} $(DESC_SEC_DOCS_PL)
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC06_ZH} $(DESC_SEC_DOCS_ZH)
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC07} $(DESC_SEC_FILE_ASSOC)
!insertmacro MUI_FUNCTION_DESCRIPTION_END

Var SemiSilentMode ; installer started uninstaller in semi-silent mode using /SS parameter
Var RunningFromInstaller ; installer started uninstaller using /uninstall parameter
Var RunningAsShellUser ; uninstaller restarted itself under the user of the running shell

Function un.onInit
	${GetParameters} $R0
  
	${GetOptions} $R0 "/uninstall" $R1
	${ifnot} ${errors}
		StrCpy $RunningFromInstaller 1
	${else}
		StrCpy $RunningFromInstaller 0
	${endif}

	${GetOptions} $R0 "/SS" $R1
	${ifnot} ${errors}
		StrCpy $SemiSilentMode 1
		StrCpy $RunningFromInstaller 1
		SetAutoClose true ; auto close (if no errors) if we are called from the installer; if there are errors, will be automatically set to false
	${else}
		StrCpy $SemiSilentMode 0
	${endif}

	${GetOptions} $R0 "/shelluser" $R1
	${ifnot} ${errors}
		StrCpy $RunningAsShellUser 1
	${else}
		StrCpy $RunningAsShellUser 0
	${endif}

	${ifnot} ${UAC_IsInnerInstance}
	${andif} $RunningFromInstaller = 0
		; Restarting the uninstaller using the user of the running shell, in order to overcome the Windows bugs that:
		; - Elevates the uninstallers of single-user installations when called from 'Apps & features' of Windows 10
		; causing them to fail when using a different account for elevation.
		; - Elevates the uninstallers of all-users installations when called from 'Add/Remove Programs' of Control Panel,
		; preventing them of eleveting on their own and correctly recognize the user that started the uninstaller. If a
		; different account was used for elevation, all user-context operations will be performed for the user of that
		; account. In this case, the fix causes the elevetion prompt to be displayed twice (one from Control Panel and
		; one from the uninstaller).
		${if} ${UAC_IsAdmin}
		${andif} $RunningAsShellUser = 0
			${StdUtils.ExecShellAsUser} $0 "$INSTDIR\${UNINSTALL_FILENAME}" "open" "/shelluser $R0"
			Quit
		${endif}
    Call un.PreventMultiInstances
	${endif}

	!insertmacro MULTIUSER_UNINIT
  !insertmacro MUI_UNGETLANGUAGE
FunctionEnd

Function un.onMyGuiInit
  !insertmacro KiCadRunningProccessesCheck

  MessageBox MB_ICONEXCLAMATION|MB_YESNO|MB_DEFBUTTON2|MB_TOPMOST $(UNINST_PROMPT) /SD IDYES IDYES +2
  Abort
FunctionEnd

Function un.onUninstSuccess
  HideWindow
  MessageBox MB_ICONINFORMATION|MB_OK|MB_TOPMOST $(UNINST_SUCCESS) /SD IDOK
FunctionEnd

Section Uninstall
  ;delete uninstaller first
  Delete "$INSTDIR\uninstaller.exe"

  ;remove start menu shortcuts and web page links
  !insertmacro ExclusiveDetailPrint $(REMOVING_SHORTCUTS)
  RMDir /r "${SMPATH}"
  Delete "$DESKTOP\KiCad ${KICAD_VERSION}.lnk"

  ;remove all program files now
  !insertmacro ExclusiveDetailPrint $(REMOVING_APP)
  RMDir /r "$INSTDIR\bin"
  RMDir /r "$INSTDIR\lib"
  RMDir /r "$INSTDIR\footprints"
  RMDir /r "$INSTDIR\symbols"
  RMDir /r "$INSTDIR\template"
  RMDir /r "$INSTDIR\internat"
  RMDir /r "$INSTDIR\demos"
  RMDir /r "$INSTDIR\tutorials"
  RMDir /r "$INSTDIR\help"
  RMDir /r "$INSTDIR\ssl\certs"
  RMDir /r "$INSTDIR\ssl"
  
  !insertmacro ExclusiveDetailPrint $(REMOVING_LIBRARIES)
  RMDir /r "$INSTDIR\share\symbols"
  RMDir /r "$INSTDIR\share\footprints"
  RMDir /r "$INSTDIR\share\kicad\template"
  RMDir /r "$INSTDIR\share\kicad\internat"
  RMDir /r "$INSTDIR\share\kicad\demos"
  
  !insertmacro ExclusiveDetailPrint $(REMOVING_DOCS)
  RMDir /r "$INSTDIR\share\doc\kicad\tutorials"
  RMDir /r "$INSTDIR\share\doc\kicad\help"
  RMDir /r "$INSTDIR\share\doc\kicad"
  RMDir /r "$INSTDIR\share\doc"
  RMDir /r "$INSTDIR\share"
  ;don't remove $INSTDIR recursively just in case the user has installed it in c:\ or
  ;c:\program files as this would attempt to delete a lot more than just this package
  Delete "$INSTDIR\*.txt"
  RMDir "$INSTDIR"

  ;remove file association only if it was installed
  ClearErrors
  ReadRegDWORD $0 ${UNINST_ROOT} "${PRODUCT_UNINST_KEY}" "FileAssocInstalled"
  IfErrors FinishUninstall 0

  IntCmp $0 1 0 FinishUninstall FinishUninstall

  ;delete file associations
  !insertmacro ExclusiveDetailPrint $(REMOVING_FILE_ASSOC)
  ${DeleteFileAssociation} "kicad_pcb"
  ${DeleteFileAssociation} "sch"
  ${DeleteFileAssociation} "kicad_sch"
  ${DeleteFileAssociation} "pro"
  ${DeleteFileAssociation} "kicad_pro"
  ${DeleteFileAssociation} "kicad_wks"

  FinishUninstall:
  ;Note - application registry keys are stored in the users individual registry hive (HKCU\Software\kicad".
  ;It might be possible to remove these keys as well but it would require a lot of testing of permissions
  ;and access to other people's registry entries. So for now we will leave the application registry keys.

  ;remove installation registary keys
  !insertmacro MULTIUSER_RegistryRemoveInstallInfo ; Remove registry keys	
  SetAutoClose true
SectionEnd

Function PreventMultiInstances
  System::Call 'kernel32::CreateMutexA(i 0, i 0, t "kicad-installer-${KICAD_VERSION}") i .r1 ?e'
  Pop $R0
  StrCmp $R0 0 +3
  MessageBox MB_OK|MB_ICONEXCLAMATION|MB_TOPMOST $(INSTALLER_RUNNING) /SD IDOK
  Abort
FunctionEnd

Function un.PreventMultiInstances
  System::Call 'kernel32::CreateMutexA(i 0, i 0, t "kicad-installer-${KICAD_VERSION}") i .r1 ?e'
  Pop $R0
  StrCmp $R0 0 +3
  MessageBox MB_OK|MB_ICONEXCLAMATION|MB_TOPMOST $(UNINSTALLER_RUNNING) /SD IDOK
  Abort
FunctionEnd

!macro CompileTimeIfFileExist path define
  !tempfile tmpinc
  !system 'IF EXIST "${path}" echo !define ${define} > "${tmpinc}"'
  !include "${tmpinc}"
  !delfile "${tmpinc}"
  !undef tmpinc
!macroend

Function EnableLiteMode
  ; TODO: Add override string for lite mode
  !insertmacro CompileTimeIfFileExist "..\share\kicad\symbols" ADD_LIBS
  !ifndef ADD_LIBS
    !insertmacro SetSectionFlag ${SEC03_SCHLIB} ${SF_RO}
    !insertmacro UnselectSection ${SEC03_SCHLIB}
  !endif

  !insertmacro CompileTimeIfFileExist "..\share\kicad\footprints" ADD_MODULES
  !ifndef ADD_MODULES
    !insertmacro SetSectionFlag ${SEC03_FOOTPRINTS} ${SF_RO}
    !insertmacro UnselectSection ${SEC03_FOOTPRINTS}
  !endif

  !insertmacro CompileTimeIfFileExist "..\share\doc\kicad\help" ADD_HELP
  !ifndef ADD_HELP
    !insertmacro SetSectionFlag ${SEC06} ${SF_RO}
    !insertmacro UnselectSection ${SEC06}
    !insertmacro SetSectionFlag ${SEC06_EN} ${SF_RO}
    !insertmacro UnselectSection ${SEC06_EN}
    !insertmacro SetSectionFlag ${SEC06_DE} ${SF_RO}
    !insertmacro UnselectSection ${SEC06_DE}
    !insertmacro SetSectionFlag ${SEC06_ES} ${SF_RO}
    !insertmacro UnselectSection ${SEC06_ES}
    !insertmacro SetSectionFlag ${SEC06_FR} ${SF_RO}
    !insertmacro UnselectSection ${SEC06_FR}
    !insertmacro SetSectionFlag ${SEC06_IT} ${SF_RO}
    !insertmacro UnselectSection ${SEC06_IT}
    !insertmacro SetSectionFlag ${SEC06_JA} ${SF_RO}
    !insertmacro UnselectSection ${SEC06_JA}
    !insertmacro SetSectionFlag ${SEC06_NL} ${SF_RO}
    !insertmacro UnselectSection ${SEC06_NL}
    !insertmacro SetSectionFlag ${SEC06_PL} ${SF_RO}
    !insertmacro UnselectSection ${SEC06_PL}
    !insertmacro SetSectionFlag ${SEC06_ZH} ${SF_RO}
    !insertmacro UnselectSection ${SEC06_ZH}
  !endif
FunctionEnd
