;--------------------------------
; File Association Helpers

!macro _DeleteFileAssociationFunc EXT
  ;be sure to only delete the specific kicad.extension.version entry
  DeleteRegValue ${SOFTWARE_CLASSES_ROOT_KEY} "Software\Classes\.${EXT}\OpenWithProgids\" "${FILE_ASSOC_PREFIX}.${EXT}.${KICAD_VERSION}"
  ;delete the entire kicad.extension.version key set
  DeleteRegKey ${SOFTWARE_CLASSES_ROOT_KEY} "Software\Classes\${FILE_ASSOC_PREFIX}.${EXT}.${KICAD_VERSION}"
!macroend

!macro _CreateFileAssociationFunc
  Exch $R0 ;ext
  Exch
  Exch $R1 ;exe
  Exch
  Exch 2
  Exch $R2 ;desc
  Exch 2
  Exch 3
  Exch $R3 ;ICON_RESOURCE_NAME

  ;global extension reference to program
  WriteRegExpandStr ${SOFTWARE_CLASSES_ROOT_KEY} "Software\Classes\.$R0\OpenWithProgids\" "${FILE_ASSOC_PREFIX}.$R0.${KICAD_VERSION}" ""

  ;program level extension entry
  WriteRegExpandStr ${SOFTWARE_CLASSES_ROOT_KEY} "Software\Classes\${FILE_ASSOC_PREFIX}.$R0.${KICAD_VERSION}" "" "$R2"
  WriteRegExpandStr ${SOFTWARE_CLASSES_ROOT_KEY} "Software\Classes\${FILE_ASSOC_PREFIX}.$R0.${KICAD_VERSION}\" "DefaultIcon" "$INSTDIR\bin\$R1,$R3"
  WriteRegExpandStr ${SOFTWARE_CLASSES_ROOT_KEY} "Software\Classes\${FILE_ASSOC_PREFIX}.$R0.${KICAD_VERSION}\shell\open\command" "" '$INSTDIR\bin\$R1 "%1"'

  Pop $R3
  Pop $R2
  Pop $R1
  Pop $R0
!macroend

!macro CreateFileAssociationCall EXT EXE DESCRIPTION ICON_RESOURCE_NAME
  Push `${ICON_RESOURCE_NAME}`
  Push `${DESCRIPTION}`
  Push `${EXE}`
  Push `${EXT}`
  ${CallArtificialFunction} _CreateFileAssociationFunc
!macroend

!define CreateFileAssociation `!insertmacro CreateFileAssociationCall`
!define DeleteFileAssociation `!insertmacro _DeleteFileAssociationFunc`

;--------------------------------

!macro _RegisterApplicationFunc
  Exch $R0 ;exe
  Exch
  Exch $R1 ;desc

  ;global extension reference to program
  ; We need this delete because we previously create the FriendlyAppName string subkey, the problem
  ; Windows would then use this friendly name and disable it over all versions of KiCad in the open with
  ; It essentially acts as the highest priority override for file extension association naming
  DeleteRegKey ${SOFTWARE_CLASSES_ROOT_KEY} "Software\Classes\Applications\$R0\shell\open"
  WriteRegExpandStr ${SOFTWARE_CLASSES_ROOT_KEY} "Software\Classes\Applications\$R0\shell\open\command" "" '$INSTDIR\bin\$R0 "%1"'

  Pop $R1
  Pop $R0
!macroend

!macro RegisterApplicationCall EXE DESCRIPTION
  Push `${DESCRIPTION}`
  Push `${EXE}`
  ${CallArtificialFunction} _RegisterApplicationFunc
!macroend

!define RegisterApplication `!insertmacro RegisterApplicationCall`