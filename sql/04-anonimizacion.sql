-- =====================================================================
-- LABORATORIO 01: Protección y Privacidad de Datos
-- Actividad 4: Anonimización y análisis de reidentificación
--
-- Objetivo: generar información agregada para dirección, aplicando
-- generalización, agrupación por rangos y supresión de grupos pequeños.
-- =====================================================================

\set ON_ERROR_STOP on

\echo '=== 12.1 Generalización de la edad ==='
SELECT CASE
           WHEN edad BETWEEN 18 AND 30 THEN '18-30'
           WHEN edad BETWEEN 31 AND 45 THEN '31-45'
           ELSE '46+'
       END AS rango_edad,
       COUNT(*) AS total
FROM clientes
GROUP BY 1
ORDER BY 1;

\echo '=== 12.2 Generalización de la región a partir del código postal ==='
SELECT LEFT(codigo_postal, 2) AS region,
       COUNT(*) AS total
FROM clientes
GROUP BY 1
ORDER BY 1;

\echo '=== 12.3 Combinación de cuasi-identificadores generalizados ==='
SELECT CASE
           WHEN edad BETWEEN 18 AND 30 THEN '18-30'
           WHEN edad BETWEEN 31 AND 45 THEN '31-45'
           ELSE '46+'
       END AS rango_edad,
       LEFT(codigo_postal, 2) AS region,
       COUNT(*) AS total
FROM clientes
GROUP BY 1, 2
ORDER BY 1, 2;

\echo '=== 12.4 Supresión de grupos pequeños con umbral k = 5 ==='
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

\echo '=== Análisis complementario: mismo agrupamiento con umbral k = 2 ==='
-- Se incluye únicamente para visualizar los grupos que el umbral k = 5
-- suprime. No debe interpretarse como una publicación segura.
SELECT CASE
           WHEN edad BETWEEN 18 AND 30 THEN '18-30'
           WHEN edad BETWEEN 31 AND 45 THEN '31-45'
           ELSE '46+'
       END AS rango_edad,
       LEFT(codigo_postal, 2) AS region,
       COUNT(*) AS total
FROM clientes
GROUP BY 1, 2
HAVING COUNT(*) >= 2
ORDER BY 1, 2;

\echo '=== Reto: generalización más agresiva (bandas de 18 años y región de 1 dígito) ==='
SELECT CASE
           WHEN edad BETWEEN 18 AND 35 THEN '18-35'
           WHEN edad BETWEEN 36 AND 50 THEN '36-50'
           ELSE '51+'
       END AS rango_edad,
       LEFT(codigo_postal, 1) AS region,
       COUNT(*) AS total
FROM clientes
GROUP BY 1, 2
HAVING COUNT(*) >= 5
ORDER BY 1, 2;

\echo '=== Reto (variante): publicar solo el agregado que alcanza k = 5 ==='
-- Al generalizar la edad a una sola banda y la región a 1 dígito se logra
-- un grupo de 5, pero se pierde casi toda la utilidad analítica.
SELECT '18+' AS rango_edad,
       LEFT(codigo_postal, 1) AS region,
       COUNT(*) AS total
FROM clientes
GROUP BY 1, 2
HAVING COUNT(*) >= 5;
