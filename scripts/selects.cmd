@echo off
rem Cuenta las lecturas SQL a la tabla alumnos registradas hasta ahora en el log de la app.
rem Requiere haber iniciado la app con SQL_LOG=DEBUG.
for /f %%n in ('docker compose logs app ^| find /c /i "from alumnos"') do echo Lecturas SQL a alumnos acumuladas: %%n
