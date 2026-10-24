-- =====================================================================
-- LABORATORIO 01: Protección y Privacidad de Datos
-- Actividad 1: Clasificación de los datos
--
-- Objetivo: identificar identificadores directos, cuasi-identificadores
-- y atributos que requieren protección dentro de la tabla clientes.
-- =====================================================================

\set ON_ERROR_STOP on

CREATE TABLE clasificacion_datos (
    orden                  INTEGER PRIMARY KEY,
    campo                  VARCHAR(30) NOT NULL UNIQUE,
    identificador_directo  BOOLEAN NOT NULL,
    cuasi_identificador    BOOLEAN NOT NULL,
    requiere_proteccion    BOOLEAN NOT NULL,
    justificacion          TEXT NOT NULL
);

INSERT INTO clasificacion_datos
    (orden, campo, identificador_directo, cuasi_identificador, requiere_proteccion, justificacion)
VALUES
    (1, 'id', FALSE, TRUE, TRUE,
        'Identificador interno único. Por sí solo no revela el nombre, pero permite enlazar el registro con la tabla de correspondencia o con otras fuentes y, por tanto, reidentificar al titular.'),
    (2, 'nombre', TRUE, FALSE, TRUE,
        'Identificador directo: revela la identidad de la persona de forma inmediata.'),
    (3, 'correo', TRUE, FALSE, TRUE,
        'Identificador directo y único. Además de contener datos del nombre, permite contactar a la persona y correlacionarla con otras cuentas.'),
    (4, 'telefono', TRUE, TRUE, TRUE,
        'Identificador directo de contacto. Puede ser único y permite localizar o suplantar comunicaciones a la persona.'),
    (5, 'rfc', TRUE, TRUE, TRUE,
        'Identificador directo oficial de carácter fiscal. Es único y permite asociar información con la persona ante terceros.'),
    (6, 'edad', FALSE, TRUE, TRUE,
        'Cuasi-identificador: combinada con ciudad, código postal u otros atributos puede aislar a un individuo. También puede considerarse dato personal.'),
    (7, 'ciudad', FALSE, TRUE, TRUE,
        'Cuasi-identificador geográfico: por sí sola no identifica, pero reduce el conjunto de candidatos.'),
    (8, 'codigo_postal', FALSE, TRUE, TRUE,
        'Cuasi-identificador geográfico de alta granularidad: combinado con edad y ciudad puede individualizar a una persona.'),
    (9, 'fecha_alta', FALSE, TRUE, TRUE,
        'Cuasi-identificador temporal. Combinada con otros datos puede contribuir a distinguir o reidentificar a una persona.');

\echo '=== Matriz de clasificación de datos ==='
SELECT campo,
       identificador_directo AS identifica_directamente,
       cuasi_identificador   AS contribuye_a_identificar,
       requiere_proteccion   AS requiere_proteccion,
       justificacion
FROM clasificacion_datos
ORDER BY orden;

\echo '=== Verificación 1: ¿cuántos registros y cuántos valores únicos hay? ==='
SELECT COUNT(*) AS total_registros,
       COUNT(DISTINCT correo)        AS correos_unicos,
       COUNT(DISTINCT telefono)      AS telefonos_unicos,
       COUNT(DISTINCT rfc)           AS rfc_unicos,
       COUNT(DISTINCT nombre)        AS nombres_unicos
FROM clientes;

\echo '=== Verificación 2: combinación de cuasi-identificadores edad + ciudad + código postal ==='
SELECT ciudad,
       codigo_postal,
       edad,
       COUNT(*) AS repeticiones
FROM clientes
GROUP BY ciudad, codigo_postal, edad
ORDER BY ciudad, codigo_postal, edad;

\echo '=== Verificación 3: ¿cuántas combinaciones únicas produce el conjunto de cuasi-identificadores? ==='
SELECT COUNT(*) AS registros,
       COUNT(DISTINCT (ciudad, codigo_postal, edad)) AS combinaciones_unicas
FROM clientes;
