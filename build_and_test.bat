@echo off

cd %~dp0\test

rem compile
ponyc
if %errorlevel% neq 0 exit /b %errorlevel%

rem test
test.exe
if %errorlevel% neq 0 exit /b %errorlevel%

cd %~dp0
