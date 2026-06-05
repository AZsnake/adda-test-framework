@echo off
cd /d "%~dp0"
python gui\adda_test_gui_qt.py
if errorlevel 1 pause
