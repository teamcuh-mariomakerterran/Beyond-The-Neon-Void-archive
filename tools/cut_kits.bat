@echo off
rem Double-click me: cuts every building-kit sheet in tools\handoff\kits and every auto-tile sheet in
rem tools\handoff\autotiles into pieces (assets\tiles\kits, assets\tiles\autotiles) and pre-fills
rem data\kits.json and data\autotiles.json. Slots you changed in the Kit map tab are kept.
setlocal
if "%GODOT%"=="" set GODOT=godot
cd /d "%~dp0.."
"%GODOT%" --headless -s tools/art/cut_kit.gd
pause
