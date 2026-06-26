from flask import Blueprint, request, jsonify
from flask_jwt_extended import (
    create_access_token,
    jwt_required,
    get_jwt_identity,
    create_refresh_token,
    get_jwt,
)
from db import get_db_connection
import bcrypt
import re
from datetime import datetime, timedelta
import math

auth_bp = Blueprint('auth', __name__)


def _find_account_by_email(cursor, email: str):
    cursor.execute("""
        SELECT user_id AS account_id, user_email AS email, status
        FROM user
        WHERE user_email=%s
        LIMIT 1
    """, (email,))
    user = cursor.fetchone()
    if user:
        return {
            "account_type": "user",
            "account_id": user["account_id"],
            "email": user["email"],
            "status": str(user.get("status", "active")).lower()
        }

    cursor.execute("""
        SELECT seller_id AS account_id, seller_email AS email, status
        FROM seller
        WHERE seller_email=%s
        LIMIT 1
    """, (email,))
    seller = cursor.fetchone()
    if seller:
        return {
            "account_type": "seller",
            "account_id": seller["account_id"],
            "email": seller["email"],
            "status": str(seller.get("status", "active")).lower()
        }

    cursor.execute("""
        SELECT delivery_staff_id AS account_id, d_s_email AS email, d_s_status AS status
        FROM delivery_staff
        WHERE d_s_email=%s
        LIMIT 1
    """, (email,))
    staff = cursor.fetchone()
    if staff:
        return {
            "account_type": "delivery_staff",
            "account_id": staff["account_id"],
            "email": staff["email"],
            "status": str(staff.get("status", "active")).lower()
        }

    return None


def _get_latest_block_request(conn, account_type: str, account_id: int):
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("""
            SELECT request_id, request_status, requested_at, cooldown_until, accepted_at, deleted_at, message
            FROM block_requests
            WHERE account_type=%s AND account_id=%s
            ORDER BY request_id DESC
            LIMIT 1
        """, (account_type, account_id))
        return cursor.fetchone()
    finally:
        cursor.close()


def _inactive_login_response(conn, account_type: str, account_id: int, email: str, default_message: str):
    latest = _get_latest_block_request(conn, account_type, account_id)
    now = datetime.now()

    if latest:
        status = str(latest.get("request_status", "")).lower()

        if status == "pending":
            cooldown_until = latest.get("cooldown_until")
            remaining_days = 0
            if cooldown_until and cooldown_until > now:
                remaining_days = max(1, math.ceil((cooldown_until - now).total_seconds() / 86400))

            conn.close()
            return jsonify({
                "message": "Your account is inactive. Your request has already been sent to admin.",
                "inactive_account": True,
                "account_type": account_type,
                "email": email,
                "can_contact_admin": False,
                "request_status": "pending",
                "cooldown_remaining_days": remaining_days,
                "next_request_message": f"You can send another request after {remaining_days} day(s)." if remaining_days > 0 else ""
            }), 403

        if status == "accepted":
            conn.close()
            return jsonify({
                "message": "Your account has been unblocked. You can now log in.",
                "inactive_account": True,
                "account_type": account_type,
                "email": email,
                "can_contact_admin": False,
                "request_status": "accepted",
                "unblocked_message": "Your account has been unblocked. You can now log in."
            }), 403

        if status == "deleted":
            cooldown_until = latest.get("cooldown_until")
            if cooldown_until and cooldown_until > now:
                remaining_days = max(1, math.ceil((cooldown_until - now).total_seconds() / 86400))
                conn.close()
                return jsonify({
                    "message": default_message,
                    "inactive_account": True,
                    "account_type": account_type,
                    "email": email,
                    "can_contact_admin": False,
                    "request_status": "deleted",
                    "cooldown_remaining_days": remaining_days,
                    "next_request_message": f"You can send another request after {remaining_days} day(s)."
                }), 403

    conn.close()
    return jsonify({
        "message": default_message,
        "inactive_account": True,
        "account_type": account_type,
        "email": email,
        "can_contact_admin": True,
        "request_status": None
    }), 403


def _hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')


def _email_exists(cursor, email: str) -> bool:
    cursor.execute("SELECT user_id FROM user WHERE user_email=%s LIMIT 1", (email,))
    if cursor.fetchone():
        return True

    cursor.execute("SELECT seller_id FROM seller WHERE seller_email=%s LIMIT 1", (email,))
    if cursor.fetchone():
        return True

    cursor.execute("SELECT delivery_staff_id FROM delivery_staff WHERE d_s_email=%s LIMIT 1", (email,))
    if cursor.fetchone():
        return True

    cursor.execute("SELECT admin_id FROM admin WHERE admin_email=%s LIMIT 1", (email,))
    if cursor.fetchone():
        return True

    return False


def _mobile_exists(cursor, mobile: str) -> bool:
    cursor.execute("SELECT user_id FROM user WHERE user_mobile=%s LIMIT 1", (mobile,))
    if cursor.fetchone():
        return True

    cursor.execute("SELECT seller_id FROM seller WHERE seller_mobile=%s LIMIT 1", (mobile,))
    if cursor.fetchone():
        return True

    cursor.execute("SELECT delivery_staff_id FROM delivery_staff WHERE d_s_mobile=%s LIMIT 1", (mobile,))
    if cursor.fetchone():
        return True

    return False


@auth_bp.route('/api/login', methods=['POST'])
def login():
    data = request.get_json(silent=True) or {}
    email = str(data.get("email", "")).strip()
    password = str(data.get("password", "")).strip()

    if not email or not password:
        return jsonify({"message": "Email & password required"}), 400

    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)

    cursor.execute(
        "SELECT admin_id, admin_email, admin_pass FROM admin WHERE admin_email=%s LIMIT 1",
        (email,)
    )
    admin = cursor.fetchone()

    if admin and bcrypt.checkpw(password.encode('utf-8'), admin["admin_pass"].encode('utf-8')):
        role = "admin"
        user_id = admin["admin_id"]

    else:
        cursor.execute(
            "SELECT user_id, user_email, user_pass, status FROM user WHERE user_email=%s LIMIT 1",
            (email,)
        )
        user = cursor.fetchone()

        if user and bcrypt.checkpw(password.encode('utf-8'), user["user_pass"].encode('utf-8')):
            if str(user.get("status", "active")).lower() == "inactive":
                cursor.close()
                return _inactive_login_response(
                    conn,
                    "user",
                    user["user_id"],
                    user["user_email"],
                    "Your account is inactive. Contact admin."
                )
            role = "user"
            user_id = user["user_id"]

        else:
            cursor.execute(
                "SELECT seller_id, seller_email, seller_pass, status FROM seller WHERE seller_email=%s LIMIT 1",
                (email,)
            )
            seller = cursor.fetchone()

            if seller and bcrypt.checkpw(password.encode('utf-8'), seller["seller_pass"].encode('utf-8')):
                if str(seller.get("status", "active")).lower() == "inactive":
                    cursor.close()
                    return _inactive_login_response(
                        conn,
                        "seller",
                        seller["seller_id"],
                        seller["seller_email"],
                        "Your seller account is inactive. Contact admin."
                    )
                role = "seller"
                user_id = seller["seller_id"]

            else:
                cursor.execute(
                    """
                    SELECT delivery_staff_id, d_s_email, d_s_pass, d_s_status
                    FROM delivery_staff
                    WHERE d_s_email=%s
                    LIMIT 1
                    """,
                    (email,)
                )
                delivery_staff = cursor.fetchone()

                if delivery_staff and bcrypt.checkpw(password.encode('utf-8'), delivery_staff["d_s_pass"].encode('utf-8')):
                    if str(delivery_staff.get("d_s_status", "active")).lower() == "inactive":
                        cursor.close()
                        return _inactive_login_response(
                            conn,
                            "delivery_staff",
                            delivery_staff["delivery_staff_id"],
                            delivery_staff["d_s_email"],
                            "Your delivery staff account is inactive. Contact admin."
                        )
                    role = "delivery_staff"
                    user_id = delivery_staff["delivery_staff_id"]
                else:
                    cursor.close()
                    conn.close()
                    return jsonify({"message": "Invalid credentials"}), 401

    cursor.close()
    conn.close()

    access_token = create_access_token(
        identity=str(user_id),
        additional_claims={"role": role},
        expires_delta=timedelta(hours=12)
    )
    refresh_token = create_refresh_token(
        identity=str(user_id),
        additional_claims={"role": role},
        expires_delta=timedelta(days=30)
    )

    return jsonify({
        "role": role,
        "access_token": access_token,
        "refresh_token": refresh_token
    }), 200


@auth_bp.route('/api/refresh', methods=['POST'])
@jwt_required(refresh=True)
def refresh():
    user_id = get_jwt_identity()
    claims = get_jwt()

    new_access_token = create_access_token(
        identity=user_id,
        additional_claims={"role": claims.get("role")},
        expires_delta=timedelta(hours=12)
    )

    return jsonify({"access_token": new_access_token}), 200


@auth_bp.route('/api/block-request/check', methods=['POST'])
def check_block_request_status():
    data = request.get_json(silent=True) or {}
    email = str(data.get("email", "")).strip().lower()

    if not email:
        return jsonify({"message": "Email is required"}), 400

    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)

    account = _find_account_by_email(cursor, email)
    if not account:
        cursor.close()
        conn.close()
        return jsonify({
            "exists": False,
            "message": "Account not found"
        }), 404

    latest = _get_latest_block_request(conn, account["account_type"], account["account_id"])
    now = datetime.now()

    response = {
        "exists": True,
        "account_type": account["account_type"],
        "account_status": account["status"],
        "can_contact_admin": account["status"] == "inactive",
        "request_status": None,
        "cooldown_remaining_days": 0,
        "message": ""
    }

    if account["status"] != "inactive":
        if latest and str(latest.get("request_status", "")).lower() == "accepted":
            response["message"] = "Your account has been unblocked. You can now log in."
        else:
            response["message"] = "Your account is active."
        cursor.close()
        conn.close()
        return jsonify(response), 200

    if latest:
        req_status = str(latest.get("request_status", "")).lower()
        response["request_status"] = req_status

        if req_status == "pending":
            cooldown_until = latest.get("cooldown_until")
            if cooldown_until and cooldown_until > now:
                response["cooldown_remaining_days"] = max(
                    1, math.ceil((cooldown_until - now).total_seconds() / 86400)
                )
            response["can_contact_admin"] = False
            response["message"] = "Your request is already pending with admin."

        elif req_status == "deleted":
            cooldown_until = latest.get("cooldown_until")
            if cooldown_until and cooldown_until > now:
                response["cooldown_remaining_days"] = max(
                    1, math.ceil((cooldown_until - now).total_seconds() / 86400)
                )
                response["can_contact_admin"] = False
                response["message"] = f"You can send another request after {response['cooldown_remaining_days']} day(s)."
            else:
                response["can_contact_admin"] = True
                response["message"] = "You can contact admin now."

        elif req_status == "accepted":
            response["can_contact_admin"] = False
            response["message"] = "Your account has been unblocked. You can now log in."

    cursor.close()
    conn.close()
    return jsonify(response), 200


@auth_bp.route('/api/block-request/send', methods=['POST'])
def send_block_request():
    data = request.get_json(silent=True) or {}
    email = str(data.get("email", "")).strip().lower()
    message = str(data.get("message", "")).strip()

    if not email or not message:
        return jsonify({"message": "Email and message are required"}), 400

    if len(message) < 5:
        return jsonify({"message": "Please enter a valid message."}), 400

    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)

    account = _find_account_by_email(cursor, email)
    if not account:
        cursor.close()
        conn.close()
        return jsonify({"message": "Account not found"}), 404

    if account["status"] != "inactive":
        cursor.close()
        conn.close()
        return jsonify({"message": "This account is already active. Please log in."}), 400

    latest = _get_latest_block_request(conn, account["account_type"], account["account_id"])
    now = datetime.now()

    if latest:
        req_status = str(latest.get("request_status", "")).lower()
        cooldown_until = latest.get("cooldown_until")

        if req_status == "pending":
            remaining_days = 0
            if cooldown_until and cooldown_until > now:
                remaining_days = max(1, math.ceil((cooldown_until - now).total_seconds() / 86400))
            cursor.close()
            conn.close()
            return jsonify({
                "message": "Your request is already pending with admin.",
                "can_send": False,
                "cooldown_remaining_days": remaining_days
            }), 409

        if cooldown_until and cooldown_until > now:
            remaining_days = max(1, math.ceil((cooldown_until - now).total_seconds() / 86400))
            cursor.close()
            conn.close()
            return jsonify({
                "message": f"You can send another request after {remaining_days} day(s).",
                "can_send": False,
                "cooldown_remaining_days": remaining_days
            }), 429

    cooldown_until = now + timedelta(days=7)

    insert_cursor = conn.cursor()
    insert_cursor.execute("""
        INSERT INTO block_requests
        (account_type, account_id, email, message, request_status, requested_at, cooldown_until)
        VALUES (%s, %s, %s, %s, %s, %s, %s)
    """, (
        account["account_type"],
        account["account_id"],
        email,
        message,
        "pending",
        now,
        cooldown_until
    ))
    conn.commit()

    insert_cursor.close()
    cursor.close()
    conn.close()

    return jsonify({
        "message": "Your request has been sent to admin successfully.",
        "can_send": False,
        "request_status": "pending",
        "cooldown_remaining_days": 7
    }), 201


@auth_bp.route('/register/user', methods=['POST'])
def register_user():
    data = request.get_json(silent=True) or {}

    user_name = str(data.get("user_name", "")).strip()
    user_email = str(data.get("user_email", "")).strip().lower()
    user_mobile = str(data.get("user_mobile", "")).strip()
    user_pass = str(data.get("user_pass", "")).strip()

    if not user_name or not user_email or not user_mobile or not user_pass:
        return jsonify({"message": "All user fields are required"}), 400

    if len(user_mobile) != 10 or not user_mobile.isdigit():
        return jsonify({"message": "Enter valid 10 digit mobile number"}), 400

    if "@" not in user_email:
        return jsonify({"message": "Enter valid email"}), 400

    if len(user_pass) < 6:
        return jsonify({"message": "Password must be at least 6 characters"}), 400

    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)

    if _email_exists(cursor, user_email):
        cursor.close()
        conn.close()
        return jsonify({"message": "Email already registered"}), 409

    if _mobile_exists(cursor, user_mobile):
        cursor.close()
        conn.close()
        return jsonify({"message": "Mobile number already registered"}), 409

    hashed_password = _hash_password(user_pass)

    cursor = conn.cursor()
    cursor.execute("""
        INSERT INTO user
        (user_name, user_email, user_mobile, user_pass, status, registration_at, updated_at)
        VALUES (%s, %s, %s, %s, %s, %s, %s)
    """, (
        user_name,
        user_email,
        user_mobile,
        hashed_password,
        "active",
        datetime.now(),
        datetime.now()
    ))
    conn.commit()

    cursor.close()
    conn.close()

    return jsonify({"message": "User registered successfully"}), 201


@auth_bp.route('/register/seller', methods=['POST'])
def register_seller():
    data = request.get_json(silent=True) or {}

    seller_name = str(data.get("seller_name", "")).strip()
    seller_email = str(data.get("seller_email", "")).strip().lower()
    seller_mobile = str(data.get("seller_mobile", "")).strip()
    shop_name = str(data.get("shop_name", "")).strip()
    shop_address = str(data.get("shop_address", "")).strip()
    seller_pass = str(data.get("seller_pass", "")).strip()

    if not seller_name or not seller_email or not seller_mobile or not shop_name or not shop_address or not seller_pass:
        return jsonify({"message": "All seller fields are required"}), 400

    if len(seller_mobile) != 10 or not seller_mobile.isdigit():
        return jsonify({"message": "Enter valid 10 digit mobile number"}), 400

    if "@" not in seller_email:
        return jsonify({"message": "Enter valid email"}), 400

    if len(seller_pass) < 6:
        return jsonify({"message": "Password must be at least 6 characters"}), 400

    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)

    if _email_exists(cursor, seller_email):
        cursor.close()
        conn.close()
        return jsonify({"message": "Email already registered"}), 409

    if _mobile_exists(cursor, seller_mobile):
        cursor.close()
        conn.close()
        return jsonify({"message": "Mobile number already registered"}), 409

    hashed_password = _hash_password(seller_pass)

    cursor = conn.cursor()
    cursor.execute("""
        INSERT INTO seller
        (seller_name, seller_email, seller_mobile, shop_name, shop_address, seller_pass, status, registration_date)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
    """, (
        seller_name,
        seller_email,
        seller_mobile,
        shop_name,
        shop_address,
        hashed_password,
        "active",
        datetime.now()
    ))
    conn.commit()

    cursor.close()
    conn.close()

    return jsonify({"message": "Seller registered successfully"}), 201


@auth_bp.route('/register/delivery-staff', methods=['POST'])
def register_delivery_staff():
    data = request.get_json(silent=True) or {}

    delivery_staff_name = str(data.get("delivery_staff_name", "")).strip()
    d_s_email = str(data.get("d_s_email", "")).strip().lower()
    d_s_mobile = str(data.get("d_s_mobile", "")).strip()
    d_s_pass = str(data.get("d_s_pass", "")).strip()
    d_s_address = str(data.get("d_s_address", "")).strip()
    d_s_pincode = str(data.get("d_s_pincode", "")).strip()
    vehicle_type = str(data.get("vehicle_type", "")).strip()
    staff_licence_no = str(data.get("staff_licence_no", "")).strip()
    aadhar_card_no = str(data.get("aadhar_card_no", "")).strip()

    allowed_vehicle_types = {"Bike", "Scooter", "Cycle", "None"}
    licence_required = vehicle_type not in {"Cycle", "None"}

    if not delivery_staff_name or not d_s_email or not d_s_mobile or not d_s_pass or not d_s_address or not d_s_pincode or not vehicle_type or not aadhar_card_no:
        return jsonify({"message": "All delivery staff fields are required"}), 400

    if licence_required and not staff_licence_no:
        return jsonify({"message": "Licence number is required for selected vehicle type"}), 400

    if len(d_s_mobile) != 10 or not d_s_mobile.isdigit():
        return jsonify({"message": "Enter valid 10 digit mobile number"}), 400

    if len(d_s_pincode) != 6 or not d_s_pincode.isdigit():
        return jsonify({"message": "Enter valid 6 digit pincode"}), 400

    if not re.fullmatch(r'^[0-9]{12}$', aadhar_card_no):
        return jsonify({"message": "Enter valid 12 digit Aadhar card number"}), 400

    if "@" not in d_s_email:
        return jsonify({"message": "Enter valid email"}), 400

    if len(d_s_pass) < 6:
        return jsonify({"message": "Password must be at least 6 characters"}), 400

    if vehicle_type not in allowed_vehicle_types:
        return jsonify({"message": "Invalid vehicle type"}), 400

    if not licence_required:
        staff_licence_no = None

    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)

    if _email_exists(cursor, d_s_email):
        cursor.close()
        conn.close()
        return jsonify({"message": "Email already registered"}), 409

    if _mobile_exists(cursor, d_s_mobile):
        cursor.close()
        conn.close()
        return jsonify({"message": "Mobile number already registered"}), 409

    if licence_required:
        cursor.execute(
            "SELECT delivery_staff_id FROM delivery_staff WHERE staff_licence_no=%s LIMIT 1",
            (staff_licence_no,)
        )
        if cursor.fetchone():
            cursor.close()
            conn.close()
            return jsonify({"message": "Licence number already registered"}), 409

    hashed_password = _hash_password(d_s_pass)

    cursor = conn.cursor()
    cursor.execute("""
        INSERT INTO delivery_staff
        (
            delivery_staff_name, d_s_mobile, d_s_email, d_s_pass, d_s_address, d_s_pincode, vehicle_type, staff_licence_no, aadhar_card_no, d_s_status, joining_date
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
    """, (
        delivery_staff_name,
        d_s_mobile,
        d_s_email,
        hashed_password,
        d_s_address,
        d_s_pincode,
        vehicle_type,
        staff_licence_no,
        aadhar_card_no,
        "Active",
        datetime.now().date()
    ))
    conn.commit()

    cursor.close()
    conn.close()

    return jsonify({"message": "Delivery staff registered successfully"}), 201
