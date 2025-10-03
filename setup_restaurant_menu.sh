#!/bin/bash

# Script para crear la estructura completa del proyecto Restaurant Menu
# Ejecutar con: bash setup_restaurant_menu.sh

echo "🚀 Iniciando creación del proyecto Restaurant Menu..."

# Crear directorio principal
mkdir -p restaurant_menu
cd restaurant_menu

echo "📁 Creando estructura de directorios..."

# Crear estructura de carpetas
mkdir -p templates
mkdir -p static/css
mkdir -p static/js
mkdir -p static/uploads
mkdir -p instance

echo "📄 Creando archivos del proyecto..."

# Crear requirements.txt
cat > requirements.txt << 'EOF'
Flask==2.3.3
Flask-SQLAlchemy==3.0.5
Flask-Login==0.6.3
Werkzeug==2.3.7
Pillow==10.0.0
qrcode==7.4.2
EOF

# Crear app.py
cat > app.py << 'EOF'
import os
from flask import Flask, render_template, request, redirect, url_for, flash, send_from_directory
from flask_sqlalchemy import SQLAlchemy
from flask_login import LoginManager, UserMixin, login_user, login_required, logout_user, current_user
from werkzeug.security import generate_password_hash, check_password_hash
from werkzeug.utils import secure_filename
from PIL import Image
import qrcode
import io
import base64

# Configuración de la aplicación
app = Flask(__name__)
app.config['SECRET_KEY'] = 'clave-secreta-muy-segura'
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///restaurant.db'
app.config['UPLOAD_FOLDER'] = 'static/uploads'
app.config['MAX_CONTENT_LENGTH'] = 16 * 1024 * 1024  # 16MB max file size

# Extensiones permitidas para imágenes
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'gif'}

# Inicialización de extensiones
db = SQLAlchemy(app)
login_manager = LoginManager()
login_manager.init_app(app)
login_manager.login_view = 'login'

# Modelos de base de datos
class User(UserMixin, db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True, nullable=False)
    password_hash = db.Column(db.String(120), nullable=False)

    def set_password(self, password):
        self.password_hash = generate_password_hash(password)

    def check_password(self, password):
        return check_password_hash(self.password_hash, password)

class Product(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100), nullable=False)
    description = db.Column(db.Text)
    price = db.Column(db.Float, nullable=False)
    image_filename = db.Column(db.String(200))
    is_active = db.Column(db.Boolean, default=True)

@login_manager.user_loader
def load_user(user_id):
    return User.query.get(int(user_id))

def allowed_file(filename):
    return '.' in filename and \
           filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

# Rutas de la aplicación
@app.route('/')
def index():
    return redirect(url_for('login'))

@app.route('/login', methods=['GET', 'POST'])
def login():
    if current_user.is_authenticated:
        return redirect(url_for('dashboard'))
    
    if request.method == 'POST':
        username = request.form.get('username')
        password = request.form.get('password')
        user = User.query.filter_by(username=username).first()
        
        if user and user.check_password(password):
            login_user(user)
            return redirect(url_for('dashboard'))
        else:
            flash('Usuario o contraseña incorrectos', 'error')
    
    return render_template('login.html')

@app.route('/logout')
@login_required
def logout():
    logout_user()
    return redirect(url_for('login'))

@app.route('/dashboard')
@login_required
def dashboard():
    products_count = Product.query.filter_by(is_active=True).count()
    return render_template('dashboard.html', products_count=products_count)

@app.route('/products')
@login_required
def products():
    all_products = Product.query.filter_by(is_active=True).all()
    return render_template('products.html', products=all_products)

@app.route('/add_product', methods=['GET', 'POST'])
@login_required
def add_product():
    if request.method == 'POST':
        name = request.form.get('name')
        description = request.form.get('description')
        price = request.form.get('price')
        
        # Validaciones básicas
        if not name or not price:
            flash('Nombre y precio son obligatorios', 'error')
            return render_template('add_product.html')
        
        try:
            price = float(price)
        except ValueError:
            flash('El precio debe ser un número válido', 'error')
            return render_template('add_product.html')
        
        # Manejo de la imagen
        image_filename = None
        if 'image' in request.files:
            file = request.files['image']
            if file and file.filename != '' and allowed_file(file.filename):
                filename = secure_filename(file.filename)
                # Renombrar archivo para evitar conflictos
                name_part = secure_filename(name)[:20]
                file_extension = filename.rsplit('.', 1)[1].lower()
                image_filename = f"{name_part}_{db.session.query(Product).count() + 1}.{file_extension}"
                file.save(os.path.join(app.config['UPLOAD_FOLDER'], image_filename))
        
        # Crear producto
        new_product = Product(
            name=name,
            description=description,
            price=price,
            image_filename=image_filename
        )
        
        db.session.add(new_product)
        db.session.commit()
        
        flash('Producto agregado exitosamente', 'success')
        return redirect(url_for('products'))
    
    return render_template('add_product.html')

@app.route('/edit_product/<int:product_id>', methods=['GET', 'POST'])
@login_required
def edit_product(product_id):
    product = Product.query.get_or_404(product_id)
    
    if request.method == 'POST':
        product.name = request.form.get('name')
        product.description = request.form.get('description')
        product.price = request.form.get('price')
        
        # Validaciones
        if not product.name or not product.price:
            flash('Nombre y precio son obligatorios', 'error')
            return render_template('edit_product.html', product=product)
        
        try:
            product.price = float(product.price)
        except ValueError:
            flash('El precio debe ser un número válido', 'error')
            return render_template('edit_product.html', product=product)
        
        # Manejo de nueva imagen
        if 'image' in request.files:
            file = request.files['image']
            if file and file.filename != '' and allowed_file(file.filename):
                # Eliminar imagen anterior si existe
                if product.image_filename:
                    old_image_path = os.path.join(app.config['UPLOAD_FOLDER'], product.image_filename)
                    if os.path.exists(old_image_path):
                        os.remove(old_image_path)
                
                # Guardar nueva imagen
                filename = secure_filename(file.filename)
                name_part = secure_filename(product.name)[:20]
                file_extension = filename.rsplit('.', 1)[1].lower()
                product.image_filename = f"{name_part}_{product_id}.{file_extension}"
                file.save(os.path.join(app.config['UPLOAD_FOLDER'], product.image_filename))
        
        db.session.commit()
        flash('Producto actualizado exitosamente', 'success')
        return redirect(url_for('products'))
    
    return render_template('edit_product.html', product=product)

@app.route('/delete_product/<int:product_id>')
@login_required
def delete_product(product_id):
    product = Product.query.get_or_404(product_id)
    product.is_active = False
    
    # Opcional: eliminar la imagen del producto
    # if product.image_filename:
    #     image_path = os.path.join(app.config['UPLOAD_FOLDER'], product.image_filename)
    #     if os.path.exists(image_path):
    #         os.remove(image_path)
    
    db.session.commit()
    flash('Producto eliminado exitosamente', 'success')
    return redirect(url_for('products'))

@app.route('/menu')
def menu():
    products = Product.query.filter_by(is_active=True).all()
    return render_template('menu.html', products=products)

@app.route('/generate_qr')
@login_required
def generate_qr():
    # Generar URL del menú
    menu_url = url_for('menu', _external=True)
    
    # Crear código QR
    qr = qrcode.QRCode(
        version=1,
        error_correction=qrcode.constants.ERROR_CORRECT_L,
        box_size=10,
        border=4,
    )
    qr.add_data(menu_url)
    qr.make(fit=True)
    
    # Crear imagen del QR
    img = qr.make_image(fill_color="black", back_color="white")
    
    # Convertir a base64 para mostrar en HTML
    buffer = io.BytesIO()
    img.save(buffer, format='PNG')
    buffer.seek(0)
    qr_base64 = base64.b64encode(buffer.getvalue()).decode()
    
    return render_template('dashboard.html', qr_code=qr_base64, menu_url=menu_url)

# Inicialización de la base de datos y usuario admin
def init_db():
    with app.app_context():
        db.create_all()
        
        # Crear usuario admin por defecto si no existe
        admin_user = User.query.filter_by(username='admin').first()
        if not admin_user:
            admin_user = User(username='admin')
            admin_user.set_password('admin123')
            db.session.add(admin_user)
            db.session.commit()
            print("Usuario admin creado: admin / admin123")

if __name__ == '__main__':
    # Crear directorios necesarios
    os.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)
    os.makedirs('instance', exist_ok=True)
    
    # Inicializar base de datos
    init_db()
    
    app.run(debug=True)
EOF

# Crear templates/base.html
cat > templates/base.html << 'EOF'
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{% block title %}Sistema Menú Restaurante{% endblock %}</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.10.0/font/bootstrap-icons.css">
    <link rel="stylesheet" href="{{ url_for('static', filename='css/style.css') }}">
</head>
<body>
    {% if current_user.is_authenticated %}
    <nav class="navbar navbar-expand-lg navbar-dark bg-dark">
        <div class="container">
            <a class="navbar-brand" href="{{ url_for('dashboard') }}">
                <i class="bi bi-cup-hot"></i> Restaurante Admin
            </a>
            <button class="navbar-toggler" type="button" data-bs-toggle="collapse" data-bs-target="#navbarNav">
                <span class="navbar-toggler-icon"></span>
            </button>
            <div class="collapse navbar-collapse" id="navbarNav">
                <ul class="navbar-nav ms-auto">
                    <li class="nav-item">
                        <a class="nav-link" href="{{ url_for('dashboard') }}">Dashboard</a>
                    </li>
                    <li class="nav-item">
                        <a class="nav-link" href="{{ url_for('products') }}">Productos</a>
                    </li>
                    <li class="nav-item">
                        <a class="nav-link" href="{{ url_for('logout') }}">Cerrar Sesión</a>
                    </li>
                </ul>
            </div>
        </div>
    </nav>
    {% endif %}

    <div class="container mt-4">
        {% with messages = get_flashed_messages(with_categories=true) %}
            {% if messages %}
                {% for category, message in messages %}
                    <div class="alert alert-{{ 'danger' if category == 'error' else 'success' }} alert-dismissible fade show">
                        {{ message }}
                        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
                    </div>
                {% endfor %}
            {% endif %}
        {% endwith %}

        {% block content %}{% endblock %}
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    <script src="{{ url_for('static', filename='js/script.js') }}"></script>
</body>
</html>
EOF

# Crear templates/login.html
cat > templates/login.html << 'EOF'
{% extends "base.html" %}

{% block title %}Iniciar Sesión - Sistema Menú{% endblock %}

{% block content %}
<div class="row justify-content-center">
    <div class="col-md-6 col-lg-4">
        <div class="card shadow">
            <div class="card-body p-5">
                <h2 class="text-center mb-4">
                    <i class="bi bi-cup-hot text-primary"></i><br>
                    Sistema Menú
                </h2>
                <h4 class="text-center mb-4">Iniciar Sesión</h4>
                
                <form method="POST">
                    <div class="mb-3">
                        <label for="username" class="form-label">Usuario:</label>
                        <input type="text" class="form-control" id="username" name="username" required>
                    </div>
                    <div class="mb-3">
                        <label for="password" class="form-label">Contraseña:</label>
                        <input type="password" class="form-control" id="password" name="password" required>
                    </div>
                    <button type="submit" class="btn btn-primary w-100">Ingresar</button>
                </form>
                
                <div class="mt-4 text-center">
                    <small class="text-muted">
                        <strong>Credenciales por defecto:</strong><br>
                        Usuario: admin<br>
                        Contraseña: admin123
                    </small>
                </div>
            </div>
        </div>
    </div>
</div>
{% endblock %}
EOF

# Crear templates/dashboard.html
cat > templates/dashboard.html << 'EOF'
{% extends "base.html" %}

{% block title %}Dashboard - Sistema Menú{% endblock %}

{% block content %}
<div class="row">
    <div class="col-12">
        <h1 class="mb-4">Dashboard</h1>
    </div>
</div>

<div class="row">
    <div class="col-md-4 mb-4">
        <div class="card text-white bg-primary">
            <div class="card-body">
                <div class="d-flex justify-content-between">
                    <div>
                        <h4 class="card-title">{{ products_count }}</h4>
                        <p class="card-text">Productos Activos</p>
                    </div>
                    <div class="align-self-center">
                        <i class="bi bi-egg-fried fs-1"></i>
                    </div>
                </div>
            </div>
        </div>
    </div>
    
    <div class="col-md-4 mb-4">
        <div class="card text-white bg-success">
            <div class="card-body">
                <div class="d-flex justify-content-between">
                    <div>
                        <h4 class="card-title">Gestión</h4>
                        <p class="card-text">Catálogo de Productos</p>
                    </div>
                    <div class="align-self-center">
                        <i class="bi bi-list-check fs-1"></i>
                    </div>
                </div>
            </div>
        </div>
    </div>
    
    <div class="col-md-4 mb-4">
        <div class="card text-white bg-info">
            <div class="card-body">
                <div class="d-flex justify-content-between">
                    <div>
                        <h4 class="card-title">QR</h4>
                        <p class="card-text">Menú Digital</p>
                    </div>
                    <div class="align-self-center">
                        <i class="bi bi-qr-code fs-1"></i>
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>

<div class="row mt-4">
    <div class="col-md-6">
        <div class="card">
            <div class="card-header">
                <h5 class="card-title mb-0">Acciones Rápidas</h5>
            </div>
            <div class="card-body">
                <div class="d-grid gap-2">
                    <a href="{{ url_for('products') }}" class="btn btn-outline-primary">
                        <i class="bi bi-list-ul"></i> Ver Todos los Productos
                    </a>
                    <a href="{{ url_for('add_product') }}" class="btn btn-outline-success">
                        <i class="bi bi-plus-circle"></i> Agregar Nuevo Producto
                    </a>
                    <a href="{{ url_for('generate_qr') }}" class="btn btn-outline-info">
                        <i class="bi bi-qr-code"></i> Generar Código QR del Menú
                    </a>
                </div>
            </div>
        </div>
    </div>
    
    <div class="col-md-6">
        <div class="card">
            <div class="card-header">
                <h5 class="card-title mb-0">Código QR del Menú</h5>
            </div>
            <div class="card-body text-center">
                {% if qr_code %}
                    <img src="data:image/png;base64,{{ qr_code }}" alt="Código QR del Menú" class="img-fluid mb-3" style="max-width: 200px;">
                    <p class="small text-muted">Escanea este código para ver el menú</p>
                    <p class="small">
                        <strong>URL:</strong> 
                        <a href="{{ menu_url }}" target="_blank">{{ menu_url }}</a>
                    </p>
                {% else %}
                    <p class="text-muted">Haz clic en "Generar Código QR" para crear el código QR de tu menú.</p>
                    <a href="{{ url_for('generate_qr') }}" class="btn btn-primary">
                        <i class="bi bi-qr-code"></i> Generar Código QR
                    </a>
                {% endif %}
            </div>
        </div>
    </div>
</div>
{% endblock %}
EOF

# Crear templates/products.html
cat > templates/products.html << 'EOF'
{% extends "base.html" %}

{% block title %}Productos - Sistema Menú{% endblock %}

{% block content %}
<div class="d-flex justify-content-between align-items-center mb-4">
    <h1>Gestión de Productos</h1>
    <a href="{{ url_for('add_product') }}" class="btn btn-success">
        <i class="bi bi-plus-circle"></i> Agregar Producto
    </a>
</div>

<div class="row">
    {% for product in products %}
    <div class="col-md-6 col-lg-4 mb-4">
        <div class="card h-100">
            {% if product.image_filename %}
            <img src="{{ url_for('static', filename='uploads/' + product.image_filename) }}" 
                 class="card-img-top product-image" alt="{{ product.name }}">
            {% else %}
            <div class="card-img-top bg-light d-flex align-items-center justify-content-center" style="height: 200px;">
                <i class="bi bi-image text-muted fs-1"></i>
            </div>
            {% endif %}
            
            <div class="card-body">
                <h5 class="card-title">{{ product.name }}</h5>
                <p class="card-text">{{ product.description or 'Sin descripción' }}</p>
                <h6 class="text-primary">${{ "%.2f"|format(product.price) }}</h6>
            </div>
            
            <div class="card-footer bg-transparent">
                <div class="btn-group w-100">
                    <a href="{{ url_for('edit_product', product_id=product.id) }}" 
                       class="btn btn-outline-primary btn-sm">
                        <i class="bi bi-pencil"></i> Editar
                    </a>
                    <a href="{{ url_for('delete_product', product_id=product.id) }}" 
                       class="btn btn-outline-danger btn-sm"
                       onclick="return confirm('¿Estás seguro de que quieres eliminar este producto?')">
                        <i class="bi bi-trash"></i> Eliminar
                    </a>
                </div>
            </div>
        </div>
    </div>
    {% else %}
    <div class="col-12">
        <div class="alert alert-info text-center">
            <i class="bi bi-info-circle"></i> No hay productos registrados.
            <a href="{{ url_for('add_product') }}" class="alert-link">Agrega el primer producto</a>.
        </div>
    </div>
    {% endfor %}
</div>
{% endblock %}
EOF

# Crear templates/add_product.html
cat > templates/add_product.html << 'EOF'
{% extends "base.html" %}

{% block title %}Agregar Producto - Sistema Menú{% endblock %}

{% block content %}
<div class="row justify-content-center">
    <div class="col-md-8">
        <div class="card">
            <div class="card-header">
                <h4 class="card-title mb-0">
                    <i class="bi bi-plus-circle"></i> Agregar Nuevo Producto
                </h4>
            </div>
            <div class="card-body">
                <form method="POST" enctype="multipart/form-data">
                    <div class="mb-3">
                        <label for="name" class="form-label">Nombre del Producto *</label>
                        <input type="text" class="form-control" id="name" name="name" required>
                    </div>
                    
                    <div class="mb-3">
                        <label for="description" class="form-label">Descripción</label>
                        <textarea class="form-control" id="description" name="description" rows="3"></textarea>
                    </div>
                    
                    <div class="mb-3">
                        <label for="price" class="form-label">Precio *</label>
                        <div class="input-group">
                            <span class="input-group-text">C$</span>
                            <input type="number" class="form-control" id="price" name="price" 
                                   step="0.01" min="0" required>
                        </div>
                    </div>
                    
                    <div class="mb-3">
                        <label for="image" class="form-label">Imagen del Producto</label>
                        <input type="file" class="form-control" id="image" name="image" 
                               accept="image/*">
                        <div class="form-text">
                            Formatos permitidos: JPG, PNG, GIF. Tamaño máximo: 16MB.
                        </div>
                    </div>
                    
                    <div class="d-grid gap-2 d-md-flex justify-content-md-end">
                        <a href="{{ url_for('products') }}" class="btn btn-secondary me-md-2">
                            <i class="bi bi-arrow-left"></i> Cancelar
                        </a>
                        <button type="submit" class="btn btn-primary">
                            <i class="bi bi-check-circle"></i> Guardar Producto
                        </button>
                    </div>
                </form>
            </div>
        </div>
    </div>
</div>
{% endblock %}
EOF

# Crear templates/edit_product.html
cat > templates/edit_product.html << 'EOF'
{% extends "base.html" %}

{% block title %}Editar Producto - Sistema Menú{% endblock %}

{% block content %}
<div class="row justify-content-center">
    <div class="col-md-8">
        <div class="card">
            <div class="card-header">
                <h4 class="card-title mb-0">
                    <i class="bi bi-pencil"></i> Editar Producto
                </h4>
            </div>
            <div class="card-body">
                <form method="POST" enctype="multipart/form-data">
                    <div class="mb-3">
                        <label for="name" class="form-label">Nombre del Producto *</label>
                        <input type="text" class="form-control" id="name" name="name" 
                               value="{{ product.name }}" required>
                    </div>
                    
                    <div class="mb-3">
                        <label for="description" class="form-label">Descripción</label>
                        <textarea class="form-control" id="description" name="description" 
                                  rows="3">{{ product.description or '' }}</textarea>
                    </div>
                    
                    <div class="mb-3">
                        <label for="price" class="form-label">Precio *</label>
                        <div class="input-group">
                            <span class="input-group-text">$</span>
                            <input type="number" class="form-control" id="price" name="price" 
                                   step="0.01" min="0" value="{{ product.price }}" required>
                        </div>
                    </div>
                    
                    <div class="mb-3">
                        <label for="image" class="form-label">Imagen del Producto</label>
                        
                        {% if product.image_filename %}
                        <div class="mb-2">
                            <img src="{{ url_for('static', filename='uploads/' + product.image_filename) }}" 
                                 class="img-thumbnail" style="max-height: 150px;" 
                                 alt="{{ product.name }}">
                            <div class="form-text">Imagen actual</div>
                        </div>
                        {% endif %}
                        
                        <input type="file" class="form-control" id="image" name="image" 
                               accept="image/*">
                        <div class="form-text">
                            Selecciona una nueva imagen para reemplazar la actual. Formatos permitidos: JPG, PNG, GIF.
                        </div>
                    </div>
                    
                    <div class="d-grid gap-2 d-md-flex justify-content-md-end">
                        <a href="{{ url_for('products') }}" class="btn btn-secondary me-md-2">
                            <i class="bi bi-arrow-left"></i> Cancelar
                        </a>
                        <button type="submit" class="btn btn-primary">
                            <i class="bi bi-check-circle"></i> Actualizar Producto
                        </button>
                    </div>
                </form>
            </div>
        </div>
    </div>
</div>
{% endblock %}
EOF

# Crear templates/menu.html
cat > templates/menu.html << 'EOF'
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Menú - Nuestro Restaurante</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.10.0/font/bootstrap-icons.css">
    <style>
        body {
            background-color: #f8f9fa;
        }
        .menu-header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 3rem 0;
            margin-bottom: 2rem;
        }
        .product-card {
            transition: transform 0.2s;
            border: none;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .product-card:hover {
            transform: translateY(-5px);
        }
        .product-image {
            height: 200px;
            object-fit: cover;
        }
        .price-tag {
            font-size: 1.25rem;
            font-weight: bold;
            color: #28a745;
        }
    </style>
</head>
<body>
    <div class="menu-header text-center">
        <div class="container">
            <h1 class="display-4 mb-3">
                <i class="bi bi-cup-hot"></i>
            </h1>
            <h1 class="display-4 mb-3">Nuestro Menú</h1>
            <p class="lead">Los mejores platillos preparados con ingredientes frescos</p>
        </div>
    </div>

    <div class="container">
        {% if products %}
        <div class="row">
            {% for product in products %}
            <div class="col-md-6 col-lg-4 mb-4">
                <div class="card product-card h-100">
                    {% if product.image_filename %}
                    <img src="{{ url_for('static', filename='uploads/' + product.image_filename) }}" 
                         class="card-img-top product-image" alt="{{ product.name }}">
                    {% else %}
                    <div class="card-img-top bg-light d-flex align-items-center justify-content-center" style="height: 200px;">
                        <i class="bi bi-image text-muted fs-1"></i>
                    </div>
                    {% endif %}
                    
                    <div class="card-body">
                        <h5 class="card-title">{{ product.name }}</h5>
                        <p class="card-text text-muted">{{ product.description or 'Delicioso platillo preparado con los mejores ingredientes.' }}</p>
                    </div>
                    
                    <div class="card-footer bg-white border-0">
                        <div class="d-flex justify-content-between align-items-center">
                            <span class="price-tag">${{ "%.2f"|format(product.price) }}</span>
                            <span class="badge bg-success">Disponible</span>
                        </div>
                    </div>
                </div>
            </div>
            {% endfor %}
        </div>
        {% else %}
        <div class="text-center py-5">
            <i class="bi bi-emoji-frown fs-1 text-muted"></i>
            <h3 class="text-muted mt-3">Menú no disponible</h3>
            <p class="text-muted">Estamos actualizando nuestro menú. Vuelve pronto.</p>
        </div>
        {% endif %}
        
        <footer class="text-center mt-5 py-4 text-muted">
            <p>&copy; 2024 Nuestro Restaurante. Todos los derechos reservados.</p>
        </footer>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>
EOF

# Crear static/css/style.css
cat > static/css/style.css << 'EOF'
body {
    background-color: #f8f9fa;
}

.navbar-brand {
    font-weight: bold;
}

.card {
    border: none;
    box-shadow: 0 2px 10px rgba(0,0,0,0.1);
    transition: transform 0.2s;
}

.card:hover {
    transform: translateY(-2px);
}

.product-image {
    height: 200px;
    object-fit: cover;
}

.btn {
    border-radius: 6px;
}

.alert {
    border: none;
    border-radius: 8px;
}

.login-container {
    min-height: 100vh;
    display: flex;
    align-items: center;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
}

.login-card {
    border: none;
    border-radius: 15px;
}

.form-control {
    border-radius: 8px;
    padding: 12px;
}

.form-control:focus {
    box-shadow: 0 0 0 0.2rem rgba(102, 126, 234, 0.25);
    border-color: #667eea;
}

.btn-primary {
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    border: none;
    padding: 12px;
}

.btn-primary:hover {
    background: linear-gradient(135deg, #5a6fd8 0%, #6a4190 100%);
    transform: translateY(-1px);
}

.stat-card {
    border-radius: 12px;
}

.navbar {
    box-shadow: 0 2px 4px rgba(0,0,0,.1);
}
EOF

# Crear static/js/script.js
cat > static/js/script.js << 'EOF'
// Scripts adicionales para mejoras de UX
document.addEventListener('DOMContentLoaded', function() {
    // Auto-dismiss alerts after 5 seconds
    const alerts = document.querySelectorAll('.alert');
    alerts.forEach(alert => {
        setTimeout(() => {
            const bsAlert = new bootstrap.Alert(alert);
            bsAlert.close();
        }, 5000);
    });

    // Price input validation
    const priceInputs = document.querySelectorAll('input[type="number"]');
    priceInputs.forEach(input => {
        input.addEventListener('input', function() {
            if (this.value < 0) {
                this.value = 0;
            }
        });
    });

    // Image preview for file inputs
    const imageInputs = document.querySelectorAll('input[type="file"]');
    imageInputs.forEach(input => {
        input.addEventListener('change', function() {
            const file = this.files[0];
            if (file) {
                const reader = new FileReader();
                reader.onload = function(e) {
                    // Create preview image if it doesn't exist
                    let preview = input.parentNode.querySelector('.image-preview');
                    if (!preview) {
                        preview = document.createElement('img');
                        preview.className = 'image-preview img-thumbnail mt-2';
                        preview.style.maxHeight = '150px';
                        input.parentNode.appendChild(preview);
                    }
                    preview.src = e.target.result;
                }
                reader.readAsDataURL(file);
            }
        });
    });
});
EOF

# Crear README.md
cat > README.md << 'EOF'
# Sistema de Gestión de Menú para Restaurante

Una aplicación web completa para gestionar el menú de un restaurante con autenticación de administrador y generación de código QR.

## Características

- 🔐 Autenticación segura de administrador
- 📝 Gestión completa de productos (CRUD)
- 🖼️ Subida de imágenes para productos
- 📱 Menú público responsive
- 🔗 Generación de código QR para el menú
- 💾 Base de datos SQLite

## Instalación

1. Crear entorno virtual:
```bash
python -m venv venv
source venv/bin/activate  # Linux/Mac
venv\Scripts\activate     # Windows2. Instalar dependencias:
```bash
pip install -r requirements.txt
```

2. Ejecutar el servidor:
```bash
python app.py