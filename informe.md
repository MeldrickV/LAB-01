# Informe — Laboratorio 01: Protección y privacidad de datos

**Materia:** Gestión de Seguridad y Desempeño de Bases de Datos  
**Unidad:** II — Seguridad, privacidad y control de acceso  
**Tema:** 2.3 — Datos sensibles, privacidad y protección de la información  
**Alumno:** José Meldrick Rafael Vega Vega  
**Motor:** PostgreSQL 16.15  
**Fecha de ejecución:** 2026-10-23  
**Repositorio:** `LAB-01/`

---

## 1. Resumen ejecutivo

Se trabajó con la tabla `clientes` de la empresa ficticia Comercializadora Norte
S.A. de C.V. y se implementaron cinco capas de protección:

1. **Clasificación** de los atributos según su capacidad de identificar o
   contribuir a identificar a una persona.
2. **Enmascaramiento dinámico** para el área de soporte mediante una vista,
   retirando el acceso directo a la tabla base.
3. **Seudonimización** para analítica con tokens UUID y una tabla de
   correspondencia aislada en el esquema `pii`.
4. **Anonimización por agregación** para dirección, con generalización de edad
   y región y supresión de grupos menores a cinco registros.
5. **Retención** de datos mediante una consulta que identifica registros que
   exceden una política de cinco años, sin ejecutar borrados.

La conclusión principal es que **ningún mecanismo sustituye a los demás**:
el enmascaramiento no equivale a anonimización, la seudonimización sigue
siendo reversible si existe el mapa, y la agregación no elimina por sí sola el
riesgo de reidentificación. La protección efectiva resulta de combinar
transformación de datos con control de acceso y mínimo privilegio.

---

## 2. Escenario y metodología

La organización requiere que cuatro áreas utilicen los datos de clientes con
finalidades distintas:

- **Soporte:** identificar al cliente para atender solicitudes, sin ver todos
  sus datos.
- **Analítica:** estudiar tendencias sin conocer la identidad directa.
- **Dirección:** recibir estadísticas agregadas.
- **Administración de la base de datos:** administrar estructuras y accesos.

La metodología fue:

1. Crear el escenario con datos ficticios (`sql/00-preparacion.sql`).
2. Clasificar los campos (`sql/01-clasificacion.sql`).
3. Implementar cada control en un script independiente.
4. Verificar los permisos con `SET ROLE`, `has_schema_privilege()` y
   `has_table_privilege()`.
5. Provocar **errores intencionales** para demostrar que los accesos fueron
   rechazados.
6. Verificar los resultados en DBeaver.

Todos los scripts se ejecutaron sobre PostgreSQL 16.15 y los resultados se
verificaron en DBeaver 26.2.3.

---

## 3. Actividad 1 — Clasificación de los datos

### 3.1 Matriz de clasificación

| Campo | ¿Identifica directamente? | ¿Puede contribuir a identificar? | ¿Requiere protección? | Justificación |
| --- | --- | --- | --- | --- |
| `id` | No | Sí | Sí | Identificador interno único. No revela el nombre por sí solo, pero permite enlazar el registro con el mapa de correspondencia u otras fuentes. |
| `nombre` | Sí | No | Sí | Identificador directo: revela la identidad de la persona de inmediato. |
| `correo` | Sí | No | Sí | Identificador directo y único; contiene datos del nombre y permite contactar o correlacionar a la persona. |
| `telefono` | Sí | Sí | Sí | Identificador directo de contacto; puede ser único y permitir localización o suplantación. |
| `rfc` | Sí | Sí | Sí | Identificador oficial único de carácter fiscal; permite asociar información con la persona ante terceros. |
| `edad` | No | Sí | Sí | Cuasi-identificador: combinada con ciudad o código postal puede aislar a un individuo. |
| `ciudad` | No | Sí | Sí | Cuasi-identificador geográfico: reduce el conjunto de candidatos. |
| `codigo_postal` | No | Sí | Sí | Cuasi-identificador de alta granularidad; junto con edad y ciudad puede individualizar. |
| `fecha_alta` | No | Sí | Sí | Cuasi-identificador temporal; combinado con otros datos ayuda a distinguir registros. |

La tabla quedó materializada en `public.clasificacion_datos` para que la
clasificación sea auditable y reproducible.

### 3.2 Resultados de la verificación

- Hay **5 registros** y **5 valores únicos** de correo, teléfono, RFC y nombre.
- Cada combinación de `ciudad + codigo_postal + edad` aparece **una sola vez**:
  hay 5 registros y 5 combinaciones únicas.
- Por lo tanto, publicar esos tres atributos sin transformación permitiría
  distinguir a cada cliente dentro de este conjunto.

### 3.3 Respuestas

**1. ¿Qué campos identifican directamente a una persona?**

`nombre`, `correo`, `telefono` y `rfc`. El `id` es un identificador
pseudónimo: por sí solo no dice quién es la persona, pero la identifica de
forma indirecta si se combina con el mapa de correspondencia o con otra tabla.

**2. ¿Qué campos no identifican por sí mismos pero podrían contribuir a hacerlo?**

`id`, `edad`, `ciudad`, `codigo_postal` y `fecha_alta`. Son
cuasi-identificadores: aislados parecen inocuos, pero al combinarse reducen el
anonimato.

**3. ¿Qué combinación de campos podría incrementar el riesgo de reidentificación?**

`edad + ciudad + codigo_postal` es la combinación más clara en este conjunto:
las cinco personas tienen combinaciones distintas. Si se agrega `fecha_alta`,
el riesgo aumenta porque el tiempo también acota los candidatos. En el caso de
analítica, `cliente_token + edad + ciudad + codigo_postal + fecha_alta` podría
reidentificarse si el atacante obtiene el mapa o cruza los datos con fuentes
externas.

**4. ¿Todos los datos que deben protegerse son necesariamente datos personales
sensibles desde el punto de vista jurídico?**

No. Una cosa es que un dato **requiera protección** por su riesgo y otra que
sea **sensible** en el sentido jurídico estricto. En términos generales, los
datos sensibles incluyen categorías como origen étnico, salud, información
genética, datos biométricos, creencias religiosas, opiniones políticas o
preferencia sexual. El nombre, el correo o el teléfono son datos personales que
deben protegerse, pero no necesariamente “sensibles” con ese alcance legal. El
RFC y los datos financieros pueden tener protección reforzada según la
legislación aplicable. La clasificación debe basarse en el contexto, la
finalidad y el riesgo, no solo en una etiqueta.

**Evidencia:** `evidencias/01-clasificacion.pdf`.

---

## 4. Actividad 2 — Enmascaramiento (masking)

### 4.1 Implementación

Se creó el rol `soporte` como `NOLOGIN` y la vista `v_clientes_soporte`:

```sql
CREATE VIEW v_clientes_soporte AS
SELECT
    id,
    nombre,
    CONCAT(LEFT(correo, 2), '*****',
           SUBSTRING(correo FROM POSITION('@' IN correo))) AS correo,
    CONCAT('******', RIGHT(telefono, 4)) AS telefono,
    CONCAT('*********', RIGHT(rfc, 4)) AS rfc
FROM clientes;
```

Después se otorgó únicamente:

```sql
GRANT USAGE ON SCHEMA public TO soporte;
GRANT SELECT ON v_clientes_soporte TO soporte;
REVOKE ALL ON clientes FROM soporte;
```

### 4.2 Resultado

El rol `soporte` puede consultar la vista y ve, por ejemplo:

| id | nombre | correo | telefono | rfc |
| --- | --- | --- | --- | --- |
| 1 | Ana López | `an*****@example.test` | `******4567` | `*********5ABC` |
| 2 | Carlos Pérez | `ca*****@example.test` | `******5678` | `*********0DEF` |

Al intentar `SELECT * FROM clientes`, PostgreSQL responde:

```text
ERROR: permission denied for table clientes
```

La verificación de privilegios confirma:

```text
puede_usar_esquema_public = t
puede_leer_tabla_clientes  = f
puede_leer_vista           = t
```

### 4.3 Explicación solicitada (19.2)

- **Qué se ocultó:** el valor completo de `correo`, `telefono` y `rfc`. Del
  correo se conservan los dos primeros caracteres y el dominio; del teléfono y
  del RFC solo los últimos cuatro caracteres.
- **Para quién:** para el área de soporte, representada por el rol `soporte`.
- **Por qué:** soporte necesita identificar al cliente para atender solicitudes,
  pero no necesita los datos completos de contacto ni el RFC. Aplicar mínimo
  privilegio reduce la exposición.
- **Qué mecanismo se utilizó:** una **vista** que aplica enmascaramiento
  dinámico en el momento de la consulta. El dato original no se modifica en la
  tabla base; simplemente no se presenta completo al rol.

### 4.4 Respuestas

**1. ¿Qué información continúa existiendo en la tabla original?**

Toda: nombre, correo, teléfono, RFC, edad, ciudad, código postal y fecha de
alta completos. La vista no borra ni transforma el almacenamiento; solo cambia
la representación que se muestra.

**2. ¿Qué información puede visualizar el usuario soporte?**

El `id`, el `nombre` completo y las versiones parciales de correo, teléfono y
RFC. Con ello puede identificar al cliente para atención, pero no obtiene los
datos completos.

**3. ¿Por qué no es suficiente ocultar los datos únicamente en la aplicación?**

Porque la aplicación puede ser evadida: un usuario con credenciales de base de
datos, una exportación, un reporte, una consola de administración o una
vulnerabilidad podrían consultar la tabla directamente. Ocultar solo en la
capa de presentación no es un control de seguridad; es una convención. La base
de datos debe aplicar el control aunque la aplicación falle.

**4. ¿Qué ocurriría si soporte tuviera acceso directo a `clientes`?**

Podría leer y exportar todos los datos personales completos, incluyendo correo,
teléfono y RFC, con independencia de la vista. El enmascaramiento quedaría
anulado y aumentaría el riesgo de divulgación, fraude o suplantación.

**Evidencia:** `evidencias/02-enmascaramiento.pdf`.

---

## 5. Actividad 3 — Seudonimización y separación de funciones

### 5.1 Implementación

Se crearon los esquemas `pii` y `analitica`, la tabla de correspondencia y el
conjunto analítico:

```sql
CREATE TABLE pii.mapa_cliente (
    token      UUID PRIMARY KEY,
    cliente_id BIGINT UNIQUE REFERENCES public.clientes(id)
);

CREATE EXTENSION IF NOT EXISTS pgcrypto;

INSERT INTO pii.mapa_cliente (token, cliente_id)
SELECT gen_random_uuid(), id FROM public.clientes;

CREATE TABLE analitica.clientes AS
SELECT m.token AS cliente_token,
       c.edad,
       c.ciudad,
       c.codigo_postal,
       c.fecha_alta
FROM pii.mapa_cliente m
JOIN public.clientes c ON c.id = m.cliente_id;
```

El conjunto `analitica.clientes` contiene **solo** `cliente_token`, `edad`,
`ciudad`, `codigo_postal` y `fecha_alta`. La verificación confirmó que no
existen columnas `nombre`, `correo`, `telefono`, `rfc`, `id` ni `cliente_id`.

### 5.2 Separación de funciones

Se creó el rol `analista` y se otorgó únicamente:

```sql
GRANT USAGE ON SCHEMA analitica TO analista;
GRANT SELECT ON analitica.clientes TO analista;
```

No se otorgó acceso a `pii.mapa_cliente` ni a `public.clientes`. La
verificación arrojó:

```text
puede_usar_analitica = t
puede_leer_analitica = t
puede_usar_pii       = f
puede_leer_mapa      = f
puede_leer_clientes  = f
```

El acceso permitido y los dos accesos denegados quedaron registrados en las
evidencias 2, 3 y 4 del PDF de la actividad 3, con sus mensajes de error:

```text
ERROR: permission denied for schema pii
ERROR: permission denied for table clientes
```

### 5.3 Explicación solicitada (19.3)

- **Cómo se generaron los tokens:** con `gen_random_uuid()` de `pgcrypto`, un
  UUID aleatorio por cada cliente.
- **Dónde se encuentra el mapa de correspondencia:** en
  `pii.mapa_cliente`, dentro de un esquema separado del conjunto analítico.
- **Quién debería poder acceder a él:** únicamente un rol administrativo o de
  seguridad con autorización explícita y necesidad de servicio, sujeto a
  auditoría. No debe tener acceso el analista, ni soporte, ni roles de solo
  consulta.
- **Por qué se separaron los permisos:** para aplicar separación de funciones
  y mínimo privilegio. Si el analista pudiera leer el mapa, la seudonimización
  sería reversible de inmediato y el token dejaría de proteger la identidad.

### 5.4 Respuestas

**1. ¿Qué ocurriría si `analista` pudiera consultar también `pii.mapa_cliente`?**

Podría reconstruir la relación `token → cliente_id → nombre/correo/RFC` y
reidentificar a todas las personas del conjunto. La seudonimización perdería su
efecto práctico.

**2. ¿Qué principio de seguridad se está aplicando al separar ambos accesos?**

Separación de funciones (*separation of duties*) y mínimo privilegio
(*least privilege*). También es defensa en profundidad: aunque el analista
tenga acceso legítimo a los datos seudonimizados, no concentra la capacidad de
revertir la seudonimización.

**3. ¿Por qué la seudonimización no equivale a anonimización?**

Porque es **reversible** cuando existe información adicional protegida. El
token sustituye al identificador directo, pero el mapa permite recuperar la
identidad. La anonimización busca que la reidentificación no sea razonablemente
posible, incluso con medios adicionales razonables.

**4. ¿Qué información permite volver a relacionar el token con una persona?**

La tabla `pii.mapa_cliente` (token y `cliente_id`) junto con
`public.clientes` (donde `id` se asocia a nombre, correo, teléfono y RFC).
También podrían contribuir los cuasi-identificadores del conjunto analítico si
se cruzan con fuentes externas.

**Evidencia:** `evidencias/03-seudonimizacion.pdf`.

---

## 6. Actividades 5 y 6 — Anonimización y riesgo de reidentificación

### 6.1 Resultados

**Generalización de edad (12.1):**

| rango_edad | total |
| --- | --- |
| 31-45 | 4 |
| 46+ | 1 |

**Generalización de región (12.2):**

| region | total |
| --- | --- |
| 80 | 3 |
| 81 | 1 |
| 82 | 1 |

**Combinación de atributos (12.3):**

| rango_edad | region | total |
| --- | --- | --- |
| 31-45 | 80 | 3 |
| 31-45 | 81 | 1 |
| 46+ | 82 | 1 |

**Supresión con `HAVING COUNT(*) >= 5` (12.4):** devuelve **0 filas**, porque
ningún grupo alcanza cinco registros. Los tres grupos existentes (3, 1 y 1)
fueron suprimidos por el umbral.

Como análisis complementario se ejecutó el mismo agrupamiento con umbral k = 2:
solo sobrevive el grupo `31-45 / 80` con 3 registros. Esto permite observar qué
información se pierde cuando se aplica un umbral más estricto.

### 6.2 Reto: reducir aún más el riesgo

Se modificó la consulta para generalizar más:

- Edad en bandas de 18 años: `18-35`, `36-50`, `51+`.
- Región a partir del **primer dígito** del código postal.

Con `HAVING COUNT(*) >= 5` el resultado sigue siendo **0 filas**, porque los
grupos quedan en 2 y 3 registros. Para lograr un grupo que cumpla k = 5 fue
necesario generalizar la edad a una sola banda (`18+`) y la región a un dígito,
obteniendo:

| rango_edad | region | total |
| --- | --- | --- |
| 18+ | 8 | 5 |

**Cambio realizado:** mayor generalización de edad y región.  
**Motivo:** reducir la granularidad de los cuasi-identificadores.  
**Resultado:** con k = 5 no se publica ningún grupo con detalle; la única
variante que cumple el umbral publica un solo agregado global.  
**Riesgo que se pretende reducir:** reidentificación por combinación de edad y
zona geográfica.

La conclusión es que, con solo cinco registros, **no es posible conservar
utilidad analítica y cumplir k = 5 al mismo tiempo**. Aumentar la
generalización reduce el riesgo, pero también destruye la información; en un
caso real se necesitaría más volumen de datos y técnicas complementarias.

### 6.3 Respuestas (Actividad 6)

**1. ¿Qué identificadores directos fueron eliminados?**

`nombre`, `correo`, `telefono` y `rfc`. El `id` original también se sustituyó
por `cliente_token`. El token no es un identificador directo, pero sigue siendo
un seudónimo.

**2. ¿Qué cuasi-identificadores permanecen?**

En la salida agregada permanecen `rango_edad` y `region`. En el conjunto
analítico subyacente también están `edad`, `ciudad`, `codigo_postal` y
`fecha_alta`.

**3. ¿Qué combinaciones de atributos podrían reducir el anonimato?**

`rango_edad + region`, sobre todo si los grupos son pequeños; también
`ciudad + codigo_postal + fecha_alta` en el conjunto analítico. La combinación
con fuentes externas (padrón, redes sociales, registros públicos) aumenta el
riesgo.

**4. ¿Qué sucede cuando un grupo contiene pocos registros?**

El grupo es más fácil de atribuir a una persona concreta. Por eso se suprimen
los grupos pequeños. En este ejercicio todos los grupos tienen menos de cinco
registros y, por tanto, ninguno se publica con k = 5.

**5. ¿Qué atributos deberían generalizarse?**

`edad` a rangos amplios, `codigo_postal` a región, `ciudad` a estado o región y
`fecha_alta` a año, trimestre o mes. En un caso real también se evaluaría
suprimir atributos que no sean necesarios para la finalidad.

**6. ¿Qué información debería suprimirse?**

Los identificadores directos, el token cuando no sea necesario, los grupos
pequeños y cualquier atributo de alta granularidad que no aporte a la
finalidad. También debe evitarse publicar combinaciones que permitan aislar
registros.

**7. ¿Es correcto afirmar que el conjunto de datos es “100 % anónimo”? ¿Por qué?**

No. k-anonimato es una condición necesaria en ciertos escenarios, pero no una
garantía. No protege contra ataques de homogeneidad, conocimiento de fondo,
correlación temporal ni cruce con otras fuentes. Además, el tamaño de la
muestra es mínimo. La afirmación correcta es que se **redujo** el riesgo, no
que se eliminó.

**Evidencia:** `evidencias/04-anonimizacion.pdf`.

---

## 7. Actividad 7 — Retención de datos

### 7.1 Criterio y resultados

Se estableció una política didáctica de **cinco años** desde `fecha_alta`:

```sql
SELECT *
FROM clientes
WHERE fecha_alta < CURRENT_DATE - INTERVAL '5 years';
```

La fecha de corte calculada fue `2021-10-23`. Con los datos reales del
ejercicio, todos los registros tienen `fecha_alta = 2026-10-23`, por lo que la
consulta devuelve **0 registros**.

Para comprobar que el criterio funciona, se insertaron dos registros sintéticos
con fechas de 7 y 6 años dentro de una transacción:

| id | nombre | fecha_alta | antigüedad |
| --- | --- | --- | --- |
| 6 | Cliente Legado Uno | 2019-10-23 | 7 years |
| 7 | Cliente Legado Dos | 2020-10-23 | 6 years |

Después se ejecutó `ROLLBACK`; el conteo final volvió a **5 registros**. La
tabla principal nunca se modificó de forma permanente.

### 7.2 Documentación del procedimiento (19.5)

- **Criterio utilizado:** conservar los datos de clientes durante cinco años
  desde `fecha_alta`. Es un supuesto del ejercicio; en producción debe
  justificarse con la finalidad, obligaciones legales, contractuales,
  regulatorias y necesidades de auditoría.
- **Qué registros serían afectados:** los que tengan `fecha_alta` anterior a
  `CURRENT_DATE - INTERVAL '5 years'`. Actualmente: ninguno real; en la
  demostración: dos registros sintéticos.
- **Qué información debería conservarse:** la estrictamente necesaria para la
  finalidad vigente, obligaciones legales o auditoría. Puede conservarse un
  agregado o un registro mínimo de la operación sin datos personales
  innecesarios.
- **Qué información podría eliminarse:** los datos personales de clientes sin
  relación operativa ni obligación de conservación, incluidos identificadores
  directos y datos de contacto.
- **Qué controles deberían existir antes de eliminar:**
  - Aprobación del responsable de datos/área de negocio, con revisión de
    cumplimiento normativo.
  - Separación de funciones: quien solicita, quien aprueba y quien ejecuta no
    deben ser la misma persona.
  - Respaldo verificado y política de conservación del respaldo.
  - Registro de auditoría de la ejecución (fecha, alcance, responsable,
    identificadores afectados).
  - Periodo de cuarentena o borrado lógico cuando sea viable.
  - Procedimiento documentado de restauración y prueba de recuperación.
- **Qué evidencia debería conservarse:** la consulta de selección, el conteo
  de registros, la aprobación, el identificador del respaldo, el registro de
  ejecución y el resultado de la verificación posterior.
- **Qué procedimiento permitiría recuperar información eliminada
  accidentalmente:** restaurar desde el respaldo verificado o aplicar
  recuperación a un punto en el tiempo (PITR) en una instancia aislada;
  validar la restauración y documentar el incidente. El borrado físico se
  trabajará en las prácticas de respaldo y recuperación.

**Evidencia:** `evidencias/05-retencion.pdf`.

---

## 8. Conclusiones (19.6)

**¿Qué técnica utilizarías para un área de soporte?**  
Enmascaramiento dinámico mediante una vista, complementado con mínimo
privilegio: el rol de soporte solo debe ver la vista y nunca la tabla base.

**¿Qué técnica utilizarías para un área de analítica?**  
Seudonimización con tokens y separación estricta del mapa de correspondencia.
El analista debe acceder solo al conjunto seudonimizado; el mapa debe quedar en
un esquema con controles más estrictos y auditoría.

**¿Qué técnica utilizarías para publicar estadísticas?**  
Generalización, agregación y supresión de grupos pequeños. En un entorno real
se complementaría con técnicas como l-diversity, t-closeness o privacidad
diferencial, y con una evaluación formal del riesgo de reidentificación.

**¿Por qué ninguna de estas técnicas sustituye al control de acceso?**  
Porque todas dependen de que los privilegios se apliquen correctamente. Una
vista sin control de acceso a la tabla base se puede evadir; un mapa de
seudonimización accesible al analista anula la seudonimización; un conjunto
agregado puede exponerse si cualquier rol puede consultar los datos originales.
La transformación reduce el riesgo, pero el control de acceso determina quién
puede llegar a cada objeto. La protección real es la combinación de ambas.

---

## 9. Preguntas de reflexión (20)

**1. ¿Cuál es la diferencia entre enmascaramiento y seudonimización?**

El enmascaramiento oculta total o parcialmente la visualización de un dato sin
necesidad de sustituir la identidad; el dato original sigue existiendo y puede
seguir siendo único. La seudonimización sustituye el identificador directo por
un token y mantiene una información adicional separada que permite revertir la
sustitución si hay autorización.

**2. ¿Por qué la seudonimización no significa anonimización?**

Porque es reversible. Mientras exista el mapa de correspondencia y sea
accesible, es posible recuperar la identidad. La anonimización busca que la
reidentificación no sea razonablemente posible, incluso con información
adicional.

**3. ¿Por qué eliminar nombre y RFC no garantiza que un conjunto de datos sea
anónimo?**

Porque quedan cuasi-identificadores como edad, ciudad, código postal, fecha de
alta o el propio token. Su combinación puede distinguir a una persona,
especialmente si se cruza con otras fuentes. Anonimizar no es “quitar una
columna llamada nombre”.

**4. ¿Qué función tienen los cuasi-identificadores?**

Reducir el conjunto de candidatos. Por sí solos no identifican directamente,
pero combinados entre sí o con fuentes externas permiten acotar y,
eventualmente, identificar a una persona.

**5. ¿Por qué es importante separar el mapa de seudonimización?**

Porque el mapa es la llave para revertir la seudonimización. Si el mismo rol
puede leer los datos seudonimizados y el mapa, la sustitución no protege nada.
La separación aplica el principio de mínimo privilegio y separación de
funciones.

**6. ¿Qué principio de seguridad se aplica al impedir que el analista acceda al
mapa?**

Mínimo privilegio y separación de funciones. El analista solo recibe los
permisos necesarios para su finalidad y no concentra la capacidad de
reidentificar.

**7. ¿Por qué una vista puede ser preferible a entregar acceso directo a la
tabla?**

Porque permite exponer solo las columnas y filas necesarias, aplicar
transformaciones y mantener la tabla base fuera del alcance del rol. Además,
concentra la lógica de exposición en un objeto controlado y facilita auditoría
y cambios.

**8. ¿Qué diferencia existe entre proteger un dato para visualización y
protegerlo contra acceso no autorizado?**

Proteger para visualización es controlar cómo se presenta el dato (por ejemplo,
enmascararlo). Protegerlo contra acceso no autorizado es impedir que se lea o
modifique, mediante privilegios, revocaciones, cifrado, auditoría y control de
sesiones. Lo primero no impide el acceso; lo segundo sí.

**9. ¿Por qué la retención forma parte de la protección de datos?**

Porque conservar información más tiempo del necesario aumenta la superficie de
exposición, el impacto de una brecha y el incumplimiento de obligaciones de
minimización y finalidad. Retener de forma justificada y eliminar de forma
segura reduce el riesgo.

**10. ¿Qué riesgo existe si una organización conserva información
indefinidamente?**

Aumenta la probabilidad e impacto de filtraciones, accesos indebidos,
reidentificación y sanciones; se dificulta el cumplimiento del derecho de
supresión; se acumulan datos obsoletos o inexactos; y crece el costo de
almacenamiento y de gestión de accesos.

---

## 10. Limitaciones y recomendaciones

- El conjunto de cinco registros es insuficiente para demostrar utilidad
  estadística con k = 5. El resultado vacío es correcto y evidencia la tensión
  entre privacidad y utilidad.
- k-anonimato no garantiza anonimización. En producción se debe evaluar el
  riesgo con un marco formal y considerar técnicas adicionales.
- El enmascaramiento de la vista es parcial; no sustituye el cifrado ni el
  control de acceso a la tabla base. La vista conserva el `nombre` completo
  porque el escenario de soporte lo necesita para identificar al cliente; si
  esa finalidad no lo exigiera, el nombre también debería enmascararse.
- La seudonimización es reversible por diseño. El mapa debe tener controles
  más estrictos, auditoría y, si es posible, cifrado o almacenamiento separado.
- La política de retención de cinco años es un supuesto didáctico. Debe
  validarse con el área legal y de cumplimiento.
- Para un entorno real se recomienda:
  - registrar y monitorear accesos a datos sensibles;
  - aplicar mínimo privilegio por rol y revisar permisos periódicamente;
  - cifrar datos en reposo y en tránsito;
  - documentar finalidades y bases legales;
  - probar restauraciones de respaldo;
  - definir procedimientos de eliminación segura y de atención de incidentes.

---

## 11. Evidencias y trazabilidad

| Evidencia | Script | Contenido |
| --- | --- | --- |
| `evidencias/01-clasificacion.pdf` | `sql/01-clasificacion.sql` | Matriz, unicidad y combinaciones |
| `evidencias/02-enmascaramiento.pdf` | `sql/02-enmascaramiento.sql` | Vista, privilegios y acceso denegado |
| `evidencias/03-seudonimizacion.pdf` | `sql/03-seudonimizacion.sql` | Tokens, mapa, conjunto analítico y dos accesos denegados |
| `evidencias/04-anonimizacion.pdf` | `sql/04-anonimizacion.sql` | Generalización, agregación, k=5 y reto |
| `evidencias/05-retencion.pdf` | `sql/05-retencion.sql` | Consulta de retención y demostración con `ROLLBACK` |

Cada PDF incluye alumno, actividad, fecha/contexto de ejecución, consulta
ejecutada y resultados. El nombre y la fecha aparecen en el encabezado; no se
usa pie de página ni numeración.

---

## 12. Conclusión final

El laboratorio demuestra que proteger datos personales no consiste en aplicar
una sola técnica, sino en combinar **clasificación, transformación y control de
acceso** de acuerdo con la finalidad de cada área. El enmascaramiento reduce la
exposición visual; la seudonimización permite analizar sin exponer la identidad
directa, siempre que el mapa permanezca separado; la anonimización por
agregación reduce el riesgo de reidentificación, pero no lo elimina; y la
retención limita la acumulación innecesaria de información. Ningún control es
suficiente por sí solo: la seguridad y la privacidad dependen de que todos se
apliquen de forma coherente y verificable.
