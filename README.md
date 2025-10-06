# Sistema de Gestión de Menú para Restaurante

Una aplicación web completa para gestionar el menú de restaurante con autenticación de administrador y generación de código QR.

## Características

- 🔐 **Autenticación segura** de administrador
- 📝 **Gestión completa** de productos (CRUD)
- 🖼️ **Subida de imágenes** con validación
- 📱 **Menú público** responsive
- 🔗 **Generación de código QR** automática
- 💾 **Base de datos** SQLite integrada
- 🎨 **Interfaz moderna** con Bootstrap 5

### Prerrequisitos
- Python 3.8 o superior
- pip (gestor de paquetes de Python)

## Instalación

1. Crear entorno virtual:
   python -m venv venv
   source venv/bin/activate  # Linux/Mac
   source venv\Scripts\activate     # Windows

2. Instalar dependencias:
   pip install -r requirements.txt

3. Ejecutar el servidor:
   python app.py

 **Clonar el repositorio:**
```bash
git clone https://github.com/tu-usuario/restaurant-menu-system.git
cd restaurant-menu-system

## Uso

- Accede a la aplicación en tu navegador en `http://127.0.0.1:5000`.
- Inicia sesión con las credenciales por defecto:
  - Usuario: admin
  - Contraseña: admin123



## Estructura del Proyecto

```
restaurant_menu
├── app.py
├── requirements.txt
├── README.md
├── instance
├── static
│   ├── css
│   │   └── style.css
│   ├── js
│   │   └── script.js
│   └── uploads
├── templates
│   ├── base.html
│   ├── login.html
│   ├── dashboard.html
│   ├── products.html
│   ├── add_product.html
│   ├── edit_product.html
│   └── menu.html
```

git remote add origin https://github.com/JBATRES007/restaurant-menu-system.git
git branch -M main
git push -u origin main

📋 Comandos útiles para el futuro
bash
# Para actualizar el repositorio después de hacer cambios
./deploy.sh "Descripción de los cambios realizados"

# O manualmente:
git add .
git commit -m "Descripción de los cambios"
git push origin main