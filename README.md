# ParkControl 🚗🅿️

Sistema de gestión y control de parqueaderos desarrollado en Python (Flask) y MySQL, empaquetado y listo para desplegar con Docker.

## 🚀 Requisitos
* [Docker Desktop](https://www.docker.com/products/docker-desktop/) instalado y en ejecución.
* Git.

## 📦 Puesta en marcha

1. Clonar el repositorio:
   ```bash
   git clone <URL_DEL_REPOSITORIO>
   cd parkcontrol
   ```

2. Levantar el entorno con Docker Compose:
   ```bash
   docker compose up -d --build
   ```

3. Abrir la aplicación en el navegador:
   👉 **[http://localhost:5000](http://localhost:5000)**

## 🔑 Credenciales de acceso

* **Administrador:**
  * Usuario: `cruiz` (o `admin`)
  * Clave: `admin123`
* **Operador:**
  * Usuario: `lgomez` (o `apena`)
  * Clave: `operador123`

## 🗄️ Acceso a la Base de Datos (DBeaver / MySQL)

* **Host:** `localhost`
* **Puerto:** `3306`
* **Base de datos:** `parkcontrol_db`
* **Usuario:** `root`
* **Contraseña:** `root`
