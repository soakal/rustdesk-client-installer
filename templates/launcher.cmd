@echo off
:: Double-click me. Everything after the #__PS__ line is the PowerShell installer; this part only
:: gets admin rights (one "Yes" click), runs it, and keeps the window open so the result can be read.
title __TITLE__ setup
set "RDSELF=%~f0"
rem Not admin yet: relaunch elevated via cmd.exe (relaunching this downloaded file itself would show
rem the "publisher could not be verified" box twice). cmd /s /c with doubled quotes survives special characters in the path.
fltmc >nul 2>&1 || (
  echo Windows will now ask "Do you want to allow this app to make changes to your device?" - click Yes.
  powershell -NoProfile -Command "try { Start-Process -Verb RunAs -FilePath cmd.exe -ArgumentList ('/s /c \"\"' + $env:RDSELF + '\"\"') } catch { exit 1 }" || (
    echo.
    echo You clicked No, so nothing was installed. Double-click this file again and click Yes.
    pause
  )
  exit /b
)
rem Run the PowerShell part straight from this file, in memory: no copy left in a user-writable temp folder.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s = Get-Content -Raw -LiteralPath $env:RDSELF; & ([scriptblock]::Create($s.Substring($s.LastIndexOf('#__PS__'))))"
echo.
pause
exit /b
#__PS__
