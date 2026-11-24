@echo off
rem Starts RFSoCBeamformer.exe with an installed MATLAB R2026a instead of the Runtime.
set "ML=C:\Program Files\MATLAB\R2026a"
if exist "%ML%\bin\win64" set "PATH=%ML%\runtime\win64;%ML%\bin\win64;%PATH%"
start "" "%~dp0RFSoCBeamformer.exe" %*
