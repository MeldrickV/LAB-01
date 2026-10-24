-- =====================================================================
-- LABORATORIO 01: Protección y Privacidad de Datos
-- Actividad 3: Seudonimización (pseudonymization)
--
-- Objetivo: construir un conjunto de datos para analítica donde la
-- identidad directa fue sustituida por un token, manteniendo el mapa de
-- correspondencia en un esquema separado y con acceso restringido.
-- =====================================================================

\set ON_ERROR_STOP on

CREATE SCHEMA pii;
CREATE SCHEMA analitica;

-- Tabla de correspondencia: token -> cliente_id.
-- Es el objeto más sensible de esta actividad, porque permite revertir la
-- seudonimización.
CREATE TABLE pii.mapa_cliente (
    token      UUID PRIMARY KEY,
    cliente_id BIGINT UNIQUE REFERENCES public.clientes(id)
);

COMMENT ON TABLE pii.mapa_cliente IS
    'Mapa de correspondencia token-cliente. Acceso exclusivo para funciones autorizadas de administración/seguridad.';

CREATE EXTENSION IF NOT EXISTS pgcrypto;

INSERT INTO pii.mapa_cliente (token, cliente_id)
SELECT gen_random_uuid(), id
FROM public.clientes;

\echo '=== Mapa de correspondencia (seudonimización reversible) ==='
SELECT * FROM pii.mapa_cliente ORDER BY cliente_id;

-- Conjunto de datos analítico: sin nombre, correo, teléfono ni RFC.
CREATE TABLE analitica.clientes AS
SELECT
    m.token AS cliente_token,
    c.edad,
    c.ciudad,
    c.codigo_postal,
    c.fecha_alta
FROM pii.mapa_cliente m
JOIN public.clientes c
  ON c.id = m.cliente_id;

COMMENT ON TABLE analitica.clientes IS
    'Conjunto seudonimizado para analítica. No contiene identificadores directos.';

\echo '=== Conjunto de datos seudonimizado para analítica ==='
SELECT * FROM analitica.clientes ORDER BY cliente_token;

\echo '=== Columnas expuestas en analitica.clientes ==='
SELECT ordinal_position AS posicion,
       column_name      AS columna,
       data_type        AS tipo
FROM information_schema.columns
WHERE table_schema = 'analitica'
  AND table_name = 'clientes'
ORDER BY ordinal_position;

\echo '=== Verificación: no existen columnas de identificación directa ==='
SELECT COUNT(*) AS columnas_sensibles_expuestas
FROM information_schema.columns
WHERE table_schema = 'analitica'
  AND table_name = 'clientes'
  AND column_name IN ('nombre', 'correo', 'telefono', 'rfc', 'id', 'cliente_id');

-- =====================================================================
-- Separación de funciones: el analista solo puede consultar el conjunto
-- seudonimizado, nunca el mapa de correspondencia ni la tabla original.
-- =====================================================================

CREATE ROLE analista NOLOGIN;

GRANT USAGE ON SCHEMA analitica TO analista;
GRANT SELECT ON analitica.clientes TO analista;
-- El mapa y la tabla original no se otorgan al analista.
REVOKE ALL ON pii.mapa_cliente FROM analista;
REVOKE ALL ON public.clientes FROM analista;

\echo '=== Verificación de privilegios del rol analista ==='
SELECT has_schema_privilege('analista', 'analitica', 'USAGE')          AS puede_usar_analitica,
       has_table_privilege('analista', 'analitica.clientes', 'SELECT') AS puede_leer_analitica,
       has_schema_privilege('analista', 'pii', 'USAGE')                AS puede_usar_pii,
       has_table_privilege('analista', 'pii.mapa_cliente', 'SELECT')   AS puede_leer_mapa,
       has_table_privilege('analista', 'public.clientes', 'SELECT')    AS puede_leer_clientes;

\echo '=== Consulta PERMITIDA: conjunto seudonimizado ==='
SET ROLE analista;
SELECT * FROM analitica.clientes ORDER BY cliente_token;
RESET ROLE;

-- Errores intencionales para evidenciar la separación de funciones.
\set ON_ERROR_STOP off

\echo '=== Consulta DENEGADA: mapa de correspondencia ==='
SET ROLE analista;
SELECT * FROM pii.mapa_cliente;
RESET ROLE;

\echo '=== Consulta DENEGADA: tabla original de clientes ==='
SET ROLE analista;
SELECT * FROM public.clientes;
RESET ROLE;

\set ON_ERROR_STOP on

\echo '=== Fin de la actividad 3 ==='
