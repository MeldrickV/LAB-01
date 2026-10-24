# LAB-01 — Protección y privacidad de datos

**Materia:** Gestión de Seguridad y Desempeño de Bases de Datos  
**Unidad:** II — Seguridad, privacidad y control de acceso  
**Tema:** 2.3 — Datos sensibles, privacidad y protección de la información  
**Alumno:** José Meldrick Rafael Vega Vega  
**Motor:** PostgreSQL 16  
**Modalidad:** Práctica individual

## 1. Descripción

Este laboratorio implementa, sobre la base de datos ficticia de
**Comercializadora Norte S.A. de C.V.**, un conjunto de controles para que
distintas áreas utilicen la información de clientes sin acceder a más datos de
los necesarios:

| Área | Necesidad | Control implementado |
| --- | --- | --- |
| Soporte | Identificar al cliente sin ver todos sus datos | Vista con enmascaramiento y acceso denegado a la tabla base |
| Analítica | Analizar patrones sin conocer la identidad | Seudonimización con tokens y mapa de correspondencia separado |
| Dirección | Consultar estadísticas | Generalización, agregación y supresión de grupos pequeños |
| DBA / seguridad | Administrar y controlar accesos | Roles, GRANT/REVOKE, esquemas separados y política de retención |

El objetivo no es solo que las consultas funcionen, sino demostrar **qué
problema de seguridad resuelve cada mecanismo, qué riesgo permanece y por qué
el control elegido es adecuado**.

## 2. Estructura del repositorio

```text
LAB-01/
├── README.md
├── informe.md
├── sql/
│   ├── 00-preparacion.sql
│   ├── 01-clasificacion.sql
│   ├── 02-enmascaramiento.sql
│   ├── 03-seudonimizacion.sql
│   ├── 04-anonimizacion.sql
│   ├── 05-retencion.sql
│   └── 99-verificacion-final.sql
└── evidencias/
    ├── 01-clasificacion.pdf
    ├── 02-enmascaramiento.pdf
    ├── 03-seudonimizacion.pdf
    ├── 04-anonimizacion.pdf
    └── 05-retencion.pdf
```

Los PDF de evidencia se encuentran en `evidencias/`.

## 3. Requisitos

- PostgreSQL 16 (el laboratorio fue ejecutado con PostgreSQL 16.15).
- `psql` en el `PATH`.
- Un rol con privilegios de administración para crear roles, esquemas y la
  extensión `pgcrypto` (por ejemplo, `postgres` o el propietario de la base).

## 4. Ejecución

### 4.1 Crear la base de datos

```bash
sudo -u postgres createdb lab01
```

### 4.2 Ejecutar los scripts en orden

Todos los scripts se conectan a la base `lab01`. El script `00` es
idempotente: elimina y vuelve a crear los objetos del escenario.

```bash
psql -d lab01 -f sql/00-preparacion.sql
psql -d lab01 -f sql/01-clasificacion.sql
psql -d lab01 -f sql/02-enmascaramiento.sql
psql -d lab01 -f sql/03-seudonimizacion.sql
psql -d lab01 -f sql/04-anonimizacion.sql
psql -d lab01 -f sql/05-retencion.sql
```

Los scripts `02`, `03` y `99` contienen **errores intencionales** para
demostrar que el acceso fue rechazado. Por eso verás mensajes como
`permission denied for table clientes`: son la evidencia esperada, no fallas
del laboratorio. Dentro de cada script se desactiva temporalmente
`ON_ERROR_STOP` alrededor de esos intentos.

### 4.3 Verificación consolidada

```bash
psql -d lab01 -f sql/99-verificacion-final.sql
```

> El laboratorio se ejecutó sobre una instancia PostgreSQL 16 aislada
> (`127.0.0.1:55432`), creada para ejecutarlo de forma reproducible sin
> depender de la configuración local.

## 5. Decisiones de diseño

1. **Enmascaramiento dinámico mediante vista.** La tabla `clientes` conserva
   los valores originales; la vista `v_clientes_soporte` calcula la
   representación enmascarada en cada consulta. El rol `soporte` solo recibe
   `SELECT` sobre la vista.
2. **Seudonimización reversible con UUID.** Cada cliente recibe un token
   aleatorio generado con `gen_random_uuid()`. La relación
   `token → cliente_id` vive en `pii.mapa_cliente`.
3. **Separación de funciones.** `analista` puede leer
   `analitica.clientes`, pero no tiene `USAGE` sobre el esquema `pii` ni
   privilegios sobre `public.clientes`. Sin el mapa, el token no permite
   recuperar la identidad por sí solo.
4. **Anonimización por generalización y agregación.** Se agrupa por rangos de
   edad y prefijo de código postal, y se aplica `HAVING COUNT(*) >= 5` como
   umbral didáctico de k-anonimato.
5. **Retención sin borrado.** La actividad 5 solo identifica registros
   vencidos. La demostración inserta datos sintéticos dentro de una
   transacción y hace `ROLLBACK`, de modo que la tabla principal nunca pierde
   información.
6. **Mínimo privilegio.** Ningún rol recibe más permisos que los necesarios
   para su función; los privilegios se verifican con
   `has_schema_privilege()` y `has_table_privilege()`.

## 6. Evidencias

| Archivo | Actividad | Qué demuestra |
| --- | --- | --- |
| `evidencias/01-clasificacion.pdf` | Clasificación | Matriz de campos, unicidad y combinaciones de cuasi-identificadores |
| `evidencias/02-enmascaramiento.pdf` | Enmascaramiento | Vista con datos parcialmente ocultos y denegación sobre `clientes` |
| `evidencias/03-seudonimizacion.pdf` | Seudonimización | Tokens, mapa de correspondencia, conjunto analítico y separación de funciones |
| `evidencias/04-anonimizacion.pdf` | Anonimización | Generalización, agregación, supresión k=5 y análisis del reto |
| `evidencias/05-retencion.pdf` | Retención | Consulta de registros vencidos y demostración transaccional con `ROLLBACK` |

Cada PDF incluye alumno, actividad, fecha/contexto de ejecución, consulta
ejecutada y resultados. El nombre y la fecha aparecen en el encabezado; no se
usa pie de página ni numeración.

## 7. Resultados clave

- Los cinco clientes tienen correo, teléfono, RFC y nombre únicos; la
  combinación `ciudad + código_postal + edad` produce cinco combinaciones
  distintas para cinco registros, por lo que el riesgo de reidentificación
  individual es alto si se publican sin transformación.
- El rol `soporte` puede leer la vista enmascarada y recibe
  `permission denied` al consultar `clientes`.
- El rol `analista` puede leer `analitica.clientes`, pero recibe
  `permission denied` sobre `pii.mapa_cliente` y `public.clientes`.
- Con el umbral k = 5 y solo cinco registros, la consulta de dirección no
  publica ningún grupo; el análisis de este resultado y la tensión
  privacidad/utilidad se documentan en `informe.md`.
- La consulta de retención devuelve cero registros reales porque todos tienen
  fecha de alta reciente; la demostración con datos sintéticos detecta
  correctamente dos registros vencidos y luego revierte los cambios.

## 8. Limitaciones

- El conjunto de datos es muy pequeño (cinco registros). Un umbral k = 5 no
  permite publicar ningún grupo y no representa una evaluación de privacidad
  de producción.
- k-anonimato no garantiza anonimización: no protege contra ataques de
  homogeneidad, conocimiento de fondo ni combinación con fuentes externas.
- El enmascaramiento de la vista oculta parcialmente, pero no impide que
  alguien con acceso a la tabla base vea los datos completos.
- La seudonimización es reversible por diseño: la protección depende de que
  `pii.mapa_cliente` permanezca separado y con acceso estrictamente
  controlado.
- La política de retención de cinco años es un supuesto didáctico; en un caso
  real debe justificarse con obligaciones legales, contractuales y
  operativas.

## 9. Commits sugeridos

```text
feat: agrega preparación y clasificación de datos
feat: implementa vista de enmascaramiento para soporte
feat: implementa seudonimización y separación de funciones
feat: agrega análisis de anonimización y reidentificación
feat: agrega consulta y procedimiento de retención
docs: agrega informe, evidencias y conclusiones
```

## 10. Checklist de entrega

- [x] Matriz de clasificación completa.
- [x] Scripts SQL incluidos y ejecutables.
- [x] Enmascaramiento funcionando.
- [x] `soporte` sin acceso directo a `clientes`.
- [x] Seudonimización funcionando.
- [x] `analista` sin acceso a `pii.mapa_cliente` ni a `public.clientes`.
- [x] Análisis de anonimización y reidentificación documentado.
- [x] Cuasi-identificadores identificados.
- [x] Consulta de retención incluida.
- [x] Evidencias verificadas en DBeaver.
- [x] Informe con conclusiones y respuestas de reflexión.
