from flask import Blueprint, request, jsonify
from db import get_db_connection
import bcrypt

register_bp = Blueprint('register_bp', __name__)

@register_bp.route('/register/user', methods=['POST'])
def register_user():
    data = request.json

    name = data.get("user_name")
    email = data.get("user_email")
    mobile = data.get("user_mobile")
    password = data.get("user_pass")

    hashed_pass = bcrypt.hashpw(password.encode('utf-8'),bcrypt.gensalt())

    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)

    cursor.execute("SELECT * FROM user WHERE user_email = %s",(email,))
    existing_user = cursor.fetchone()

    if existing_user:
        return jsonify({"message": "Email already registered!"}), 400
    
    cursor.execute("""
        INSERT INTO user(user_name, user_email, user_mobile, user_pass) VALUES (%s, %s, %s, %s)
    """, (name, email, mobile, hashed_pass))

    conn.commit()
    cursor.close()
    conn.close()

    return jsonify({"message": "User Registered Successfully"}), 201


@register_bp.route('/register/seller', methods=['POST'])
def register_seller():
    data = request.json

    name = data.get("seller_name")
    email = data.get("seller_email")
    mobile = data.get("seller_mobile")
    shop_address = data.get("shop_address")
    shop_name = data.get("shop_name")
    password = data.get("seller_pass")

    hashed_pass = bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt())

    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)

    cursor.execute("SELECT * FROM seller WHERE seller_email = %s",(email,))
    existing_seller = cursor.fetchone()

    if existing_seller:
        return jsonify({"message": "Email already registered!"}), 400
    
    cursor.execute("""
        INSERT INTO seller(seller_name, seller_email, seller_mobile, shop_address, shop_name, seller_pass) VALUES (%s, %s, %s, %s, %s, %s)
    """, (name, email, mobile, shop_address, shop_name, hashed_pass))

    conn.commit()
    cursor.close()
    conn.close()

    return jsonify({"message": "Seller Registered Successfully"}), 201


@register_bp.route('/api/check-account',methods=['POST'])
def check_account():

    data = request.json
    email = data.get("email")
    mobile = data.get("mobile")

    if not email and not mobile:
        return jsonify({"error": "Email or Mobile required"}), 400
    
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)

    admin = user = seller = None

    if email:
        cursor.execute("SELECT admin_id FROM admin WHERE admin_email=%s",(email,))
        admin = cursor.fetchone()

        cursor.execute("SELECT user_id FROM user WHERE user_email=%s", (email,))
        user = cursor.fetchone()

        cursor.execute("SELECT seller_id FROM seller WHERE seller_email=%s", (email,))
        seller = cursor.fetchone()


    if mobile:
        cursor.execute("SELECT admin_id FROM admin WHERE admin_mobile=%s", (mobile,))
        admin = cursor.fetchone()

        cursor.execute("SELECT user_id FROM user WHERE user_mobile=%s", (mobile,))
        user = cursor.fetchone()

        cursor.execute("SELECT seller_id FROM seller WHERE seller_mobile=%s", (mobile,))
        seller = cursor.fetchone()

    cursor.close()
    conn.close()


    if admin:
        return jsonify({"exists": True, "role": "admin"}), 200
    elif user:
        return jsonify({"exists": True, "role": "user"}), 200
    elif seller:
        return jsonify({"exists": True, "role": "seller"}), 200
    else:
        return jsonify({"exists": False}), 404
