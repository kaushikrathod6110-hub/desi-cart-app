from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity, get_jwt
from db import get_db_connection
import random
import smtplib
import ssl
import secrets
from email.message import EmailMessage
from datetime import datetime, timedelta
import os
from dotenv import load_dotenv
import bcrypt

load_dotenv()

password_bp = Blueprint('password_bp', __name__)

@password_bp.route('/api/send-otp', methods=['POST'])
def send_otp():

    data = request.json
    email = data.get("email")

    if not email:
        return jsonify({"error": "Email required"}), 400
    
    otp = str(random.randint(100000,999999))

    conn = get_db_connection()
    cursor = conn.cursor()

    cursor.execute(
        "INSERT INTO password_resets (email,otp) VALUES (%s,%s)",(email,otp)
    )
    conn.commit()
    cursor.close()
    conn.close()

    sender_email = os.getenv("EMAIL_USER")
    sender_password = os.getenv("EMAIL_PASS")

    msg = EmailMessage()
    msg.set_content(f"Your OTP for password reset is: {otp}")
    msg["Subject"] = "Password Reset OTP"
    msg["From"] = sender_email
    msg["TO"] = email

    context = ssl.create_default_context()

    with smtplib.SMTP_SSL("smtp.gmail.com", 465, context=context) as server:
        server.login(sender_email, sender_password)
        server.send_message(msg)

    return jsonify({"message": "OTP sent successfully"})


@password_bp.route('/api/verify-otp', methods=['POST'])
def verify_otp():

    data = request.json
    email = data.get("email")
    otp = data.get("otp")

    conn = get_db_connection()
    cursor = conn.cursor(dictionary = True)

    cursor.execute(
       "SELECT * FROM password_resets WHERE email=%s AND otp=%s AND is_verified=FALSE ORDER BY created_at DESC LIMIT 1",
        (email, otp)
    )
    record = cursor.fetchone()

    if not record:
        cursor.close()
        conn.close()
        return jsonify({"error": "Invalid OTP"}), 400
    
    if datetime.now() - record["created_at"] > timedelta(minutes=5):
        return jsonify({"error": "OTP expired"}), 400
    
    reset_token = secrets.token_urlsafe(32)

    cursor.execute(
        "UPDATE password_resets SET is_verified=TRUE, reset_token=%s WHERE id=%s",
        (reset_token, record["id"])
    )
    conn.commit()
    cursor.close()
    conn.close()

    return jsonify({"reset_token": reset_token}), 200

@password_bp.route('/api/reset-password', methods=["POST"])
def reset_password():

    data = request.json
    reset_token = data.get("reset_token")
    new_password = data.get("new_password")

    if not reset_token or not new_password:
        return jsonify({"error": "Token and new password required"}), 400

    if len(new_password) < 6:
        return jsonify({"error":"Passowrd must be at least 6 characters"}), 400
    
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)

    cursor.execute(
        "SELECT * FROM password_resets WHERE reset_token=%s AND is_verified=TRUE ORDER BY created_at DESC LIMIT 1",
        (reset_token,)
    )
    record = cursor.fetchone()

    if not record:
        cursor.close()
        conn.close()
        return jsonify({"error": "Invalid or expired token"}), 400
    
    email = record["email"]

    hashed_password = bcrypt.hashpw(new_password.encode('utf-8'),bcrypt.gensalt()).decode('utf-8')

    cursor.execute("UPDATE admin SET admin_pass=%s WHERE admin_email=%s",(hashed_password, email))

    cursor.execute("UPDATE user SET user_pass=%s WHERE user_email=%s",(hashed_password, email))

    cursor.execute("UPDATE seller SET seller_pass=%s WHERE seller_email=%s",(hashed_password, email))

    cursor.execute(
        "DELETE FROM password_resets WHERE id=%s",(record["id"],))

    conn.commit()
    cursor.close()
    conn.close()

    return jsonify({"message": "Password reset successful"})


@password_bp.route('/api/change-password', methods=['POST'])
@jwt_required()
def change_password():
    data = request.get_json() or {}

    current_password = data.get("current_password")
    new_password = data.get("new_password")

    if not current_password or not new_password:
        return jsonify({"error": "Current and new password required"}), 400
    
    if len(new_password) < 6:
        return jsonify({"error": "Password must be at least 6 characters"}), 400
    
    user_id = get_jwt_identity()
    claims = get_jwt()
    role = claims.get("role")

    role_map = {
        "admin": {"table": "admin", "id_col": "admin_id", "pass_col": "admin_pass"},
        "user": {"table": "user", "id_col": "user_id", "pass_col": "user_pass"},
        "seller": {"table": "seller", "id_col": "seller_id", "pass_col": "seller_pass"},        
    }

    if role not in role_map:
        return jsonify({"error": "Invalid role"}), 400
    
    table = role_map[role]["table"]
    id_col = role_map[role]["id_col"]
    pass_col = role_map[role]["pass_col"]

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)

    cur.execute(f"SELECT {pass_col} FROM {table} WHERE {id_col}=%s",(user_id,))
    row = cur.fetchone()

    if not row:
        cur.close()
        conn.close()
        return jsonify({"error": "User not found"}), 404
    
    stored_hash = row.get(pass_col) or ""

    try:
        ok = bcrypt.checkpw(current_password.encode("utf-8"), stored_hash.encode("utf-8"))
    except Exception:
        ok = False

    if not ok:
        cur.close()
        conn.close()
        return jsonify({"error": "Current password is incorrect"}), 400
    
    new_hash = bcrypt.hashpw(new_password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")

    cur.execute(
        f"UPDATE {table} SET {pass_col}=%s WHERE {id_col}=%s",
        (new_hash, user_id)
    )
    conn.commit()
    cur.close()
    conn.close()

    return jsonify({"message": "Password updated successfully"}), 200