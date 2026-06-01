@echo off
echo Building Trestle Track Builder for web...
flutter build web --release
if %errorlevel% neq 0 (
    echo Build failed!
    exit /b %errorlevel%
)
echo.
echo Starting server on http://localhost:8765...
cd build\web
python -m http.server 8765
