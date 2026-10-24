-- =====================================================================
-- LABORATORIO 01: Protección y Privacidad de Datos
-- Actividad 5: Retención de datos
--
-- Política del ejercicio: conservar los datos de clientes durante 5 años
-- contados a partir de fecha_alta. NO se debe ejecutar DELETE sobre la
-- tabla principal; esta actividad solo identifica y documenta los
-- registros afectados.
-- =====================================================================

\set ON_ERROR_STOP on

\echo '=== Fecha de corte de la política de retención (5 años) ==='
SELECT CURRENT_DATE - INTERVAL '5 years' AS fecha_corte;

\echo '=== Registros que superan el periodo de conservación ==='
SELECT id,
       nombre,
       fecha_alta,
       AGE(CURRENT_DATE, fecha_alta) AS antiguedad,
       fecha_alta + INTERVAL '5 years' AS fecha_limite_conservacion
FROM clientes
WHERE fecha_alta < CURRENT_DATE - INTERVAL '5 years'
ORDER BY fecha_alta;

\echo '=== Conteo de registros afectados ==='
SELECT COUNT(*) AS registros_que_exceden_retencion
FROM clientes
WHERE fecha_alta < CURRENT_DATE - INTERVAL '5 years';

-- ---------------------------------------------------------------------
-- Demostración controlada del criterio de retención.
-- Se insertan dos registros ficticios con fecha antigua dentro de una
-- transacción y se revierte al final. Así se comprueba que la consulta
-- detecta correctamente los registros vencidos sin alterar los datos.
-- ---------------------------------------------------------------------
BEGIN;

INSERT INTO clientes
    (nombre, correo, telefono, rfc, edad, ciudad, codigo_postal, fecha_alta)
VALUES
    ('Cliente Legado Uno', 'legado.uno@example.test', '6670000001', 'LEGU800101AAA', 45, 'Culiacán', '80000', CURRENT_DATE - INTERVAL '7 years'),
    ('Cliente Legado Dos', 'legado.dos@example.test', '6670000002', 'LEGU750202BBB', 50, 'Mazatlán', '82000', CURRENT_DATE - INTERVAL '6 years');

\echo '=== Demostración: registros vencidos detectados (datos sintéticos) ==='
SELECT id,
       nombre,
       fecha_alta,
       AGE(CURRENT_DATE, fecha_alta) AS antiguedad
FROM clientes
WHERE fecha_alta < CURRENT_DATE - INTERVAL '5 years'
ORDER BY fecha_alta;

\echo '=== Total de registros dentro de la demostración ==='
SELECT COUNT(*) AS total_con_datos_sinteticos FROM clientes;

ROLLBACK;

\echo '=== Total final: los datos de demostración fueron revertidos ==='
SELECT COUNT(*) AS total_real FROM clientes;

\echo '=== Consulta reutilizable para el procedimiento de retención ==='
SELECT id,
       correo,
       fecha_alta,
       CURRENT_DATE - fecha_alta AS antiguedad_dias,
       fecha_alta + INTERVAL '5 years' AS fecha_eliminacion_programada
FROM clientes
WHERE fecha_alta < CURRENT_DATE - INTERVAL '5 years'
ORDER BY fecha_alta;
