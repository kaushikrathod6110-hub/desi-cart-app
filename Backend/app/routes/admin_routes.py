from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required, get_jwt, get_jwt_identity
from db import get_db_connection
from datetime import datetime
from werkzeug.utils import secure_filename
import os
import uuid
import json
import platform

admin_bp = Blueprint('admin_bp', __name__)

ALLOWED_IMAGE_EXTENSIONS = {'png', 'jpg', 'jpeg', 'webp'}
PROFILE_UPLOAD_FOLDER = os.path.join(os.getcwd(), 'uploads', 'profile')
os.makedirs(PROFILE_UPLOAD_FOLDER, exist_ok=True)

SETTINGS_FILE_PATH = os.path.join(os.getcwd(), 'admin_settings.json')

DEFAULT_ADMIN_SETTINGS = {
    "app_configuration": {
        "app_name": "Desi Cart",
        "support_email": "support@desicart.com",
        "support_mobile": "",
        "currency": "INR",
        "currency_symbol": "₹",
        "low_stock_threshold": 5,
        "new_order_notifications": True,
        "delivery_alert_notifications": True,
        "maintenance_mode": False
    },
    "security_settings": {
        "allow_multiple_admin_logins": True,
        "force_password_change_days": 90,
        "session_timeout_minutes": 15,
        "max_login_attempts": 5,
        "profile_image_required": False
    }
}


def _deep_copy_settings(data):
    return json.loads(json.dumps(data))


def _load_admin_settings():
    settings = _deep_copy_settings(DEFAULT_ADMIN_SETTINGS)

    if not os.path.exists(SETTINGS_FILE_PATH):
        _save_admin_settings(settings)
        return settings

    try:
        with open(SETTINGS_FILE_PATH, 'r', encoding='utf-8') as file:
            saved_settings = json.load(file)

        if isinstance(saved_settings, dict):
            if isinstance(saved_settings.get("app_configuration"), dict):
                settings["app_configuration"].update(saved_settings["app_configuration"])
            if isinstance(saved_settings.get("security_settings"), dict):
                settings["security_settings"].update(saved_settings["security_settings"])
    except Exception:
        pass

    return settings


def _save_admin_settings(settings):
    with open(SETTINGS_FILE_PATH, 'w', encoding='utf-8') as file:
        json.dump(settings, file, indent=2, ensure_ascii=False)

def _is_admin():
    claims = get_jwt()
    return str(claims.get("role", "")).lower() == "admin"


def _allowed_image(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_IMAGE_EXTENSIONS


def _build_file_url(filename):
    if not filename:
        return None
    base = request.host_url.rstrip('/')
    return f"{base}/uploads/profile/{filename}"


def _normalize_account_status(account_type, status_value):
    status = str(status_value or "").strip().lower()
    if account_type == "delivery_staff":
        return "Active" if status == "active" else "Inactive"
    return "active" if status == "active" else "inactive"


@admin_bp.route('/api/admin-profile', methods=['GET'])
@jwt_required()
def get_admin_profile():
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    admin_id = get_jwt_identity()

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)
    cur.execute(
        """
        SELECT admin_id, admin_name, admin_email, admin_mobile, profile_image
        FROM admin
        WHERE admin_id = %s
        LIMIT 1
        """,
        (admin_id,),
    )
    admin = cur.fetchone()
    cur.close()
    conn.close()

    if not admin:
        return jsonify({"message": "Admin not found"}), 404

    admin["admin_mobile"] = "" if admin.get("admin_mobile") is None else str(admin["admin_mobile"])
    admin["profile_image"] = admin.get("profile_image") or ""
    admin["profile_image_url"] = _build_file_url(admin["profile_image"])

    return jsonify(admin), 200


@admin_bp.route('/api/admin-profile', methods=['PUT'])
@jwt_required()
def update_admin_profile():
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    admin_id = get_jwt_identity()

    is_multipart = request.content_type and 'multipart/form-data' in request.content_type.lower()

    if is_multipart:
        name = (request.form.get('name') or '').strip()
        email = (request.form.get('email') or '').strip()
        mobile = (request.form.get('mobile') or '').strip()
        profile_file = request.files.get('profile_image')
        remove_image = (request.form.get('remove_image') or '0').strip()
    else:
        data = request.get_json(silent=True) or {}
        name = str(data.get('name', '')).strip()
        email = str(data.get('email', '')).strip()
        mobile = str(data.get('mobile', '')).strip()
        profile_file = None
        remove_image = str(data.get('remove_image', '0')).strip()

    if not name or not email or not mobile:
        return jsonify({"message": "Name, email and mobile are required."}), 400

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)
    cur.execute(
        "SELECT admin_id, profile_image FROM admin WHERE admin_id = %s LIMIT 1",
        (admin_id,),
    )
    existing_admin = cur.fetchone()

    if not existing_admin:
        cur.close()
        conn.close()
        return jsonify({"message": "Admin not found"}), 404

    image_filename = existing_admin.get('profile_image') or None

    if remove_image == '1':
        old_image = existing_admin.get('profile_image')
        if old_image:
            old_path = os.path.join(PROFILE_UPLOAD_FOLDER, old_image)
            if os.path.exists(old_path):
                try:
                    os.remove(old_path)
                except OSError:
                    pass
        image_filename = None

    if profile_file and profile_file.filename:
        if not _allowed_image(profile_file.filename):
            cur.close()
            conn.close()
            return jsonify({"message": "Only png, jpg, jpeg and webp images are allowed."}), 400

        original_name = secure_filename(profile_file.filename)
        ext = original_name.rsplit('.', 1)[1].lower()
        image_filename = f"admin_{admin_id}_{uuid.uuid4().hex[:10]}.{ext}"
        save_path = os.path.join(PROFILE_UPLOAD_FOLDER, image_filename)
        profile_file.save(save_path)

        old_image = existing_admin.get('profile_image')
        if old_image and old_image != image_filename:
            old_path = os.path.join(PROFILE_UPLOAD_FOLDER, old_image)
            if os.path.exists(old_path):
                try:
                    os.remove(old_path)
                except OSError:
                    pass

    cur = conn.cursor()
    cur.execute(
        """
        UPDATE admin
        SET admin_name = %s,
            admin_email = %s,
            admin_mobile = %s,
            profile_image = %s
        WHERE admin_id = %s
        """,
        (name, email, mobile, image_filename, admin_id),
    )
    conn.commit()
    cur.close()
    conn.close()

    return jsonify({
        "message": "Profile updated successfully",
        "profile_image": image_filename or "",
        "profile_image_url": _build_file_url(image_filename),
    }), 200


@admin_bp.route('/api/admin-data', methods=['GET'])
@jwt_required()
def admin_data():
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    return jsonify({"message": "Welcome Admin"}), 200


@admin_bp.route('/api/admin/sellers', methods=['GET'])
@jwt_required()
def get_all_sellers():
    if not _is_admin():
        return jsonify({"msg": "Access denied. Admin only."}), 403

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)

    cur.execute("""
        SELECT
            seller_id, seller_name, seller_email, seller_mobile,
            shop_name, shop_address, status, registration_date
        FROM seller
        ORDER BY seller_id DESC
    """)
    sellers = cur.fetchall()

    cur.close()
    conn.close()

    for s in sellers:
        s["seller_mobile"] = "" if s.get("seller_mobile") is None else str(s["seller_mobile"])
        if not s.get("status"):
            s["status"] = "active"

    return jsonify(sellers), 200


@admin_bp.route('/api/admin/sellers/stats', methods=['GET'])
@jwt_required()
def sellers_stats():
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)

    cur.execute("""
        SELECT
            COUNT(*) AS total,
            SUM((status = 'active') AND (registration_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY))) AS active_new,
            SUM((status = 'active') AND (registration_date IS NULL OR registration_date < DATE_SUB(CURDATE(), INTERVAL 30 DAY))) AS active_old,
            SUM((status = 'inactive') AND (registration_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY))) AS inactive_new,
            SUM((status = 'inactive') AND (registration_date IS NULL OR registration_date < DATE_SUB(CURDATE(), INTERVAL 30 DAY))) AS inactive_old
        FROM seller
    """)
    stats = cur.fetchone()

    cur.close()
    conn.close()

    if not stats:
        stats = {"total": 0, "active_new": 0, "active_old": 0, "inactive_new": 0, "inactive_old": 0}

    for k in ["total", "active_new", "active_old", "inactive_new", "inactive_old"]:
        stats[k] = int(stats.get(k) or 0)

    return jsonify(stats), 200


@admin_bp.route('/api/admin/sellers/<int:seller_id>/status', methods=['PUT'])
@jwt_required()
def update_seller_status(seller_id):
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    data = request.get_json(silent=True) or {}
    status = str(data.get("status", "")).strip().lower()

    if status not in ["active", "inactive"]:
        return jsonify({"error": "Invalid status. Use 'active' or 'inactive'."}), 400

    conn = get_db_connection()
    cur = conn.cursor()

    cur.execute("UPDATE seller SET status=%s WHERE seller_id=%s", (status, seller_id))
    conn.commit()

    affected = cur.rowcount
    cur.close()
    conn.close()

    if affected == 0:
        return jsonify({"error": "Seller not found"}), 404

    return jsonify({"message": "Status updated", "seller_id": seller_id, "status": status}), 200


@admin_bp.route('/api/admin/users', methods=['GET'])
@jwt_required()
def get_all_users():
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)

    cur.execute("""
        SELECT
            user_id, user_name, user_email, user_mobile,
            user_address, pincode, status, registration_at, updated_at
        FROM user
        ORDER BY user_id DESC
    """)
    users = cur.fetchall()

    cur.close()
    conn.close()

    for u in users:
        u["user_mobile"] = "" if u.get("user_mobile") is None else str(u["user_mobile"])
        if not u.get("status"):
            u["status"] = "active"

    return jsonify(users), 200


@admin_bp.route('/api/admin/users/stats', methods=['GET'])
@jwt_required()
def users_stats():
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)

    cur.execute("""
        SELECT
            COUNT(*) AS total,
            SUM((status = 'active') AND (registration_at >= DATE_SUB(CURDATE(), INTERVAL 30 DAY))) AS active_new,
            SUM((status = 'active') AND (registration_at < DATE_SUB(CURDATE(), INTERVAL 30 DAY))) AS active_old,
            SUM((status = 'inactive') AND (registration_at >= DATE_SUB(CURDATE(), INTERVAL 30 DAY))) AS inactive_new,
            SUM((status = 'inactive') AND (registration_at < DATE_SUB(CURDATE(), INTERVAL 30 DAY))) AS inactive_old
        FROM user
    """)
    stats = cur.fetchone()

    cur.close()
    conn.close()

    if not stats:
        stats = {"total": 0, "active_new": 0, "active_old": 0, "inactive_new": 0, "inactive_old": 0}

    for k in ["total", "active_new", "active_old", "inactive_new", "inactive_old"]:
        stats[k] = int(stats.get(k) or 0)

    return jsonify(stats), 200


@admin_bp.route('/api/admin/users/<int:user_id>/status', methods=['PUT'])
@jwt_required()
def update_user_status(user_id):
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    data = request.get_json(silent=True) or {}
    status = str(data.get("status", "")).strip().lower()

    if status not in ("active", "inactive"):
        return jsonify({"error": "Invalid status. Use 'active' or 'inactive'."}), 400

    conn = get_db_connection()
    cur = conn.cursor()

    cur.execute("UPDATE user SET status=%s WHERE user_id=%s", (status, user_id))
    conn.commit()

    affected = cur.rowcount
    cur.close()
    conn.close()

    if affected == 0:
        return jsonify({"error": "User not found"}), 404

    return jsonify({"message": "Status updated", "user_id": user_id, "status": status}), 200


@admin_bp.route('/api/admin/delivery-staff', methods=['GET'])
@jwt_required()
def get_all_delivery_staff():
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)

    cur.execute("""
        SELECT
            delivery_staff_id,
            delivery_staff_name,
            d_s_mobile,
            d_s_email,
            d_s_address,
            d_s_pincode,
            vehicle_type,
            staff_licence_no,
            d_s_status,
            joining_date
        FROM delivery_staff
        ORDER BY delivery_staff_id DESC
    """)
    staff = cur.fetchall()

    cur.close()
    conn.close()

    for s in staff:
        s["d_s_mobile"] = "" if s.get("d_s_mobile") is None else str(s["d_s_mobile"])
        s["d_s_pincode"] = "" if s.get("d_s_pincode") is None else str(s["d_s_pincode"])
        if not s.get("d_s_status"):
            s["d_s_status"] = "Active"

    return jsonify(staff), 200


@admin_bp.route('/api/admin/delivery-staff/stats', methods=['GET'])
@jwt_required()
def delivery_staff_stats():
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)

    cur.execute("""
        SELECT
            COUNT(*) AS total,
            SUM((d_s_status = 'Active') AND (joining_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY))) AS active_new,
            SUM((d_s_status = 'Active') AND (joining_date < DATE_SUB(CURDATE(), INTERVAL 30 DAY))) AS active_old,
            SUM((d_s_status = 'Inactive') AND (joining_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY))) AS inactive_new,
            SUM((d_s_status = 'Inactive') AND (joining_date < DATE_SUB(CURDATE(), INTERVAL 30 DAY))) AS inactive_old
        FROM delivery_staff
    """)
    stats = cur.fetchone()

    cur.close()
    conn.close()

    if not stats:
        stats = {"total": 0, "active_new": 0, "active_old": 0, "inactive_new": 0, "inactive_old": 0}

    for k in ["total", "active_new", "active_old", "inactive_new", "inactive_old"]:
        stats[k] = int(stats.get(k) or 0)

    return jsonify(stats), 200


@admin_bp.route('/api/admin/delivery-staff/<int:staff_id>/status', methods=['PUT'])
@jwt_required()
def update_delivery_staff_status(staff_id):
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    data = request.get_json(silent=True) or {}
    status = str(data.get("status", "")).strip()

    if status not in ("Active", "Inactive"):
        return jsonify({"error": "Invalid status. Use 'Active' or 'Inactive'."}), 400

    conn = get_db_connection()
    cur = conn.cursor()

    cur.execute(
        "UPDATE delivery_staff SET d_s_status=%s WHERE delivery_staff_id=%s",
        (status, staff_id)
    )
    conn.commit()

    affected = cur.rowcount
    cur.close()
    conn.close()

    if affected == 0:
        return jsonify({"error": "Delivery staff not found"}), 404

    return jsonify({
        "message": "Status updated",
        "delivery_staff_id": staff_id,
        "d_s_status": status
    }), 200


@admin_bp.route('/api/admin/orders/stats', methods=['GET'])
@jwt_required()
def get_admin_orders_stats():
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)

    cur.execute("""
        SELECT
            COUNT(*) AS total,
            SUM(LOWER(COALESCE(order_status, '')) = 'pending') AS pending,
            SUM(LOWER(COALESCE(order_status, '')) = 'confirmed') AS confirmed,
            SUM(LOWER(COALESCE(order_status, '')) = 'packed') AS packed,
            SUM(
                LOWER(REPLACE(COALESCE(order_status, ''), ' ', '')) = 'outfordelivery'
            ) AS out_for_delivery,
            SUM(LOWER(COALESCE(order_status, '')) = 'delivered') AS delivered,
            SUM(LOWER(COALESCE(payment_status, '')) = 'paid') AS paid,
            SUM(LOWER(COALESCE(payment_status, '')) = 'pending') AS pay_pending,
            SUM(LOWER(COALESCE(payment_status, '')) = 'failed') AS failed
        FROM orders
    """)
    stats = cur.fetchone()

    cur.close()
    conn.close()

    if not stats:
        stats = {
            "total": 0,
            "pending": 0,
            "confirmed": 0,
            "packed": 0,
            "out_for_delivery": 0,
            "delivered": 0,
            "paid": 0,
            "pay_pending": 0,
            "failed": 0,
        }

    for key in [
        "total",
        "pending",
        "confirmed",
        "packed",
        "out_for_delivery",
        "delivered",
        "paid",
        "pay_pending",
        "failed",
    ]:
        stats[key] = int(stats.get(key) or 0)

    return jsonify(stats), 200


@admin_bp.route('/api/admin/orders/unassigned', methods=['GET'])
@jwt_required()
def get_unassigned_orders_for_delivery():
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)

    cur.execute("""
        SELECT
            o.order_id,
            o.user_id,
            o.seller_id,
            o.total_amount,
            o.order_status,
            o.payment_status,
            o.payment_method,
            o.order_date,
            o.delivery_status,
            u.user_name,
            s.seller_name
        FROM orders o
        LEFT JOIN user u ON u.user_id = o.user_id
        LEFT JOIN seller s ON s.seller_id = o.seller_id
        WHERE o.delivery_staff_id IS NULL
          AND o.delivery_status = 'Unassigned'
        ORDER BY o.order_date DESC
    """)
    rows = cur.fetchall()

    cur.close()
    conn.close()

    return jsonify(rows), 200


@admin_bp.route('/api/admin/orders/<int:order_id>/assign-delivery-staff', methods=['PUT'])
@jwt_required()
def assign_delivery_staff_to_order(order_id):
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    data = request.get_json(silent=True) or {}
    delivery_staff_id = data.get("delivery_staff_id")

    if not delivery_staff_id:
        return jsonify({"message": "delivery_staff_id required"}), 400

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)

    cur.execute("""
        SELECT delivery_staff_id, d_s_status
        FROM delivery_staff
        WHERE delivery_staff_id = %s
        LIMIT 1
    """, (delivery_staff_id,))
    staff = cur.fetchone()

    if not staff:
        cur.close()
        conn.close()
        return jsonify({"message": "Delivery staff not found"}), 404

    if str(staff.get("d_s_status", "")).lower() != "active":
        cur.close()
        conn.close()
        return jsonify({"message": "Delivery staff is inactive"}), 400

    cur.execute("""
        SELECT order_id, delivery_staff_id
        FROM orders
        WHERE order_id = %s
        LIMIT 1
    """, (order_id,))
    order = cur.fetchone()

    if not order:
        cur.close()
        conn.close()
        return jsonify({"message": "Order not found"}), 404

    if order.get("delivery_staff_id") is not None:
        cur.close()
        conn.close()
        return jsonify({"message": "Order already assigned"}), 400

    cur = conn.cursor()
    cur.execute("""
        UPDATE orders
        SET
            delivery_staff_id = %s,
            delivery_status = 'Assigned',
            assigned_at = %s
        WHERE order_id = %s
    """, (delivery_staff_id, datetime.now(), order_id))
    conn.commit()

    cur.close()
    conn.close()

    return jsonify({"message": "Delivery staff assigned successfully"}), 200

@admin_bp.route('/api/admin/settings/app-configuration', methods=['GET'])
@jwt_required()
def get_app_configuration():
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    settings = _load_admin_settings()
    return jsonify(settings["app_configuration"]), 200


@admin_bp.route('/api/admin/settings/app-configuration', methods=['PUT'])
@jwt_required()
def update_app_configuration():
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    data = request.get_json(silent=True) or {}
    settings = _load_admin_settings()
    app_config = settings["app_configuration"]

    app_name = str(data.get("app_name", app_config["app_name"])).strip()
    support_email = str(data.get("support_email", app_config["support_email"])).strip()
    support_mobile = str(data.get("support_mobile", app_config["support_mobile"])).strip()
    currency = str(data.get("currency", app_config["currency"])).strip()
    currency_symbol = str(data.get("currency_symbol", app_config["currency_symbol"])).strip()
    low_stock_threshold = int(data.get("low_stock_threshold", app_config["low_stock_threshold"]) or 5)
    new_order_notifications = bool(data.get("new_order_notifications", app_config["new_order_notifications"]))
    delivery_alert_notifications = bool(data.get("delivery_alert_notifications", app_config["delivery_alert_notifications"]))
    maintenance_mode = bool(data.get("maintenance_mode", app_config["maintenance_mode"]))

    if not app_name:
        return jsonify({"message": "App name is required"}), 400

    if not currency:
        return jsonify({"message": "Currency is required"}), 400

    settings["app_configuration"] = {
        "app_name": app_name,
        "support_email": support_email,
        "support_mobile": support_mobile,
        "currency": currency,
        "currency_symbol": currency_symbol,
        "low_stock_threshold": low_stock_threshold,
        "new_order_notifications": new_order_notifications,
        "delivery_alert_notifications": delivery_alert_notifications,
        "maintenance_mode": maintenance_mode
    }

    _save_admin_settings(settings)
    return jsonify({"message": "App configuration updated successfully"}), 200


@admin_bp.route('/api/admin/settings/security', methods=['GET'])
@jwt_required()
def get_security_settings():
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    settings = _load_admin_settings()
    return jsonify(settings["security_settings"]), 200


@admin_bp.route('/api/admin/settings/security', methods=['PUT'])
@jwt_required()
def update_security_settings():
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    data = request.get_json(silent=True) or {}
    settings = _load_admin_settings()
    security = settings["security_settings"]

    allow_multiple_admin_logins = bool(
        data.get("allow_multiple_admin_logins", security["allow_multiple_admin_logins"])
    )
    force_password_change_days = int(
        data.get("force_password_change_days", security["force_password_change_days"]) or 90
    )
    session_timeout_minutes = int(
        data.get("session_timeout_minutes", security["session_timeout_minutes"]) or 15
    )
    max_login_attempts = int(
        data.get("max_login_attempts", security["max_login_attempts"]) or 5
    )
    profile_image_required = bool(
        data.get("profile_image_required", security["profile_image_required"])
    )

    settings["security_settings"] = {
        "allow_multiple_admin_logins": allow_multiple_admin_logins,
        "force_password_change_days": force_password_change_days,
        "session_timeout_minutes": session_timeout_minutes,
        "max_login_attempts": max_login_attempts,
        "profile_image_required": profile_image_required
    }

    _save_admin_settings(settings)
    return jsonify({"message": "Security settings updated successfully"}), 200


@admin_bp.route('/api/admin/system-info', methods=['GET'])
@jwt_required()
def get_system_info():
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    admin_id = get_jwt_identity()
    claims = get_jwt()
    role = str(claims.get("role", "")).lower()

    settings = _load_admin_settings()
    app_name = settings["app_configuration"].get("app_name", "Desi Cart")

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)

    db_version = "-"
    counts = {
        "users": 0,
        "sellers": 0,
        "delivery_staff": 0,
        "categories": 0,
        "products": 0,
        "orders": 0
    }

    try:
        cur.execute("SELECT VERSION() AS version")
        version_row = cur.fetchone()
        if version_row:
            db_version = version_row.get("version") or "-"
    except Exception:
        pass

    try:
        cur.execute("SELECT COUNT(*) AS total FROM user")
        row = cur.fetchone()
        counts["users"] = int((row or {}).get("total", 0))
    except Exception:
        pass

    try:
        cur.execute("SELECT COUNT(*) AS total FROM seller")
        row = cur.fetchone()
        counts["sellers"] = int((row or {}).get("total", 0))
    except Exception:
        pass

    try:
        cur.execute("SELECT COUNT(*) AS total FROM delivery_staff")
        row = cur.fetchone()
        counts["delivery_staff"] = int((row or {}).get("total", 0))
    except Exception:
        pass

    try:
        cur.execute("SELECT COUNT(*) AS total FROM category")
        row = cur.fetchone()
        counts["categories"] = int((row or {}).get("total", 0))
    except Exception:
        pass

    try:
        cur.execute("SELECT COUNT(*) AS total FROM product")
        row = cur.fetchone()
        counts["products"] = int((row or {}).get("total", 0))
    except Exception:
        pass

    try:
        cur.execute("SELECT COUNT(*) AS total FROM orders")
        row = cur.fetchone()
        counts["orders"] = int((row or {}).get("total", 0))
    except Exception:
        pass

    cur.close()
    conn.close()

    return jsonify({
        "app_name": app_name,
        "app_version": "1.0.0",
        "environment": "Production/Local",
        "server_time": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "database_version": db_version,
        "python_version": platform.python_version(),
        "admin_id": admin_id,
        "role": role,
        "counts": counts
    }), 200


@admin_bp.route('/api/admin/block-requests', methods=['GET'])
@jwt_required()
def get_block_requests():
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)

    try:
        cur.execute("""
            CREATE TABLE IF NOT EXISTS block_requests (
                request_id INT(11) NOT NULL AUTO_INCREMENT,
                account_type ENUM('user','seller','delivery_staff') NOT NULL,
                account_id INT(11) NOT NULL,
                email VARCHAR(200) NOT NULL,
                message TEXT NOT NULL,
                request_status ENUM('pending','accepted','deleted') NOT NULL DEFAULT 'pending',
                requested_at DATETIME NOT NULL DEFAULT current_timestamp(),
                cooldown_until DATETIME NOT NULL,
                accepted_at DATETIME DEFAULT NULL,
                deleted_at DATETIME DEFAULT NULL,
                admin_note TEXT DEFAULT NULL,
                PRIMARY KEY (request_id),
                KEY idx_block_requests_lookup (account_type, account_id, request_status),
                KEY idx_block_requests_email (email)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
        """)
        conn.commit()

        cur.execute("""
            SELECT
                br.request_id,
                br.account_type,
                br.account_id,
                br.email,
                br.message,
                br.request_status,
                br.requested_at,
                br.cooldown_until,
                br.accepted_at,
                br.deleted_at,
                CASE
                    WHEN br.account_type = 'user' THEN u.user_name
                    WHEN br.account_type = 'seller' THEN s.seller_name
                    WHEN br.account_type = 'delivery_staff' THEN ds.delivery_staff_name
                    ELSE ''
                END AS account_name
            FROM block_requests br
            LEFT JOIN user u
                ON br.account_type = 'user' AND br.account_id = u.user_id
            LEFT JOIN seller s
                ON br.account_type = 'seller' AND br.account_id = s.seller_id
            LEFT JOIN delivery_staff ds
                ON br.account_type = 'delivery_staff' AND br.account_id = ds.delivery_staff_id
            WHERE br.request_status = 'pending'
            ORDER BY br.request_id DESC
        """)
        rows = cur.fetchall() or []

        for row in rows:
            for key in ('requested_at', 'cooldown_until', 'accepted_at', 'deleted_at'):
                if row.get(key):
                    row[key] = row[key].isoformat()

        return jsonify(rows), 200
    finally:
        cur.close()
        conn.close()


@admin_bp.route('/api/admin/block-requests/<int:request_id>/accept', methods=['PUT'])
@jwt_required()
def accept_block_request(request_id):
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)

    try:
        cur.execute("""
            SELECT request_id, account_type, account_id, request_status
            FROM block_requests
            WHERE request_id=%s
            LIMIT 1
        """, (request_id,))
        req = cur.fetchone()

        if not req:
            return jsonify({"message": "Request not found"}), 404

        if str(req.get("request_status", "")).lower() != "pending":
            return jsonify({"message": "Only pending requests can be accepted"}), 400

        account_type = req["account_type"]
        account_id = req["account_id"]

        update_cur = conn.cursor()

        if account_type == "user":
            update_cur.execute("UPDATE user SET status='active' WHERE user_id=%s", (account_id,))
        elif account_type == "seller":
            update_cur.execute("UPDATE seller SET status='active' WHERE seller_id=%s", (account_id,))
        elif account_type == "delivery_staff":
            update_cur.execute("UPDATE delivery_staff SET d_s_status='Active' WHERE delivery_staff_id=%s", (account_id,))
        else:
            update_cur.close()
            return jsonify({"message": "Invalid account type"}), 400

        update_cur.execute("""
            UPDATE block_requests
            SET request_status='accepted', accepted_at=%s
            WHERE request_id=%s
        """, (datetime.now(), request_id))
        conn.commit()
        update_cur.close()

        return jsonify({
            "message": "Request accepted and account unblocked successfully."
        }), 200
    finally:
        cur.close()
        conn.close()


@admin_bp.route('/api/admin/block-requests/<int:request_id>', methods=['DELETE'])
@jwt_required()
def delete_block_request(request_id):
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)

    try:
        cur.execute("""
            SELECT request_id, request_status
            FROM block_requests
            WHERE request_id=%s
            LIMIT 1
        """, (request_id,))
        req = cur.fetchone()

        if not req:
            return jsonify({"message": "Request not found"}), 404

        update_cur = conn.cursor()
        update_cur.execute("""
            UPDATE block_requests
            SET request_status='deleted', deleted_at=%s
            WHERE request_id=%s
        """, (datetime.now(), request_id))
        conn.commit()
        update_cur.close()

        return jsonify({"message": "Request deleted successfully."}), 200
    finally:
        cur.close()
        conn.close()


def _ensure_notifications_table(cur):
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS admin_notifications (
            notification_id INT AUTO_INCREMENT PRIMARY KEY,
            title VARCHAR(255) NOT NULL,
            message TEXT NOT NULL,
            target_type ENUM('all','user') NOT NULL DEFAULT 'all',
            target_user_id INT NULL,
            created_by_admin_id INT NULL,
            created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            is_active TINYINT(1) NOT NULL DEFAULT 1
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
        """
    )


@admin_bp.route('/api/admin/notifications', methods=['GET'])
@jwt_required()
def list_admin_notifications():
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)
    try:
        _ensure_notifications_table(cur)
        conn.commit()

        cur.execute(
            """
            SELECT notification_id, title, message, target_type, target_user_id, created_at, is_active
            FROM admin_notifications
            ORDER BY created_at DESC
            LIMIT 100
            """
        )
        notifications = cur.fetchall() or []

        for row in notifications:
            if row.get('created_at'):
                row['created_at'] = row['created_at'].isoformat()
            row['is_active'] = bool(row.get('is_active'))

        return jsonify(notifications), 200
    finally:
        cur.close()
        conn.close()


@admin_bp.route('/api/admin/notifications', methods=['POST'])
@jwt_required()
def create_admin_notification():
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    data = request.get_json(silent=True) or {}
    title = str(data.get('title') or '').strip()
    message = str(data.get('message') or '').strip()
    target_type = str(data.get('target_type') or 'all').strip().lower()
    target_user_id = data.get('target_user_id')

    if not title or not message:
        return jsonify({"message": "Title and message are required."}), 400

    if target_type not in ('all', 'user'):
        return jsonify({"message": "target_type must be 'all' or 'user'."}), 400

    if target_type == 'user':
        try:
            target_user_id = int(target_user_id)
        except Exception:
            return jsonify({"message": "Valid target_user_id is required for user notifications."}), 400
    else:
        target_user_id = None

    admin_id = get_jwt_identity()
    if isinstance(admin_id, dict):
        admin_id = admin_id.get('id') or admin_id.get('admin_id')

    conn = get_db_connection()
    cur = conn.cursor()
    try:
        _ensure_notifications_table(cur)
        cur.execute(
            """
            INSERT INTO admin_notifications (title, message, target_type, target_user_id, created_by_admin_id)
            VALUES (%s, %s, %s, %s, %s)
            """,
            (title, message, target_type, target_user_id, admin_id),
        )
        conn.commit()
        return jsonify({"message": "Notification sent successfully."}), 201
    finally:
        cur.close()
        conn.close()


@admin_bp.route('/api/admin/users/<int:user_id>', methods=['GET'])
@jwt_required()
def get_user_detail_for_admin(user_id):
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)
    try:
        cur.execute(
            """
            SELECT user_id, user_name, user_email, user_mobile, user_address, pincode, status, registration_at, updated_at, profile_image
            FROM user
            WHERE user_id=%s
            LIMIT 1
            """,
            (user_id,),
        )
        user = cur.fetchone()
        if not user:
            return jsonify({"error": "User not found"}), 404

        cur.execute("SELECT COUNT(*) AS total_orders, COALESCE(SUM(CASE WHEN payment_status = 'Paid' THEN total_amount ELSE 0 END),0) AS total_spent FROM orders WHERE user_id=%s", (user_id,))
        stats = cur.fetchone() or {}
        user['stats'] = {
            'total_orders': int(stats.get('total_orders') or 0),
            'total_spent': float(stats.get('total_spent') or 0),
        }
        user['user_mobile'] = '' if user.get('user_mobile') is None else str(user['user_mobile'])
        user['pincode'] = '' if user.get('pincode') is None else str(user['pincode'])
        return jsonify(user), 200
    finally:
        cur.close()
        conn.close()


@admin_bp.route('/api/admin/sellers/<int:seller_id>', methods=['GET'])
@jwt_required()
def get_seller_detail_for_admin(seller_id):
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)
    try:
        cur.execute(
            """
            SELECT seller_id, seller_name, seller_email, seller_mobile, shop_name, shop_address, pincode, licence_no, status, registration_date, updated_at, store_logo
            FROM seller
            WHERE seller_id=%s
            LIMIT 1
            """,
            (seller_id,),
        )
        seller = cur.fetchone()
        if not seller:
            return jsonify({"error": "Seller not found"}), 404

        cur.execute("SELECT COUNT(*) AS total_products FROM product_seller WHERE seller_id=%s", (seller_id,))
        total_products = int((cur.fetchone() or {}).get('total_products') or 0)
        cur.execute("SELECT COUNT(*) AS total_orders, COALESCE(SUM(CASE WHEN payment_status = 'Paid' THEN total_amount ELSE 0 END),0) AS total_revenue FROM orders WHERE seller_id=%s", (seller_id,))
        stats = cur.fetchone() or {}
        seller['stats'] = {
            'total_products': total_products,
            'total_orders': int(stats.get('total_orders') or 0),
            'total_revenue': float(stats.get('total_revenue') or 0),
        }
        seller['seller_mobile'] = '' if seller.get('seller_mobile') is None else str(seller['seller_mobile'])
        seller['pincode'] = '' if seller.get('pincode') is None else str(seller['pincode'])
        return jsonify(seller), 200
    finally:
        cur.close()
        conn.close()


@admin_bp.route('/api/admin/delivery-staff/<int:staff_id>', methods=['GET'])
@jwt_required()
def get_delivery_staff_detail_for_admin(staff_id):
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)
    try:
        cur.execute(
            """
            SELECT delivery_staff_id, delivery_staff_name, d_s_mobile, d_s_email, d_s_address, d_s_pincode, vehicle_type, staff_licence_no, d_s_status, joining_date, profile_image
            FROM delivery_staff
            WHERE delivery_staff_id=%s
            LIMIT 1
            """,
            (staff_id,),
        )
        staff = cur.fetchone()
        if not staff:
            return jsonify({"error": "Delivery staff not found"}), 404

        cur.execute("SELECT COUNT(*) AS assigned_orders FROM orders WHERE delivery_staff_id=%s", (staff_id,))
        assigned = int((cur.fetchone() or {}).get('assigned_orders') or 0)
        cur.execute("SELECT COUNT(*) AS delivered_orders FROM orders WHERE delivery_staff_id=%s AND LOWER(COALESCE(delivery_status,''))='delivered'", (staff_id,))
        delivered = int((cur.fetchone() or {}).get('delivered_orders') or 0)
        staff['stats'] = {
            'assigned_orders': assigned,
            'delivered_orders': delivered,
        }
        staff['d_s_mobile'] = '' if staff.get('d_s_mobile') is None else str(staff['d_s_mobile'])
        staff['d_s_pincode'] = '' if staff.get('d_s_pincode') is None else str(staff['d_s_pincode'])
        return jsonify(staff), 200
    finally:
        cur.close()
        conn.close()
