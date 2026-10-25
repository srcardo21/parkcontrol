-- ============================================================
-- 1. CREACIÓN DE LA BASE DE DATOS
-- ============================================================
CREATE DATABASE IF NOT EXISTS parkcontrol_db;
USE parkcontrol_db;

-- ============================================================
-- 2. CREACIÓN DE TABLAS
-- ============================================================

-- Tabla: OPERADOR
CREATE TABLE OPERADOR (
    id_operador INT AUTO_INCREMENT,
    nombre VARCHAR(100) NOT NULL,
    telefono VARCHAR(20) NOT NULL,
    PRIMARY KEY (id_operador)
);

-- Tabla: VEHICULO
CREATE TABLE VEHICULO (
    id_vehiculo INT AUTO_INCREMENT,
    placa VARCHAR(10) NOT NULL UNIQUE,
    tipo VARCHAR(15) NOT NULL, -- Valores esperados: 'Carro' o 'Moto'
    marca VARCHAR(50) NOT NULL,
    modelo VARCHAR(50) NOT NULL,
    color VARCHAR(30) NOT NULL,
    PRIMARY KEY (id_vehiculo)
);

-- Tabla: MENSUALIDAD
CREATE TABLE MENSUALIDAD (
    id_mensualidad INT AUTO_INCREMENT,
    fecha_ingreso DATETIME NOT NULL,
    vencimiento_fecha DATETIME NOT NULL,
    estado VARCHAR(20) NOT NULL, -- Valores esperados: 'Vigente', 'Vencida' o 'sin asignar'
    id_vehiculo INT NOT NULL, -- Corregido: Se usa id_vehiculo en lugar de placa_vehiculo
    PRIMARY KEY (id_mensualidad),
    CONSTRAINT FK_Mensualidad_Vehiculo 
        FOREIGN KEY (id_vehiculo) REFERENCES VEHICULO(id_vehiculo) 
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT UQ_Vehiculo_Mensualidad 
        UNIQUE (id_vehiculo)
);

-- Tabla: ESTADIA
CREATE TABLE ESTADIA (
    id_estancia INT AUTO_INCREMENT,
    hora_entrada DATETIME NOT NULL,
    hora_salida DATETIME NULL, -- Permite NULL cuando el vehículo se encuentra dentro del parking
    celda_asignada INT NOT NULL,
    tarifa_total DECIMAL(10, 2) DEFAULT 0.00,
    valor_pagado DECIMAL(10, 2) DEFAULT 0.00,
    id_vehiculo INT NOT NULL, -- Corregido: Cambiado a INT para que coincida con VEHICULO(id_vehiculo)
    id_operador INT NOT NULL,
    PRIMARY KEY (id_estancia),
    CONSTRAINT FK_Estadia_Vehiculo 
        FOREIGN KEY (id_vehiculo) REFERENCES VEHICULO(id_vehiculo)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT FK_Estadia_Operador 
        FOREIGN KEY (id_operador) REFERENCES OPERADOR(id_operador)
        ON DELETE RESTRICT ON UPDATE CASCADE
);