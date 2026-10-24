-- =====================================================================
-- LABORATORIO 01: Protección y Privacidad de Datos
-- Actividad 0: Preparación del escenario
-- Motor: PostgreSQL 16
--
-- Ejecutar conectado a la base de datos del laboratorio con un rol
-- administrador (por ejemplo, postgres o labadmin):
--     psql -d lab01 -f sql/00-preparacion.sql
-- =====================================================================

\set ON_ERROR_STOP on

-- Limpieza para que el script pueda ejecutarse varias veces sin errores.
DROP SCHEMA IF EXISTS analitica CASCADE;
DROP SCHEMA IF EXISTS pii CASCADE;
DROP VIEW IF EXISTS public.v_clientes_soporte;
DROP TABLE IF EXISTS public.clasificacion_datos;
DROP TABLE IF EXISTS public.clientes;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'soporte') THEN
        EXECUTE 'DROP OWNED BY soporte';
        EXECUTE 'DROP ROLE soporte';
    END IF;

    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'analista') THEN
        EXECUTE 'DROP OWNED BY analista';
        EXECUTE 'DROP ROLE analista';
    END IF;
END
$$;

CREATE TABLE clientes (
    id             BIGSERIAL PRIMARY KEY,
    nombre         VARCHAR(120) NOT NULL,
    correo         VARCHAR(150) NOT NULL,
    telefono       VARCHAR(20),
    rfc            VARCHAR(13),
    edad           INTEGER,
    ciudad         VARCHAR(80),
    codigo_postal  VARCHAR(10),
    fecha_alta     DATE DEFAULT CURRENT_DATE
);

INSERT INTO clientes
    (nombre, correo, telefono, rfc, edad, ciudad, codigo_postal)
VALUES
    ('Ana López',    'ana.lopez@example.test',    '6671234567', 'LOAA850315ABC', 41, 'Culiacán',  '80000'),
    ('Carlos Pérez', 'carlos.perez@example.test', '6672345678', 'PECA900720DEF', 35, 'Culiacán',  '80100'),
    ('María García', 'maria.garcia@example.test', '6673456789', 'GAMA780912GHI', 47, 'Mazatlán',  '82000'),
    ('Luis Torres',  'luis.torres@example.test',  '6674567890', 'TOLU920201JKL', 34, 'Los Mochis', '81200'),
    ('Laura Sánchez','laura.sanchez@example.test','6675678901', 'SALA880525MNO', 38, 'Culiacán',  '80200');

\echo '=== Estructura de la tabla clientes ==='
\d clientes

\echo '=== Datos de prueba cargados ==='
SELECT * FROM clientes ORDER BY id;
