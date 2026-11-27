@echo off
rem Uso: call scripts\csrf.cmd USUARIO CLAVE ARCHIVO_COOKIES
rem Pide un token CSRF y guarda la cookie JSESSIONID de esa sesion en ARCHIVO_COOKIES.
rem Deja el token en la variable CSRF de la ventana actual de cmd.
for /f "delims=" %%i in ('powershell -NoProfile -Command "(curl.exe -s -c %3 -b %3 -u %1:%2 http://localhost:8080/api/v1/csrf | ConvertFrom-Json).token"') do set CSRF=%%i
echo CSRF=%CSRF%
