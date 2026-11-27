# Backend académico (U12): entrega reproducible

Todo se ejecuta en **cmd de Windows**, en orden, sin IDE. Los resultados esperados salen de leer el código; si algo no coincide, anota lo que viste y compáralo con la sección indicada.

Usuarios de laboratorio:

| Usuario | Clave | Rol | Nota |
|---|---|---|---|
| `docente` | `docente123` | DOCENTE | crea, edita, lista |
| `alumno` | `alumno123` | ALUMNO | no es propietario de ninguna matrícula |
| `a001` | `alumno123` | ALUMNO | propietario de la matrícula `A001` |
| `admin` | `admin123` | ADMIN | actuator |

---

## 0. Requisitos y versiones (JDK 25 y Java 21)

- **JDK 25** ejecuta Maven y es el JDK de la imagen Docker (`eclipse-temurin:25-jre`).
- **Java 21** es el nivel del código: el `pom.xml` fija `maven.compiler.release=21`, así que el bytecode y la API son de Java 21 aunque compile JDK 25. Un JDK 21 también debería compilarlo; lo único que cambia es lo que muestra `java -version`.
- Docker Desktop iniciado (las pruebas usan Testcontainers) y acceso a internet la primera vez (Maven Wrapper y dependencias).
- `curl.exe` y PowerShell vienen con Windows 10/11; los scripts de `scripts\` los usan.

```cmd
java -version
echo %JAVA_HOME%
docker version
```

Debe verse Java 25 y un servidor Docker activo.

## 1. Carpeta limpia

```cmd
mkdir C:\entrega
cd C:\entrega
tar -xf C:\ruta\prj-entrega.zip
cd C:\entrega
dir
```

Debes ver `pom.xml`, `compose.yaml`, `Dockerfile`, `demo\`, `scripts\`, `src\`.

Estado limpio de datos (esto **borra** el volumen de PostgreSQL de ese proyecto; sólo se usa aquí, al empezar):

```cmd
docker compose down -v
```

## 2. Construcción y pruebas

```cmd
.\mvnw.cmd -v
.\mvnw.cmd clean test package
```

Esperado: `BUILD SUCCESS` y `target\backend-academico-0.0.12-SNAPSHOT.jar`. Si falla `PostgresIntegrationTest`, casi siempre Docker no está iniciado.

Comprueba que el bytecode es Java 21:

```cmd
javap -v -cp target\classes mx.edu.backendacademico.BackendAcademicoApplication | findstr /c:"major version"
```

Esperado: `major version: 65` (Java 21).

## 3. Inicio

`SQL_LOG=DEBUG` hace que la app registre cada SQL; lo usaremos como evidencia de la caché.

```cmd
set SQL_LOG=DEBUG
docker compose build
docker compose up -d
docker compose ps
timeout /t 20 /nobreak
docker compose logs app
docker compose exec app java -version
```

Esperado: `postgres` healthy, `app` Up; en el log `Started BackendAcademicoApplication` y `using Java 25`; `java -version` dentro del contenedor muestra 25.

Salud (sin credenciales) y métricas (reservadas a ADMIN):

```cmd
curl -i http://localhost:8080/actuator/health
curl -i http://localhost:8080/actuator/health/liveness
curl -i http://localhost:8080/actuator/health/readiness
curl -i http://localhost:8080/actuator/metrics
curl -i -u docente:docente123 http://localhost:8080/actuator/metrics
curl -i -u admin:admin123 http://localhost:8080/actuator/metrics
```

Esperado: tres `200 {"status":"UP"}`; métricas: `401` sin credenciales, `403` con docente, `200` con admin.

## 4. Demostraciones HTTP (éxito, 400, 404, 409)

Cada `POST/PUT/DELETE` necesita un token CSRF **de la misma sesión** que la cookie. El script lo pide, guarda la cookie en el archivo indicado y deja el token en la variable `%CSRF%`. Que el token cambie en cada llamada es normal (Spring lo enmascara); cualquiera sirve mientras viaje la cookie de su sesión.

```cmd
call scripts\csrf.cmd docente docente123 cj.txt
```

**4.1 Éxito, 201**

```cmd
curl -i -b cj.txt -c cj.txt -u docente:docente123 -X POST http://localhost:8080/api/v1/alumnos -H "X-CSRF-TOKEN: %CSRF%" -H "Content-Type: application/json" -d @demo\alumno-a001.json
```

Esperado: `201`, `Location: /api/v1/alumnos/1`, cuerpo con matrícula `A001`.

**4.2 Validación, 400**

```cmd
curl -i -b cj.txt -c cj.txt -u docente:docente123 -X POST http://localhost:8080/api/v1/alumnos -H "X-CSRF-TOKEN: %CSRF%" -H "Content-Type: application/json" -d @demo\alumno-invalido.json
```

Esperado: `400`, `"codigo":"DATOS_INVALIDOS"` y la lista `campos` (matrícula, nombre, correo) sin el valor rechazado.

**4.3 Ausencia, 404**

```cmd
curl -i -u docente:docente123 http://localhost:8080/api/v1/alumnos/9999
```

Esperado: `404`, `"codigo":"ALUMNO_NO_ENCONTRADO"`.

**4.4 Conflicto, 409** (repite la matrícula `A001`)

```cmd
curl -i -b cj.txt -c cj.txt -u docente:docente123 -X POST http://localhost:8080/api/v1/alumnos -H "X-CSRF-TOKEN: %CSRF%" -H "Content-Type: application/json" -d @demo\alumno-a001.json
```

Esperado: `409`, `"codigo":"MATRICULA_DUPLICADA"`.

**Preparación** para la sección siguiente: segundo alumno (id 2).

```cmd
curl -i -b cj.txt -c cj.txt -u docente:docente123 -X POST http://localhost:8080/api/v1/alumnos -H "X-CSRF-TOKEN: %CSRF%" -H "Content-Type: application/json" -d @demo\alumno-b002.json
```

Esperado: `201` con `Location: /api/v1/alumnos/2`.

## 5. Rechazos de seguridad: cada uno con una causa distinta

La técnica es cambiar **una sola variable** por vez, como hace `SeguridadTest`.

| # | Petición | Resultado | Causa |
|---|---|---|---|
| 5.1 | sin credenciales | 401 | no hay identidad |
| 5.2 | docente, sin token | 403 | falta CSRF (el rol sí alcanza) |
| 5.3 | alumno, con token válido | 403 | rol insuficiente (el token sí es válido) |
| 5.4 | a001 pide el registro de otro | 403 | no es propietario (rol y token no intervienen) |

**5.1 Sin credenciales, 401**

```cmd
curl -i http://localhost:8080/api/v1/alumnos/1
```

Esperado: `401` y `WWW-Authenticate: Basic`.

**5.2 Falta CSRF, 403** (docente, cuerpo válido, sin cabecera de token)

```cmd
curl -i -b cj.txt -u docente:docente123 -X POST http://localhost:8080/api/v1/alumnos -H "Content-Type: application/json" -d @demo\alumno-c003.json
```

Esperado: `403` con cuerpo vacío. Es el mismo caso que 4.1, con una única diferencia: falta `X-CSRF-TOKEN`.

**5.3 Rol insuficiente, 403** (token válido de la sesión de `alumno`)

```cmd
call scripts\csrf.cmd alumno alumno123 cj-alumno.txt
curl -i -b cj-alumno.txt -u alumno:alumno123 -X POST http://localhost:8080/api/v1/alumnos -H "X-CSRF-TOKEN: %CSRF%" -H "Content-Type: application/json" -d @demo\alumno-c003.json
```

Esperado: `403` con cuerpo vacío. El token es correcto: aquí el que rechaza es el rol.

Comprueba que ninguno de los dos creó a `C003`:

```cmd
curl -u docente:docente123 http://localhost:8080/api/v1/alumnos
```

Esperado: sólo `A001` y `B002`.

**5.4 Propietario, 403** (mejora de la sección 9)

```cmd
curl -i -u a001:alumno123 http://localhost:8080/api/v1/alumnos/1
curl -i -u a001:alumno123 http://localhost:8080/api/v1/alumnos/2
curl -i -u a001:alumno123 http://localhost:8080/api/v1/alumnos
```

Esperado: `200` (su registro); `403` con JSON `"Solo puedes consultar tu propio registro"`; `403` por rol en el listado.

## 6. Caché: evidencia con SQL

`scripts\selects.cmd` cuenta las lecturas SQL a `alumnos` acumuladas en el log. Lo que importa es la **diferencia** entre un conteo y el siguiente.

```cmd
call scripts\csrf.cmd docente docente123 cj.txt
curl -s -b cj.txt -c cj.txt -u docente:docente123 -X PUT http://localhost:8080/api/v1/alumnos/1 -H "X-CSRF-TOKEN: %CSRF%" -H "Content-Type: application/json" -d @demo\actualizar-ada-byron.json
```

El `PUT` vacía la caché, así que partimos en frío.

```cmd
scripts\selects.cmd
curl -s -u docente:docente123 http://localhost:8080/api/v1/alumnos/1
scripts\selects.cmd
curl -s -u docente:docente123 http://localhost:8080/api/v1/alumnos/1
scripts\selects.cmd
```

Esperado: el conteo **sube** tras la primera consulta (falló la caché, fue a PostgreSQL) y **no cambia** tras la segunda (respondió la caché).

Modificar y volver a consultar:

```cmd
curl -s -b cj.txt -c cj.txt -u docente:docente123 -X PUT http://localhost:8080/api/v1/alumnos/1 -H "X-CSRF-TOKEN: %CSRF%" -H "Content-Type: application/json" -d @demo\actualizar-ada-lovelace.json
curl -s -u docente:docente123 http://localhost:8080/api/v1/alumnos/1
scripts\selects.cmd
```

Esperado: el nombre vuelve a `Ada Lovelace` y el conteo sube otra vez (la escritura invalidó la caché).

Costo de la caché (dato obsoleto): cambia la fila **sin pasar por la app**.

```cmd
docker compose exec postgres psql -U academico -d academico -c "UPDATE alumnos SET nombre='Editado en SQL' WHERE id=1"
curl -s -u docente:docente123 http://localhost:8080/api/v1/alumnos/1
docker compose restart app
timeout /t 20 /nobreak
curl -s -u docente:docente123 http://localhost:8080/api/v1/alumnos/1
```

Esperado: `UPDATE 1`; la primera consulta sigue mostrando `Ada Lovelace` (obsoleto); tras reiniciar la app muestra `Editado en SQL`.

## 7. Falla controlada de PostgreSQL y readiness

Primero un token (no depende de la base) y la línea base:

```cmd
call scripts\csrf.cmd docente docente123 cj.txt
curl -i http://localhost:8080/actuator/health/readiness
```

Detén **sólo** PostgreSQL (conserva el volumen):

```cmd
docker compose stop postgres
curl -i --max-time 30 http://localhost:8080/actuator/health/readiness
curl -i http://localhost:8080/actuator/health/liveness
curl -i --max-time 30 -u admin:admin123 http://localhost:8080/actuator/health/readiness
curl -i --max-time 30 -b cj.txt -u docente:docente123 -X POST http://localhost:8080/api/v1/alumnos -H "X-CSRF-TOKEN: %CSRF%" -H "Content-Type: application/json" -d @demo\alumno-c003.json
docker compose logs --tail 40 app | findstr /i "referencia"
```

Esperado y por qué:

- **readiness → 503 `DOWN`**: el grupo incluye `readinessState,db` (`application.properties`); al fallar la base la app deja de declararse lista para recibir tráfico. Con credenciales de admin se ve el componente `db` en `DOWN`; sin ellas, sólo el estado. La respuesta tarda unos 3 s por `hikari.connection-timeout=3000` (con el valor por defecto de 30 s el chequeo se quedaría esperando).
- **liveness → 200 `UP`**: el proceso está vivo y reiniciarlo no arreglaría nada; por eso liveness no depende de la base.
- **POST → 500 `ERROR_INTERNO`** con una `referencia` UUID; esa misma referencia aparece en el log con el tipo de excepción, sin datos del cliente. No se crea el alumno.
- El resumen programado fallará en el log mientras dure la caída.
- Observación opcional: consulta un alumno que ya estaba en caché (`curl -s -u docente:docente123 http://localhost:8080/api/v1/alumnos/1`). Puede responder 200 desde la caché o 500, según si la transacción se abre antes que la caché; anota lo que veas y no lo des por supuesto.

Recuperación **sin reiniciar la app**:

```cmd
docker compose start postgres
timeout /t 15 /nobreak
curl -i http://localhost:8080/actuator/health/readiness
curl -i -b cj.txt -c cj.txt -u docente:docente123 -X POST http://localhost:8080/api/v1/alumnos -H "X-CSRF-TOKEN: %CSRF%" -H "Content-Type: application/json" -d @demo\alumno-c003.json
```

Esperado: readiness vuelve a `200 UP` y el `POST` da `201`. Si el `POST` da 403, el token venía de otra sesión: repite `call scripts\csrf.cmd docente docente123 cj.txt`.

## 8. Resumen programado, persistencia y cierre

Espera más de un minuto desde el arranque de la app y consulta el contador (ADMIN) y el log:

```cmd
curl -s -u admin:admin123 http://localhost:8080/actuator/metrics/academico.resumen.ejecuciones
docker compose logs app | findstr /c:"Total de inscripciones"
```

Esperado: `COUNT` mayor que 0 y líneas `Total de inscripciones=N`.

Persistencia: reinicia la app y luego baja **todo** conservando el volumen (no uses `-v`):

```cmd
docker compose restart app
timeout /t 20 /nobreak
curl -s -u docente:docente123 http://localhost:8080/api/v1/alumnos
docker compose down
docker compose up -d
timeout /t 25 /nobreak
curl -s -u docente:docente123 http://localhost:8080/api/v1/alumnos
docker compose down
```

Esperado: ambas listas contienen `A001`, `B002` y `C003`. Las sesiones y la caché sí se pierden en cada reinicio; los datos no.

Para dejar la máquina limpia al terminar la revisión (borra datos):

```cmd
docker compose down -v
del cj.txt cj-alumno.txt
```

---

## 9. Decisiones

### Caché

**Decisión:** conservar `@Cacheable` en `buscar(id)` y `listar()`, con invalidación total (`allEntries`) en cada escritura, **sólo mientras** se cumpla que hay una única instancia y que toda escritura pasa por `AlumnoService`. No se cachean las inscripciones ni ninguna decisión de autorización.

**Argumentos:**

1. *Hay evidencia de que funciona:* en la sección 6 la segunda lectura no genera SQL.
2. *Es correcta bajo esas condiciones:* `TransactionAwareCacheManagerProxy` aplica put/evict al hacer commit, así que un rollback no deja la caché a medias. Invalidar todo en cada escritura es tosco, pero sencillo y no puede dejar la lista desactualizada respecto a un alumno.
3. *Su costo también está demostrado:* un `UPDATE` directo en PostgreSQL no se refleja hasta reiniciar (sección 6); no hay TTL ni límite de tamaño, y cada JVM tiene su propia copia.
4. *Inscripciones fuera:* el cupo depende de un conteo bajo bloqueo; cachearlo rompería la regla que `InscripcionService` protege.
5. *Autorización fuera:* la comprobación de propietario ocurre en el controlador, después de la lectura. Así la entrada de caché es la misma para todos y nunca contiene una decisión por usuario.

**Cuándo se revisa:** al tener más de una réplica, escrituras directas en la base o crecimiento de datos. Entonces: Caffeine con TTL y `maximumSize`, o quitar la caché (una búsqueda por clave primaria es barata).

### Mejora de acceso por propietario

**Problema:** cualquier usuario con rol ALUMNO podía listar todos los alumnos y leer el registro de cualquier id (acceso a objeto sin comprobar su dueño).

**Cambio:**

- `SecurityConfig`: `GET /api/v1/alumnos` (listado) sólo DOCENTE/ADMIN; `GET /api/v1/alumnos/{id}` sigue abierto a los tres roles.
- `AlumnoController.buscar`: DOCENTE/ADMIN ven cualquiera; un ALUMNO sólo si su usuario coincide con la matrícula del registro (`a001` ↔ `A001`); si no, 403.
- Pruebas nuevas en `SeguridadTest` (propio, ajeno, listado, docente).

**Límites asumidos:**

- La relación usuario↔matrícula es una convención del laboratorio; en un sistema real se guardaría como dato (usuario propietario en la tabla `alumnos` o una tabla de usuarios), no como coincidencia de nombres.
- Se responde 403 y no 404 para que el rechazo sea diagnosticable; a cambio, quien conozca un id sabe que existe. Con ids secuenciales eso aquí es poco relevante; si importara, se devolvería 404 en ambos casos.
- El historial de inscripciones sigue reservado a DOCENTE/ADMIN; abrirlo al propietario es el siguiente paso natural.

### Otros cambios para poder repetir las observaciones

- `compose.yaml`: `LOGGING_LEVEL_ORG_HIBERNATE_SQL` configurable con `SQL_LOG`.
- `application.properties`: `hikari.connection-timeout=3000` y `validation-timeout=2000`, para que la falla de PostgreSQL se vea en segundos.
- `requests.http`: el token ya no está escrito a mano; se captura en `{{csrf}}`.
- `scripts\` y `demo\`: pedir el token con su cookie, contar SQL y cuerpos JSON, para no depender de comillas en cmd.
