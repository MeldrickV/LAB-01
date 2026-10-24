-- =====================================================================
-- LABORATORIO 01: Protección y Privacidad de Datos
-- Verificación final de los escenarios de la sección 15
--
-- Este script es complementario y no forma parte de los cinco entregables
-- obligatorios. Sirve para comprobar de forma consolidada que los
-- controles implementados funcionan.
-- =====================================================================

\pset pager off

\echo '=== 1. Resumen de privilegios por rol ==='
SELECT r.rolname AS rol,
       has_schema_privilege(r.rolname, 'public', 'USAGE')            AS usa_public,
       has_table_privilege(r.rolname, 'public.clientes', 'SELECT')   AS lee_clientes,
       has_table_privilege(r.rolname, 'public.v_clientes_soporte', 'SELECT') AS lee_vista,
       has_schema_privilege(r.rolname, 'analitica', 'USAGE')         AS usa_analitica,
       has_table_privilege(r.rolname, 'analitica.clientes', 'SELECT') AS lee_analitica,
       has_schema_privilege(r.rolname, 'pii', 'USAGE')               AS usa_pii,
       has_table_privilege(r.rolname, 'pii.mapa_cliente', 'SELECT')  AS lee_mapa
FROM pg_roles r
WHERE r.rolname IN ('soporte', 'analista')
ORDER BY r.rolname;

\echo '=== 2. Soporte: consulta permitida a la vista ==='
SET ROLE soporte;
SELECT * FROM v_clientes_soporte ORDER BY id;
RESET ROLE;

\set ON_ERROR_STOP off

\echo '=== 3. Soporte: acceso denegado a clientes ==='
SET ROLE soporte;
SELECT * FROM clientes;
RESET ROLE;

\echo '=== 4. Analista: consulta permitida al conjunto seudonimizado ==='
SET ROLE analista;
SELECT * FROM analitica.clientes ORDER BY cliente_token;
RESET ROLE;

\echo '=== 5. Analista: acceso denegado al mapa de correspondencia ==='
SET ROLE analista;
SELECT * FROM pii.mapa_cliente;
RESET ROLE;

\echo '=== 6. Analista: acceso denegado a clientes ==='
SET ROLE analista;
SELECT * FROM public.clientes;
RESET ROLE;

\set ON_ERROR_STOP on

\echo '=== 7. Información agregada para dirección (k = 5) ==='
SELECT CASE
           WHEN edad BETWEEN 18 AND 30 THEN '18-30'
           WHEN edad BETWEEN 31 AND 45 THEN '31-45'
           ELSE '46+'
       END AS rango_edad,
       LEFT(codigo_postal, 2) AS region,
       COUNT(*) AS total
FROM clientes
GROUP BY 1, 2
HAVING COUNT(*) >= 5
ORDER BY 1, 2;

\echo '=== 8. Retención: registros que exceden cinco años ==='
SELECT id, nombre, fecha_alta
FROM clientes
WHERE fecha_alta < CURRENT_DATE - INTERVAL '5 years'
ORDER BY fecha_alta;

\echo '=== 9. Inventario final de objetos ==='
SELECT table_schema, table_name, table_type
FROM information_schema.tables
WHERE table_schema IN ('public', 'pii', 'analitica')
ORDER BY table_schema, table_name;
