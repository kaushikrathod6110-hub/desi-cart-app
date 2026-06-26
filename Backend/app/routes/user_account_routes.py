from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required, get_jwt, get_jwt_identity
from db import get_db_connection
from werkzeug.utils import secure_filename
import os
import uuid

user_account_bp = Blueprint("user_account_bp", __name__)

ALLOWED_IMAGE_EXTENSIONS = {"png", "jpg", "jpeg", "webp"}
USER_PROFILE_UPLOAD_FOLDER = os.path.join(os.getcwd(), 'uploads', 'user_profile')
os.makedirs(USER_PROFILE_UPLOAD_FOLDER, exist_ok=True)


def _is_user():
    return str(get_jwt().get("role", "")).lower() == "user"


def _identity_int():
    identity = get_jwt_identity()
    try:
        if isinstance(identity, dict):
            for key in ("id", "user_id", "userId"):
                if identity.get(key) is not None:
                    return int(identity.get(key))
        return int(identity)
    except Exception:
        return None


def _allowed_image(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_IMAGE_EXTENSIONS


def _profile_image_url(filename):
    if not filename:
        return None
    base = request.host_url.rstrip('/')
    clean = str(filename).replace('\\', '/').lstrip('/')
    if clean.startswith('http://') or clean.startswith('https://'):
        return clean
    if clean.startswith('uploads/'):
        return f"{base}/{clean}"
    return f"{base}/uploads/user_profile/{clean}"


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


@user_account_bp.route('/get_user/<int:user_id>', methods=['GET'])
@jwt_required()
def get_user(user_id):
    if not _is_user():
        return jsonify({"message": "Access denied. User only."}), 403

    current_user_id = _identity_int()
    if current_user_id != user_id:
        return jsonify({"message": "You can access only your own profile."}), 403

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)
    cur.execute(
        """
        SELECT user_id, user_name, user_email, user_mobile, user_address, pincode, status, profile_image
        FROM user
        WHERE user_id=%s
        LIMIT 1
        """,
        (user_id,),
    )
    user = cur.fetchone()
    cur.close()
    conn.close()

    if not user:
        return jsonify({"message": "User not found"}), 404

    user["user_mobile"] = "" if user.get("user_mobile") is None else str(user["user_mobile"])
    user["pincode"] = "" if user.get("pincode") is None else str(user["pincode"])
    user["user_name"] = user.get("user_name") or ""
    user["user_email"] = user.get("user_email") or ""
    user["user_address"] = user.get("user_address") or ""
    user["profile_image"] = user.get("profile_image") or ""
    user["profile_image_url"] = _profile_image_url(user.get("profile_image"))

    return jsonify(user), 200


@user_account_bp.route('/update_user/<int:user_id>', methods=['PUT'])
@jwt_required()
def update_user(user_id):
    if not _is_user():
        return jsonify({"message": "Access denied. User only."}), 403

    current_user_id = _identity_int()
    if current_user_id != user_id:
        return jsonify({"message": "You can update only your own profile."}), 403

    is_multipart = request.content_type and 'multipart/form-data' in request.content_type.lower()

    conn = get_db_connection()
    read_cur = conn.cursor(dictionary=True)
    read_cur.execute(
        """
        SELECT user_id, user_name, user_email, user_mobile, user_address, pincode, profile_image
        FROM user
        WHERE user_id = %s
        LIMIT 1
        """,
        (user_id,),
    )
    existing_user = read_cur.fetchone()
    read_cur.close()

    if not existing_user:
        conn.close()
        return jsonify({"message": "User not found"}), 404

    if is_multipart:
        name = str(request.form.get('user_name', existing_user.get('user_name') or '')).strip()
        email = str(request.form.get('user_email', existing_user.get('user_email') or '')).strip()
        mobile = str(request.form.get('user_mobile', existing_user.get('user_mobile') or '')).strip()
        address = str(request.form.get('user_address', existing_user.get('user_address') or '')).strip()
        pincode = str(request.form.get('pincode', existing_user.get('pincode') or '')).strip()
        remove_image = str(request.form.get('remove_image', '0')).strip()
        profile_file = request.files.get('profile_image')
    else:
        data = request.get_json(silent=True) or {}
        name = str(data.get('user_name', existing_user.get('user_name') or '')).strip()
        email = str(data.get('user_email', existing_user.get('user_email') or '')).strip()
        mobile = str(data.get('user_mobile', existing_user.get('user_mobile') or '')).strip()
        address = str(data.get('user_address', existing_user.get('user_address') or '')).strip()
        pincode = str(data.get('pincode', existing_user.get('pincode') or '')).strip()
        remove_image = str(data.get('remove_image', '0')).strip()
        profile_file = None

    required = [name, email, mobile]
    if any(value == '' for value in required):
        conn.close()
        return jsonify({"message": "Name, email and mobile are required"}), 400

    image_filename = existing_user.get('profile_image') or None

    if remove_image == '1':
        old_image = existing_user.get('profile_image')
        if old_image:
            old_path = os.path.join(USER_PROFILE_UPLOAD_FOLDER, os.path.basename(str(old_image)))
            if os.path.exists(old_path):
                try:
                    os.remove(old_path)
                except OSError:
                    pass
        image_filename = None

    if profile_file and profile_file.filename:
        if not _allowed_image(profile_file.filename):
            conn.close()
            return jsonify({"message": "Only png, jpg, jpeg and webp images are allowed."}), 400

        ext = secure_filename(profile_file.filename).rsplit('.', 1)[1].lower()
        image_filename = f"user_{user_id}_{uuid.uuid4().hex[:10]}.{ext}"
        save_path = os.path.join(USER_PROFILE_UPLOAD_FOLDER, image_filename)
        profile_file.save(save_path)

        old_image = existing_user.get('profile_image')
        if old_image and os.path.basename(str(old_image)) != image_filename:
            old_path = os.path.join(USER_PROFILE_UPLOAD_FOLDER, os.path.basename(str(old_image)))
            if os.path.exists(old_path):
                try:
                    os.remove(old_path)
                except OSError:
                    pass

    cur = conn.cursor()
    cur.execute(
        """
        UPDATE user
        SET user_name=%s,
            user_email=%s,
            user_mobile=%s,
            user_address=%s,
            pincode=%s,
            profile_image=%s,
            updated_at=CURRENT_TIMESTAMP
        WHERE user_id=%s
        """,
        (name, email, mobile, address, pincode, image_filename, user_id),
    )
    conn.commit()
    cur.close()
    conn.close()

    return jsonify({
        "message": "Profile updated successfully",
        "profile_image": image_filename or "",
        "profile_image_url": _profile_image_url(image_filename),
    }), 200


@user_account_bp.route('/api/user/notifications', methods=['GET'])
@jwt_required()
def get_user_notifications():
    if not _is_user():
        return jsonify({"message": "Access denied. User only."}), 403

    user_id = _identity_int()
    if user_id is None:
        return jsonify({"message": "Invalid user token"}), 401

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)
    try:
        _ensure_notifications_table(cur)
        notifications = []

        cur.execute(
            """
            SELECT notification_id, title, message, created_at
            FROM admin_notifications
            WHERE is_active = 1
              AND (target_type = 'all' OR (target_type = 'user' AND target_user_id = %s))
            ORDER BY created_at DESC
            LIMIT 50
            """,
            (user_id,),
        )
        for row in cur.fetchall() or []:
            notifications.append({
                "id": f"admin_{row['notification_id']}",
                "title": row.get("title") or "Admin Notification",
                "message": row.get("message") or "",
                "type": "admin",
                "created_at": row.get("created_at").isoformat() if row.get("created_at") else None,
            })

        cur.execute(
            """
            SELECT order_id, order_status, delivery_status, payment_status, order_date, total_amount
            FROM orders
            WHERE user_id = %s
            ORDER BY order_date ASC, order_id ASC
            """,
            (user_id,),
        )
        order_rows = cur.fetchall() or []
        total_user_orders = len(order_rows)

        for index, row in enumerate(order_rows, start=1):
            order_id = row.get('order_id')
            order_status = row.get('order_status') or 'Pending'
            delivery_status = row.get('delivery_status') or 'Pending'
            payment_status = row.get('payment_status') or 'Pending'
            amount = row.get('total_amount') or 0
            notifications.append({
                "id": f"order_{order_id}",
                "title": f"Your Order #{index} update",
                "message": f"Status: {order_status} | Delivery: {delivery_status} | Payment: {payment_status} | Amount: ₹{amount}",
                "type": "order",
                "order_id": order_id,
                "display_order_number": index,
                "total_user_orders": total_user_orders,
                "created_at": row.get('order_date').isoformat() if row.get('order_date') else None,
            })

        notifications.sort(key=lambda item: item.get('created_at') or '', reverse=True)
        return jsonify(notifications[:100]), 200
    finally:
        cur.close()
        conn.close()


@user_account_bp.route('/api/user/notifications/read-all', methods=['POST'])
@jwt_required()
def mark_all_user_notifications_read():
    if not _is_user():
        return jsonify({"message": "Access denied. User only."}), 403

    user_id = _identity_int()
    if user_id is None:
        return jsonify({"message": "Invalid user token"}), 401

    conn = get_db_connection()
    cur = conn.cursor()
    try:
        _ensure_notifications_table(cur)
        cur.execute(
            """
            UPDATE admin_notifications
            SET is_active = 0
            WHERE is_active = 1
              AND (target_type = 'all' OR (target_type = 'user' AND target_user_id = %s))
            """,
            (user_id,),
        )
        conn.commit()
        return jsonify({"message": "Notifications marked as read"}), 200
    except Exception as e:
        conn.rollback()
        return jsonify({"message": str(e)}), 500
    finally:
        cur.close()
        conn.close()


@user_account_bp.route('/api/user/rate-app', methods=['POST'])
@jwt_required()
def submit_app_rating():
    if not _is_user():
        return jsonify({"success": False, "message": "Access denied. User only."}), 403

    user_id = _identity_int()
    if user_id is None:
        return jsonify({"success": False, "message": "Invalid user token"}), 401

    data = request.get_json(silent=True) or {}
    rating = int(data.get('rating') or 0)
    comment = str(data.get('comment') or '').strip()

    if rating < 1 or rating > 5:
        return jsonify({"success": False, "message": "Rating must be between 1 and 5"}), 400

    conn = get_db_connection()
    cur = conn.cursor()
    try:
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS app_feedback (
                feedback_id INT AUTO_INCREMENT PRIMARY KEY,
                user_id INT NOT NULL,
                rating INT NOT NULL,
                comment TEXT NULL,
                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
            """
        )
        cur.execute(
            "INSERT INTO app_feedback (user_id, rating, comment) VALUES (%s, %s, %s)",
            (user_id, rating, comment),
        )
        conn.commit()
        return jsonify({"success": True, "message": "Rating submitted successfully"}), 200
    except Exception as e:
        conn.rollback()
        return jsonify({"success": False, "message": str(e)}), 500
    finally:
        cur.close()
        conn.close()
