;--------------------------------

!macro _RunningProcessCheck EXE NICENAME
  Push $R0
  ${nsProcess::FindProcess} ${EXE} $R0

  ${If} $R0 == "0"
    Push $R1
    StrCpy $R1 ${NICENAME}

    MessageBox mb_ok|mb_iconinformation $(PROGRAM_IS_OPEN_ERROR)

    Pop $R1
    Exch $R0
    Abort
  ${Else}
    Pop $R0
  ${EndIf}

!macroend

!define RunningProcessCheck `!insertmacro _RunningProcessCheck`