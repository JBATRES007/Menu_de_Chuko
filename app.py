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
            admin_user.set_password('contrasenaperrona')
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