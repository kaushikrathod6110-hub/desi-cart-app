from flask import Flask, jsonify, send_from_directory
from flask_cors import CORS
from flask_jwt_extended import JWTManager
import os

from routes.auth_route import auth_bp
from routes.admin_routes import admin_bp
from routes.user_account_routes import user_account_bp
from routes.user_checkout_routes import user_checkout_bp
from routes.user_public_routes import user_public_bp
from routes.payment_routes import payment_bp
from routes.order_routes import order_bp
from routes.cart_routes import cart_bp
from routes.delivery_staff_routes import delivery_staff_bp
from routes.seller_routes import seller_bp
from routes.product_routes import product_bp
from routes.dashboard_routes import dashboard_bp

app = Flask(__name__)
app.config['JWT_SECRET_KEY'] = 'desi_cart_secret_key'
CORS(app)
jwt = JWTManager(app)

UPLOADS_FOLDER = os.path.join(os.getcwd(), 'uploads')
os.makedirs(UPLOADS_FOLDER, exist_ok=True)

@app.route('/')
def home():
    return jsonify({
        'success': True,
        'message': 'Desi Cart Backend Running'
    })

@app.route('/uploads/<path:filename>')
def uploaded_file(filename):
    return send_from_directory(UPLOADS_FOLDER, filename)

app.register_blueprint(auth_bp)
app.register_blueprint(admin_bp)
app.register_blueprint(user_account_bp)
app.register_blueprint(user_checkout_bp)
app.register_blueprint(user_public_bp)
app.register_blueprint(payment_bp)
app.register_blueprint(order_bp)
app.register_blueprint(cart_bp)
app.register_blueprint(delivery_staff_bp)
app.register_blueprint(seller_bp)
app.register_blueprint(product_bp)
app.register_blueprint(dashboard_bp)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)