-- ============================================================
-- ParkControl Database Initialization Script
-- ============================================================

CREATE DATABASE IF NOT EXISTS parkcontrol_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE parkcontrol_db;

-- ------------------------------------------------------------
-- 1. TABLA: OPERADOR
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS OPERADOR (
    id_operador INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    telefono VARCHAR(20) NOT NULL,
    usuario VARCHAR(50) NOT NULL UNIQUE,
    clave_hash VARCHAR(255) NOT NULL,
    rol VARCHAR(20) NOT NULL DEFAULT 'Operador',
    estado VARCHAR(20) NOT NULL DEFAULT 'Activo',
    inactivo_hasta DATE NULL
);

-- ------------------------------------------------------------
-- 2. TABLA: VEHICULO
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS VEHICULO (
    id_vehiculo INT AUTO_INCREMENT PRIMARY KEY,
    placa VARCHAR(10) NOT NULL UNIQUE,
    tipo VARCHAR(15) NOT NULL,
    marca VARCHAR(50) NOT NULL,
    modelo VARCHAR(50) NOT NULL,
    color VARCHAR(30) NOT NULL,
    estado VARCHAR(20) NOT NULL DEFAULT 'Activo',
    inactivo_hasta DATE NULL
);

-- ------------------------------------------------------------
-- 3. TABLA: MENSUALIDAD
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS MENSUALIDAD (
    id_mensualidad INT AUTO_INCREMENT PRIMARY KEY,
    fecha_ingreso DATETIME NOT NULL,
    vencimiento_fecha DATETIME NOT NULL,
    estado VARCHAR(20) NOT NULL DEFAULT 'Vigente',
    valor_pagado DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    id_vehiculo INT NOT NULL,
    CONSTRAINT FK_Mensualidad_Vehiculo
        FOREIGN KEY (id_vehiculo) REFERENCES VEHICULO(id_vehiculo)
        ON DELETE CASCADE ON UPDATE CASCADE
);

-- ------------------------------------------------------------
-- 4. TABLA: CELDA
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS CELDA (
    id_celda INT AUTO_INCREMENT PRIMARY KEY,
    codigo VARCHAR(10) NOT NULL UNIQUE,
    tipo VARCHAR(15) NOT NULL,
    estado VARCHAR(20) NOT NULL DEFAULT 'Disponible'
);

-- ------------------------------------------------------------
-- 5. TABLA: ESTADIA
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ESTADIA (
    id_estancia INT AUTO_INCREMENT PRIMARY KEY,
    hora_entrada DATETIME NOT NULL,
    hora_salida DATETIME NULL,
    id_celda INT NOT NULL,
    id_vehiculo INT NOT NULL,
    id_operador INT NOT NULL,
    tarifa_total DECIMAL(10, 2) DEFAULT 0.00,
    valor_pagado DECIMAL(10, 2) DEFAULT 0.00,
    CONSTRAINT FK_Estadia_Celda
        FOREIGN KEY (id_celda) REFERENCES CELDA(id_celda)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT FK_Estadia_Vehiculo
        FOREIGN KEY (id_vehiculo) REFERENCES VEHICULO(id_vehiculo)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT FK_Estadia_Operador
        FOREIGN KEY (id_operador) REFERENCES OPERADOR(id_operador)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

-- ------------------------------------------------------------
-- 6. VISTAS
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_cupos AS
SELECT 
    c.tipo,
    COUNT(*) AS total,
    SUM(CASE WHEN c.estado = 'Disponible' THEN 1 ELSE 0 END) AS disponibles
FROM CELDA c
GROUP BY c.tipo;

CREATE OR REPLACE VIEW v_inscripciones AS
SELECT 
    m.id_mensualidad,
    m.id_vehiculo,
    v.placa,
    v.tipo,
    CONCAT(v.marca, ' ', v.modelo) AS vehiculo,
    m.fecha_ingreso AS fecha_emision,
    m.vencimiento_fecha,
    DATEDIFF(m.vencimiento_fecha, NOW()) AS dias_restantes,
    m.estado
FROM MENSUALIDAD m
INNER JOIN VEHICULO v ON m.id_vehiculo = v.id_vehiculo
WHERE m.id_mensualidad = (
    SELECT MAX(m2.id_mensualidad)
    FROM MENSUALIDAD m2
    WHERE m2.id_vehiculo = m.id_vehiculo
);

-- ------------------------------------------------------------
-- 7. DATOS INICIALES (SEED DATA)
-- ------------------------------------------------------------

-- Operadores y Administradores (Contraseñas: admin123 / operador123)
INSERT INTO OPERADOR (id_operador, nombre, telefono, usuario, clave_hash, rol, estado) VALUES
(1, 'Carlos Ruiz', '3001234567', 'cruiz', 'scrypt:32768:8:1$DWkBF7Otgpy2AFo1$ce6bcf16549cd5cc2136678af5194c31c92f787c9d23a9667814f065e3d913738b7511305718c1bd15c98a7a74a0701cade7682bffc3874fccbe0d963842a88c', 'Administrador', 'Activo'),
(2, 'Administrador General', '3009876543', 'admin', 'scrypt:32768:8:1$DWkBF7Otgpy2AFo1$ce6bcf16549cd5cc2136678af5194c31c92f787c9d23a9667814f065e3d913738b7511305718c1bd15c98a7a74a0701cade7682bffc3874fccbe0d963842a88c', 'Administrador', 'Activo'),
(3, 'Laura Gómez', '3002345678', 'lgomez', 'scrypt:32768:8:1$CvvMkLSpnKS5lNvD$c6239ef58a5c6cd6e860e355567711fa0f0c572eff5352c307df2d4727af07ef620fbd647128bca7f1a15d83cccad89e92d63330d0a84d113e08881863ee9737', 'Operador', 'Activo'),
(4, 'Andrés Peña', '3003456789', 'apena', 'scrypt:32768:8:1$CvvMkLSpnKS5lNvD$c6239ef58a5c6cd6e860e355567711fa0f0c572eff5352c307df2d4727af07ef620fbd647128bca7f1a15d83cccad89e92d63330d0a84d113e08881863ee9737', 'Operador', 'Activo');

-- Generación de 70 celdas para automóviles (C-01 a C-70)
INSERT INTO CELDA (codigo, tipo, estado) VALUES
('C-01', 'Carro', 'Disponible'), ('C-02', 'Carro', 'Disponible'), ('C-03', 'Carro', 'Disponible'), ('C-04', 'Carro', 'Disponible'),
('C-05', 'Carro', 'Disponible'), ('C-06', 'Carro', 'Disponible'), ('C-07', 'Carro', 'Disponible'), ('C-08', 'Carro', 'Disponible'),
('C-09', 'Carro', 'Disponible'), ('C-10', 'Carro', 'Disponible'), ('C-11', 'Carro', 'Disponible'), ('C-12', 'Carro', 'Disponible'),
('C-13', 'Carro', 'Disponible'), ('C-14', 'Carro', 'Disponible'), ('C-15', 'Carro', 'Disponible'), ('C-16', 'Carro', 'Disponible'),
('C-17', 'Carro', 'Ocupada'),    ('C-18', 'Carro', 'Disponible'), ('C-19', 'Carro', 'Disponible'), ('C-20', 'Carro', 'Disponible'),
('C-21', 'Carro', 'Mantenimiento'), ('C-22', 'Carro', 'Disponible'), ('C-23', 'Carro', 'Disponible'), ('C-24', 'Carro', 'Disponible'),
('C-25', 'Carro', 'Disponible'), ('C-26', 'Carro', 'Disponible'), ('C-27', 'Carro', 'Disponible'), ('C-28', 'Carro', 'Disponible'),
('C-29', 'Carro', 'Disponible'), ('C-30', 'Carro', 'Disponible'), ('C-31', 'Carro', 'Disponible'), ('C-32', 'Carro', 'Disponible'),
('C-33', 'Carro', 'Disponible'), ('C-34', 'Carro', 'Disponible'), ('C-35', 'Carro', 'Disponible'), ('C-36', 'Carro', 'Disponible'),
('C-37', 'Carro', 'Disponible'), ('C-38', 'Carro', 'Disponible'), ('C-39', 'Carro', 'Disponible'), ('C-40', 'Carro', 'Disponible'),
('C-41', 'Carro', 'Disponible'), ('C-42', 'Carro', 'Disponible'), ('C-43', 'Carro', 'Disponible'), ('C-44', 'Carro', 'Disponible'),
('C-45', 'Carro', 'Disponible'), ('C-46', 'Carro', 'Disponible'), ('C-47', 'Carro', 'Disponible'), ('C-48', 'Carro', 'Disponible'),
('C-49', 'Carro', 'Disponible'), ('C-50', 'Carro', 'Disponible'), ('C-51', 'Carro', 'Disponible'), ('C-52', 'Carro', 'Disponible'),
('C-53', 'Carro', 'Disponible'), ('C-54', 'Carro', 'Disponible'), ('C-55', 'Carro', 'Disponible'), ('C-56', 'Carro', 'Disponible'),
('C-57', 'Carro', 'Disponible'), ('C-58', 'Carro', 'Disponible'), ('C-59', 'Carro', 'Disponible'), ('C-60', 'Carro', 'Disponible'),
('C-61', 'Carro', 'Disponible'), ('C-62', 'Carro', 'Disponible'), ('C-63', 'Carro', 'Disponible'), ('C-64', 'Carro', 'Disponible'),
('C-65', 'Carro', 'Disponible'), ('C-66', 'Carro', 'Disponible'), ('C-67', 'Carro', 'Disponible'), ('C-68', 'Carro', 'Disponible'),
('C-69', 'Carro', 'Disponible'), ('C-70', 'Carro', 'Disponible');

-- Generación de 10 celdas para motocicletas (M-01 a M-10)
INSERT INTO CELDA (codigo, tipo, estado) VALUES
('M-01', 'Moto', 'Disponible'), ('M-02', 'Moto', 'Disponible'), ('M-03', 'Moto', 'Disponible'), ('M-04', 'Moto', 'Disponible'),
('M-05', 'Moto', 'Disponible'), ('M-06', 'Moto', 'Disponible'), ('M-07', 'Moto', 'Disponible'), ('M-08', 'Moto', 'Disponible'),
('M-09', 'Moto', 'Disponible'), ('M-10', 'Moto', 'Disponible');

-- Vehículos iniciales
INSERT INTO VEHICULO (id_vehiculo, placa, tipo, marca, modelo, color, estado) VALUES
(1, 'FGH456', 'Carro', 'Toyota', 'Corolla', 'Blanco perlado', 'Activo'),
(2, 'KSM234', 'Carro', 'Mazda', '3 Sedan', 'Rojo', 'Activo'),
(3, 'XYZ789', 'Moto', 'Yamaha', 'FZ25', 'Negro', 'Activo'),
(4, 'ABC123', 'Carro', 'Renault', 'Logan', 'Gris', 'Activo'),
(5, 'MNP45F', 'Moto', 'Honda', 'CB190', 'Azul', 'Activo'),
(6, 'JKL321', 'Carro', 'Chevrolet', 'Onix', 'Blanco', 'Activo');

-- Mensualidades iniciales
INSERT INTO MENSUALIDAD (fecha_ingreso, vencimiento_fecha, estado, valor_pagado, id_vehiculo) VALUES
(NOW() - INTERVAL 26 DAY, NOW() + INTERVAL 4 DAY, 'Vigente', 250000.00, 1),
(NOW() - INTERVAL 3 DAY, NOW() + INTERVAL 27 DAY, 'Vigente', 250000.00, 2),
(NOW() - INTERVAL 35 DAY, NOW() - INTERVAL 5 DAY, 'Vencida', 100000.00, 3),
(NOW() - INTERVAL 10 DAY, NOW() + INTERVAL 20 DAY, 'Vigente', 250000.00, 4),
(NOW() - INTERVAL 15 DAY, NOW() + INTERVAL 15 DAY, 'Vigente', 100000.00, 5),
(NOW() - INTERVAL 40 DAY, NOW() - INTERVAL 10 DAY, 'Vencida', 250000.00, 6);

-- Estadía activa para FGH456 en C-17
INSERT INTO ESTADIA (hora_entrada, hora_salida, id_celda, id_vehiculo, id_operador, tarifa_total, valor_pagado) VALUES
(NOW() - INTERVAL 2 HOUR, NULL, 17, 1, 1, 0.00, 0.00);
