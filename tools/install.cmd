@echo off
if "%REMOTE_TRAY_TESTMODE%"=="1" (
    if "%REMOTE_TRAY_TEST_INSTALLDIR%"=="" exit /b 10
    if "%REMOTE_TRAY_TEST_DATADIR%"=="" exit /b 11
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Manage-RemoteCommanderTray.ps1" -Action Install -TestMode -InstallDir "%REMOTE_TRAY_TEST_INSTALLDIR%" -DataDir "%REMOTE_TRAY_TEST_DATADIR%"
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Manage-RemoteCommanderTray.ps1" -Action Install
)
exit /b %ERRORLEVEL%
