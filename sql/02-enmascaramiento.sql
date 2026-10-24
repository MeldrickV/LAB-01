-- =====================================================================
-- LABORATORIO 01: Protección y Privacidad de Datos
-- Actividad 2: Enmascaramiento (masking) para el área de soporte
--
-- Objetivo: permitir que soporte identifique al cliente sin exponer los
-- valores completos de correo, teléfono y RFC, y sin darle acceso directo
-- a la tabla original.
-- =====================================================================

\set ON_ERROR_STOP on

CREATE ROLE soporte NOLOGIN;

-- La vista enmascara los datos en el momento de la consulta (enmascaramiento
-- dinámico): el dato original permanece intacto en public.clientes.
CREATE VIEW v_clientes_soporte AS
SELECT
    id,
    nombre,
    CONCAT(LEFT(correo, 2), '*****', SUBSTRING(correo FROM POSITION('@' IN correo))) AS correo,
    CONCAT('******', RIGHT(telefono, 4)) AS telefono,
    CONCAT('*********', RIGHT(rfc, 4)) AS rfc
FROM clientes;

COMMENT ON VIEW v_clientes_soporte IS
    'Vista de enmascaramiento para soporte: oculta parcialmente correo, teléfono y RFC.';

GRANT USAGE ON SCHEMA public TO soporte;
GRANT SELECT ON v_clientes_soporte TO soporte;
REVOKE ALL ON clientes FROM soporte;

\echo '=== Privilegios efectivos del rol soporte ==='
SELECT grantee,
       table_schema,
       table_name,
       privilege_type
FROM information_schema.role_table_grants
WHERE grantee = 'soporte'
ORDER BY table_name, privilege_type;

SELECT has_schema_privilege('soporte', 'public', 'USAGE')          AS puede_usar_esquema_public,
       has_table_privilege('soporte', 'public.clientes', 'SELECT')  AS puede_leer_tabla_clientes,
       has_table_privilege('soporte', 'public.v_clientes_soporte', 'SELECT') AS puede_leer_vista;

\echo '=== Consulta PERMITIDA: vista enmascarada ==='
SET ROLE soporte;
SELECT * FROM v_clientes_soporte ORDER BY id;
RESET ROLE;

-- A partir de aquí se provoca un error de forma intencional para demostrar
-- que el control de acceso funciona. El error es la evidencia esperada.
\set ON_ERROR_STOP off
\echo '=== Consulta DENEGADA: tabla original clientes ==='
SET ROLE soporte;
SELECT * FROM clientes;
RESET ROLE;
\set ON_ERROR_STOP on

\echo '=== Fin de la actividad 2 ==='
