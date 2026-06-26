from flask import Flask, jsonify
from flask_cors import CORS
from flask_jwt_extended import JWTManager
from datetime import timedelta
from flask import send_from_directory
import os

from app.routes.auth_route import auth_bp
from app.routes.register_routes import register_bp
from app.routes.password_routes import password_bp
from app.routes.admin_routes import admin_bp
from app.routes.category_routes import category_bp
from app.routes.profile_routes import profile_bp
from app.routes.product_routes import product_bp
from app.routes.order_routes import order_bp
from app.routes.reports_routes import reports_bp
from app.routes.dashboard_routes import dashboard_bp
from app.routes.delivery_staff_routes import delivery_staff_bp
from app.routes.seller_routes import seller_bp
from app.routes.cart_routes import cart_bp
from app.routes.payment_routes import payment_bp
from app.routes.user_public_routes import user_public_bp
from app.routes.user_account_routes import user_account_bp
from app.routes.user_checkout_routes import user_checkout_bp

app = Flask(__name__)
CORS(
    app,
    resources={r"/*": {"origins": "*"}},
    allow_headers=["Content-Type", "Authorization"],
)

app.config["JWT_SECRET_KEY"] = "my_super_secure_secret_key_2026_flutter_project_backend"

app.config["JWT_ACCESS_TOKEN_EXPIRES"] = timedelta(minutes=15)
app.config["JWT_REFRESH_TOKEN_EXPIRES"] = timedelta(days=7)

jwt = JWTManager(app)

@jwt.invalid_token_loader
def invalid_token_callback(reason):
    return jsonify({"error": "invalid_token", "message": reason}), 422

@jwt.unauthorized_loader
def unauthorized_callback(reason):
    return jsonify({"error": "missing_token", "message": reason}), 401

UPLOAD_FOLDER = os.path.join(os.getcwd(), 'uploads')
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

@app.route('/uploads/<path:filename>')
def uploaded_file(filename):
    return send_from_directory('uploads', filename)


app.register_blueprint(auth_bp)
app.register_blueprint(register_bp)
app.register_blueprint(password_bp)
app.register_blueprint(admin_bp)
app.register_blueprint(category_bp)
app.register_blueprint(profile_bp)
app.register_blueprint(product_bp)
app.register_blueprint(order_bp)
app.register_blueprint(reports_bp)
app.register_blueprint(dashboard_bp)
app.register_blueprint(delivery_staff_bp)
app.register_blueprint(seller_bp)
app.register_blueprint(cart_bp)
app.register_blueprint(payment_bp)
app.register_blueprint(user_public_bp)
app.register_blueprint(user_account_bp)
app.register_blueprint(user_checkout_bp)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
