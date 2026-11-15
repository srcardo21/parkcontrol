-- DROP DATABASE IF EXISTS parkcontrol_db;

CREATE DATABASE IF NOT EXISTS parkcontrol_db
    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE parkcontrol_db;

-- ============================================================
-- 1. TABLAS
-- ============================================================

-- OPERADOR: personas que inician sesion (login con usuario y clave, segun rol)
CREATE TABLE IF NOT EXISTS OPERADOR (
    id_operador    INT AUTO_INCREMENT,
    nombre         VARCHAR(100) NOT NULL,
    telefono       VARCHAR(20)  NOT NULL,
    usuario        VARCHAR(50)  NOT NULL,
    clave_hash     VARCHAR(255) NOT NULL,
    rol            ENUM('Administrador','Operador') NOT NULL DEFAULT 'Operador',
    estado         ENUM('Activo','Inactivo') NOT NULL DEFAULT 'Activo',
    inactivo_hasta DATE NULL,                                    -- inactivacion por 12 meses (reactivable en ese plazo)
    PRIMARY KEY (id_operador),
    CONSTRAINT UQ_Operador_Usuario UNIQUE (usuario)
) ENGINE=InnoDB;

-- VEHICULO: cliente mensual identificado por su placa
CREATE TABLE IF NOT EXISTS VEHICULO (
    id_vehiculo    INT AUTO_INCREMENT,
    placa          VARCHAR(10) NOT NULL,
    tipo           ENUM('Carro','Moto') NOT NULL,
    marca          VARCHAR(50) NOT NULL,
    modelo         VARCHAR(50) NOT NULL,
    color          VARCHAR(30) NOT NULL,
    estado         ENUM('Activo','Inactivo') NOT NULL DEFAULT 'Activo',
    inactivo_hasta DATE NULL,
    PRIMARY KEY (id_vehiculo),
    CONSTRAINT UQ_Vehiculo_Placa UNIQUE (placa)
) ENGINE=InnoDB;

-- CELDA: espacios fisicos (70 de carros y 10 de motos)
CREATE TABLE IF NOT EXISTS CELDA (
    id_celda INT AUTO_INCREMENT,
    codigo   VARCHAR(10) NOT NULL,                               -- nomenclatura: C-01..C-70, M-01..M-10
    tipo     ENUM('Carro','Moto') NOT NULL,                      -- tipo de vehiculo asignado
    estado   ENUM('Disponible','Ocupada','Reservada','Mantenimiento') NOT NULL DEFAULT 'Disponible',
    PRIMARY KEY (id_celda),
    CONSTRAINT UQ_Celda_Codigo UNIQUE (codigo)
) ENGINE=InnoDB;

-- MENSUALIDAD: una fila por cada pago/renovacion
CREATE TABLE IF NOT EXISTS MENSUALIDAD (
    id_mensualidad    INT AUTO_INCREMENT,
    fecha_ingreso     DATETIME NOT NULL,                         -- fecha de emision / inicio
    vencimiento_fecha DATETIME NOT NULL,                         -- inicio + 30 dias calendario
    estado            ENUM('Vigente','Vencida') NOT NULL DEFAULT 'Vigente',
    valor_pagado      DECIMAL(10,2) NOT NULL DEFAULT 0.00,       -- 250000 carros / 100000 motos
    id_vehiculo       INT NOT NULL,
    PRIMARY KEY (id_mensualidad),
    CONSTRAINT FK_Mensualidad_Vehiculo
        FOREIGN KEY (id_vehiculo) REFERENCES VEHICULO(id_vehiculo)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    INDEX IDX_Mensualidad_Vehiculo (id_vehiculo, estado)
) ENGINE=InnoDB;

-- ESTADIA: cada ingreso/salida de un vehiculo en una celda
CREATE TABLE IF NOT EXISTS ESTADIA (
    id_estancia  INT AUTO_INCREMENT,
    hora_entrada DATETIME NOT NULL,
    hora_salida  DATETIME NULL,                                  -- NULL = el vehiculo sigue dentro
    id_celda     INT NOT NULL,
    tarifa_total DECIMAL(10,2) DEFAULT 0.00,
    valor_pagado DECIMAL(10,2) DEFAULT 0.00,
    id_vehiculo  INT NOT NULL,
    id_operador  INT NOT NULL,
    vehiculo_activo INT GENERATED ALWAYS AS (IF(hora_salida IS NULL, id_vehiculo, NULL)) STORED,
    celda_activa    INT GENERATED ALWAYS AS (IF(hora_salida IS NULL, id_celda, NULL)) STORED,
    PRIMARY KEY (id_estancia),
    CONSTRAINT UQ_Estadia_VehiculoActivo UNIQUE (vehiculo_activo),
    CONSTRAINT UQ_Estadia_CeldaActiva    UNIQUE (celda_activa),
    CONSTRAINT FK_Estadia_Celda
        FOREIGN KEY (id_celda) REFERENCES CELDA(id_celda)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT FK_Estadia_Vehiculo
        FOREIGN KEY (id_vehiculo) REFERENCES VEHICULO(id_vehiculo)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT FK_Estadia_Operador
        FOREIGN KEY (id_operador) REFERENCES OPERADOR(id_operador)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

-- ============================================================
-- 2. VISTAS
-- ============================================================

-- Cupos por tipo de vehiculo (contadores de Entrada/Salida y Mapa de celdas)
CREATE OR REPLACE VIEW v_cupos AS
SELECT tipo,
       COUNT(*)                         AS total,
       SUM(estado = 'Disponible')       AS disponibles,
       SUM(estado = 'Ocupada')          AS ocupadas,
       SUM(estado = 'Reservada')        AS reservadas,
       SUM(estado = 'Mantenimiento')    AS mantenimiento
FROM CELDA
GROUP BY tipo;

-- Ultima mensualidad de cada vehiculo (pantalla Control de inscripciones)
CREATE OR REPLACE VIEW v_inscripciones AS
SELECT v.id_vehiculo, v.placa, v.tipo,
       CONCAT(v.marca, ' ', v.modelo)                  AS vehiculo,
       m.fecha_ingreso                                 AS fecha_emision,
       m.vencimiento_fecha,
       DATEDIFF(m.vencimiento_fecha, NOW())            AS dias_restantes,
       m.estado
FROM MENSUALIDAD m
JOIN VEHICULO v ON v.id_vehiculo = m.id_vehiculo
WHERE m.id_mensualidad = (SELECT MAX(m2.id_mensualidad)
                          FROM MENSUALIDAD m2
                          WHERE m2.id_vehiculo = m.id_vehiculo);

-- ============================================================
-- 3. DATOS INICIALES (ejecutar una sola vez)
-- ============================================================

-- 70 celdas de carros (C-01..C-70)
INSERT INTO CELDA (codigo, tipo)
SELECT CONCAT('C-', LPAD(d1.n * 10 + d2.n + 1, 2, '0')), 'Carro'
FROM (SELECT 0 n UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6) d1
CROSS JOIN (SELECT 0 n UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5
            UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9) d2
ORDER BY d1.n, d2.n;

-- 10 celdas de motos (M-01..M-10)
INSERT INTO CELDA (codigo, tipo)
SELECT CONCAT('M-', LPAD(d2.n + 1, 2, '0')), 'Moto'
FROM (SELECT 0 n UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5
      UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9) d2
ORDER BY d2.n;

-- Usuarios de ejemplo. Claves: admin123 y operador123
-- Los hashes son compatibles con werkzeug.security.check_password_hash de Flask.
INSERT INTO OPERADOR (nombre, telefono, usuario, clave_hash, rol) VALUES
('Carlos Ruiz', '3001112233', 'cruiz',  'pbkdf2:sha256:1000000$2fctL6LDGen83U89$e6ad5927079fdee6ee430ff483ae1d1b4cd2cec8dcf94bbd323fb2efc3b4a904', 'Administrador'),
('Laura Gómez', '3004445566', 'lgomez', 'pbkdf2:sha256:1000000$CxdLMrgunsGyHPRv$fe156e5a38ec783563bf7ac34b7a8ee203c95df3b56871c128e88ce2dd0899d3', 'Operador');

-- Datos de prueba
INSERT INTO VEHICULO (placa, tipo, marca, modelo, color) VALUES
('FGH456', 'Carro', 'Toyota',    'Corolla',  'Blanco perlado'),
('KSM234', 'Carro', 'Mazda',     '3 Sedan',  'Rojo'),
('XYZ789', 'Moto',  'Yamaha',    'FZ25',     'Negro'),
('ABC123', 'Carro', 'Renault',   'Logan',    'Gris'),
('MNP45F', 'Moto',  'Honda',     'CB190',    'Azul'),
('JKL321', 'Carro', 'Chevrolet', 'Onix',     'Plata'),
('RTY88B', 'Moto',  'Honda',     'CB125',    'Rojo');

INSERT INTO MENSUALIDAD (fecha_ingreso, vencimiento_fecha, estado, valor_pagado, id_vehiculo)
SELECT t.fi, DATE_ADD(t.fi, INTERVAL 30 DAY), t.est, t.valor, v.id_vehiculo
FROM (SELECT 'FGH456' placa, '2026-10-19' fi, 'Vigente' est, 250000 valor
      UNION ALL SELECT 'KSM234', '2026-11-12', 'Vigente', 250000
      UNION ALL SELECT 'XYZ789', '2026-10-13', 'Vencida', 100000
      UNION ALL SELECT 'ABC123', '2026-10-17', 'Vigente', 250000
      UNION ALL SELECT 'MNP45F', '2026-10-29', 'Vigente', 100000
      UNION ALL SELECT 'JKL321', '2026-10-11', 'Vencida', 250000
      UNION ALL SELECT 'RTY88B', '2026-10-21', 'Vigente', 100000) t
JOIN VEHICULO v ON v.placa = t.placa;

-- Tres estadias activas de ejemplo y sus celdas ocupadas
INSERT INTO ESTADIA (hora_entrada, id_celda, id_vehiculo, id_operador)
SELECT '2026-11-14 08:12:00', c.id_celda, v.id_vehiculo, 1 FROM CELDA c, VEHICULO v WHERE c.codigo = 'C-17' AND v.placa = 'FGH456';
INSERT INTO ESTADIA (hora_entrada, id_celda, id_vehiculo, id_operador)
SELECT '2026-11-14 08:40:00', c.id_celda, v.id_vehiculo, 2 FROM CELDA c, VEHICULO v WHERE c.codigo = 'C-02' AND v.placa = 'KSM234';
INSERT INTO ESTADIA (hora_entrada, id_celda, id_vehiculo, id_operador)
SELECT '2026-11-14 09:05:00', c.id_celda, v.id_vehiculo, 2 FROM CELDA c, VEHICULO v WHERE c.codigo = 'C-05' AND v.placa = 'ABC123';

UPDATE CELDA SET estado = 'Ocupada' WHERE codigo IN ('C-17', 'C-02', 'C-05');

-- Verificacion rapida:
-- SELECT * FROM v_cupos;
-- SELECT * FROM v_inscripciones;