@echo off
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >nul
cd /d %~dp0
cl /nologo /EHsc /std:c++17 /O2 hdrcap.cpp /link d3d11.lib dxgi.lib windowsapp.lib user32.lib
