from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required, get_jwt, get_jwt_identity
from db import get_db_connection
from datetime import datetime
import json
import os
import re
import uuid
from decimal import Decimal
from werkzeug.utils import secure_filename


delivery_staff_bp = Blueprint("delivery_staff_bp", __name__)


def _table_exists(cur, table_name):
    cur.execute("SHOW TABLES LIKE %s", (table_name,))
    return cur.fetchone() is not None


def _column_exists(cur, table_name, column_name):
    cur.execute(f"SHOW COLUMNS FROM `{table_name}` LIKE %s", (column_name,))
    return cur.fetchone() is not None


def _sync_delivery_table(conn, order_id, status=None, staff_id=None, delivery_date=None):
    meta_cur = conn.cursor(dictionary=True)
    try:
        if not _table_exists(meta_cur, "delivery"):
            return

        meta_cur.execute(
            """
            SELECT
                order_id,
                delivery_staff_id,
                order_date,
                delivery_address,
                pincode,
                delivery_status,
                notes
            FROM orders
            WHERE order_id = %s
            LIMIT 1
            """,
            (order_id,),
        )
        order_row = meta_cur.fetchone()
        if not order_row:
            return

        final_staff_id = staff_id if staff_id is not None else order_row.get("delivery_staff_id")
        final_status = status or order_row.get("delivery_status") or "Unassigned"
        final_delivery_date = delivery_date if delivery_date is not None else (order_row.get("order_date") or datetime.now())

        data = {
            "order_id": order_id,
            "delivery_staff_id": final_staff_id,
            "delivery_date": final_delivery_date,
            "delivery_address": order_row.get("delivery_address"),
            "delivery_pincode": order_row.get("pincode"),
            "delivery_status": final_status,
            "notes": _clean_cod_payment_note(order_row.get("notes")),
        }

        available_cols = [col for col in data.keys() if _column_exists(meta_cur, "delivery", col)]
        if not available_cols:
            return

        meta_cur.execute("SELECT delivery_id FROM delivery WHERE order_id = %s LIMIT 1", (order_id,))
        existing = meta_cur.fetchone()

        write_cur = conn.cursor()
        if existing:
            update_cols = [col for col in available_cols if col != "order_id"]
            if update_cols:
                set_sql = ", ".join([f"`{col}` = %s" for col in update_cols])
                values = [data[col] for col in update_cols]
                write_cur.execute(
                    f"UPDATE delivery SET {set_sql} WHERE order_id = %s",
                    tuple(values + [order_id]),
                )
        else:
            cols_sql = ", ".join([f"`{col}`" for col in available_cols])
            marks_sql = ", ".join(["%s"] * len(available_cols))
            write_cur.execute(
                f"INSERT INTO delivery ({cols_sql}) VALUES ({marks_sql})",
                tuple(data[col] for col in available_cols),
            )
        write_cur.close()
    finally:
        meta_cur.close()


def _is_delivery_staff():
    return str(get_jwt().get("role", "")).lower() == "delivery_staff"


def _num(v):
    if v is None:
        return 0
    if isinstance(v, Decimal):
        return float(v)
    return float(v)


def _safe_int(v):
    return int(v or 0)


def _safe_float(v):
    try:
        if v is None:
            return 0.0
        if isinstance(v, Decimal):
            return float(v)
        return float(v)
    except Exception:
        return 0.0


def _parse_date_value(value):
    try:
        if not value:
            return None
        return datetime.strptime(str(value).strip(), '%Y-%m-%d').date()
    except Exception:
        return None


def _earning_per_order(order_row=None):
    return 20.0


def _earning_amount(order_row=None):
    return round(_earning_per_order(order_row), 2)


def _delivery_staff_earnings_summary(cur, staff_id, start_date=None, end_date=None):
    conditions = ["o.delivery_staff_id = %s", "COALESCE(o.delivery_status, '') = 'Delivered'"]
    params = [staff_id]

    if start_date is not None:
        conditions.append("DATE(COALESCE(o.delivered_at, o.order_date)) >= %s")
        params.append(start_date)
    if end_date is not None:
        conditions.append("DATE(COALESCE(o.delivered_at, o.order_date)) <= %s")
        params.append(end_date)

    where_sql = ' AND '.join(conditions)

    cur.execute(f"""
        SELECT
            COUNT(*) AS delivered_orders,
            COALESCE(SUM(o.total_amount), 0) AS delivered_amount,
            COALESCE(SUM(CASE
                WHEN UPPER(COALESCE(o.payment_method, '')) = 'COD'
                 AND COALESCE(o.payment_status, '') IN ('Paid', 'Success')
                THEN o.total_amount
                ELSE 0
            END), 0) AS cod_collected
        FROM orders o
        WHERE {where_sql}
    """, tuple(params))
    row = cur.fetchone() or {}

    delivered_orders = _safe_int(row.get('delivered_orders'))
    earning_per_order = _earning_per_order()
    total_earning = round(delivered_orders * earning_per_order, 2)

    return {
        'delivered_orders': delivered_orders,
        'delivered_amount': round(_safe_float(row.get('delivered_amount')), 2),
        'cod_collected': round(_safe_float(row.get('cod_collected')), 2),
        'earning_per_order': earning_per_order,
        'total_earning': total_earning,
    }


def _clean_cod_payment_note(note_text):
    text = str(note_text or "").strip()
    if not text:
        return ""

    text = re.sub(
        r'(?i)(?:\s*\|\s*)?cod\s+payment\s+marked\s+.*?(?=(?:\s*\|\s*)|$)',
        '',
        text,
    )
    text = re.sub(r'\s*\|\s*', ' | ', text)
    text = re.sub(r'\s{2,}', ' ', text).strip(' |')
    return text.strip()






def _is_user_role():
    return str(get_jwt().get("role", "")).lower() == "user"


def _current_identity_int():
    try:
        return int(get_jwt_identity())
    except Exception:
        return None


def _normalize_status_text(value):
    return str(value or "").strip().lower().replace("_", " ").replace("-", " ")


def _is_delivered_status(order_row):
    return _normalize_status_text(order_row.get("order_status")) == "delivered" or _normalize_status_text(order_row.get("delivery_status")) == "delivered"


def _ensure_delivery_staff_reviews_table(cur):
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS delivery_staff_reviews (
            delivery_review_id INT AUTO_INCREMENT PRIMARY KEY,
            order_id INT NOT NULL,
            user_id INT NOT NULL,
            delivery_staff_id INT NOT NULL,
            rating INT NULL,
            review TEXT NULL,
            review_tags TEXT NULL,
            is_skipped TINYINT(1) NOT NULL DEFAULT 0,
            skipped_at DATETIME NULL,
            created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            CONSTRAINT chk_delivery_staff_reviews_rating CHECK (rating IS NULL OR (rating BETWEEN 1 AND 5)),
            UNIQUE KEY uq_delivery_staff_review_order (order_id),
            INDEX idx_delivery_staff_reviews_staff (delivery_staff_id),
            INDEX idx_delivery_staff_reviews_user (user_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
        """
    )


def _fetch_delivery_rating_order(cur, order_id):
    cur.execute(
        """
        SELECT
            o.order_id,
            o.user_id,
            o.delivery_staff_id,
            o.order_status,
            o.delivery_status,
            d.delivery_staff_name,
            d.d_s_mobile,
            d.vehicle_type
        FROM orders o
        LEFT JOIN delivery_staff d ON d.delivery_staff_id = o.delivery_staff_id
        WHERE o.order_id = %s
        LIMIT 1
        """,
        (order_id,),
    )
    return cur.fetchone()


def _fetch_delivery_review(cur, order_id):
    _ensure_delivery_staff_reviews_table(cur)
    cur.execute(
        """
        SELECT
            delivery_review_id, order_id, user_id, delivery_staff_id, rating, review,
            review_tags, is_skipped, skipped_at, created_at, updated_at
        FROM delivery_staff_reviews
        WHERE order_id = %s
        LIMIT 1
        """,
        (order_id,),
    )
    review = cur.fetchone()
    if review and review.get('review_tags'):
        try:
            review['review_tags'] = json.loads(review['review_tags'])
        except Exception:
            review['review_tags'] = []
    elif review:
        review['review_tags'] = []
    return review


def _delivery_review_payload(order_row, review_row=None):
    review_row = review_row or {}
    has_review = bool(review_row) and int(review_row.get('is_skipped') or 0) != 1 and review_row.get('rating') is not None
    return {
        'order_id': order_row.get('order_id'),
        'delivery_staff_id': order_row.get('delivery_staff_id'),
        'delivery_staff_name': order_row.get('delivery_staff_name') or '',
        'delivery_staff_mobile': '' if order_row.get('d_s_mobile') is None else str(order_row.get('d_s_mobile')),
        'vehicle_type': order_row.get('vehicle_type') or '',
        'can_rate': bool(order_row.get('delivery_staff_id')) and _is_delivered_status(order_row),
        'has_review': has_review,
        'is_skipped': bool(int(review_row.get('is_skipped') or 0)) if review_row else False,
        'review': {
            'delivery_review_id': review_row.get('delivery_review_id'),
            'rating': review_row.get('rating'),
            'review': review_row.get('review') or '',
            'review_tags': review_row.get('review_tags') or [],
            'created_at': review_row.get('created_at'),
            'updated_at': review_row.get('updated_at'),
        } if review_row else None,
    }

def _build_upload_url(filename):
    if not filename:
        return None
    base = request.host_url.rstrip('/')
    return f"{base}/uploads/{filename}"

def _uploads_dir():
    uploads_dir = os.path.join(os.getcwd(), 'uploads')
    os.makedirs(uploads_dir, exist_ok=True)
    return uploads_dir


def _save_profile_image(file_storage):
    if file_storage is None or not getattr(file_storage, 'filename', ''):
        return None

    original_name = secure_filename(file_storage.filename)
    ext = os.path.splitext(original_name)[1] or '.jpg'
    filename = f"delivery_staff_{uuid.uuid4().hex}{ext}"
    save_path = os.path.join(_uploads_dir(), filename)
    file_storage.save(save_path)
    return filename


def _fetch_delivery_staff_profile(conn, staff_id):
    cur = conn.cursor(dictionary=True)
    try:
        select_cols = [
            'delivery_staff_id',
            'delivery_staff_name',
            'd_s_mobile',
            'd_s_email',
            'd_s_address',
            'd_s_pincode',
            'vehicle_type',
            'staff_licence_no',
            'd_s_status',
            'joining_date',
        ]

        if _column_exists(cur, 'delivery_staff', 'aadhar_card_no'):
            select_cols.append('aadhar_card_no')
        if _column_exists(cur, 'delivery_staff', 'profile_image'):
            select_cols.append('profile_image')

        cols_sql = ','.join(select_cols)
        cur.execute(f"""
            SELECT
                {cols_sql}
            FROM delivery_staff
            WHERE delivery_staff_id = %s
            LIMIT 1
        """, (staff_id,))

        profile = cur.fetchone()
        if not profile:
            return None

        profile['d_s_mobile'] = '' if profile.get('d_s_mobile') is None else str(profile['d_s_mobile'])
        profile['d_s_pincode'] = '' if profile.get('d_s_pincode') is None else str(profile['d_s_pincode'])
        if 'aadhar_card_no' in profile:
            profile['aadhar_card_no'] = '' if profile.get('aadhar_card_no') is None else str(profile['aadhar_card_no'])
        if 'profile_image' in profile and profile.get('profile_image') is None:
            profile['profile_image'] = ''
        if 'profile_image' in profile:
            profile['profile_image_url'] = _build_upload_url(profile.get('profile_image'))
        else:
            profile['profile_image_url'] = None
        return profile
    finally:
        cur.close()



@delivery_staff_bp.route('/api/delivery-staff/dashboard', methods=['GET'])
@jwt_required()
def delivery_staff_dashboard():
    if not _is_delivery_staff():
        return jsonify({"message": "Access denied. Delivery staff only."}), 403

    staff_id = get_jwt_identity()

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)

    profile = _fetch_delivery_staff_profile(conn, staff_id)

    if not profile:
        cur.close()
        conn.close()
        return jsonify({"message": "Delivery staff not found"}), 404

    cur.execute("""
        SELECT COUNT(*) AS total_assigned
        FROM orders
        WHERE delivery_staff_id = %s
    """, (staff_id,))
    total_assigned = _safe_int(cur.fetchone()["total_assigned"])

    cur.execute("""
        SELECT COUNT(*) AS active_orders
        FROM orders
        WHERE delivery_staff_id = %s
          AND delivery_status IN ('Assigned', 'Picked Up', 'Out For Delivery')
    """, (staff_id,))
    active_orders = _safe_int(cur.fetchone()["active_orders"])

    cur.execute("""
        SELECT COUNT(*) AS delivered_orders
        FROM orders
        WHERE delivery_staff_id = %s
          AND delivery_status = 'Delivered'
    """, (staff_id,))
    delivered_orders = _safe_int(cur.fetchone()["delivered_orders"])

    cur.execute("""
        SELECT COUNT(*) AS available_orders
        FROM orders
        WHERE delivery_staff_id IS NULL
          AND COALESCE(delivery_status, 'Unassigned') = 'Unassigned'
          AND COALESCE(order_status, 'Pending') <> 'Delivered'
    """)
    available_orders = _safe_int(cur.fetchone()["available_orders"])

    _ensure_delivery_staff_reviews_table(cur)
    cur.execute("""
        SELECT AVG(rating) AS avg_rating, COUNT(*) AS total_reviews
        FROM delivery_staff_reviews
        WHERE delivery_staff_id = %s
          AND COALESCE(is_skipped, 0) = 0
          AND rating IS NOT NULL
    """, (staff_id,))
    rating_row = cur.fetchone() or {}
    avg_rating = float(rating_row.get("avg_rating") or 0)
    total_reviews = _safe_int(rating_row.get("total_reviews"))

    today = datetime.now().date()
    month_start = today.replace(day=1)
    earnings_today = _delivery_staff_earnings_summary(cur, staff_id, today, today)
    earnings_month = _delivery_staff_earnings_summary(cur, staff_id, month_start, today)
    earnings_all = _delivery_staff_earnings_summary(cur, staff_id)

    cur.execute("""
    SELECT
    o.order_id,
    o.user_id,
    o.total_amount,
    o.order_status,
    o.payment_status,
    o.payment_method,
    o.order_date,
    o.delivery_status,

    u.user_name,
    u.user_mobile,
    u.user_address,
    o.pincode AS user_pincode,

    COALESCE(NULLIF(oi.seller_id, 0), o.seller_id) AS seller_id,
    s.seller_name,
    s.seller_mobile,
    s.shop_name,
    s.shop_address,
    s.pincode AS seller_pincode

    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    LEFT JOIN seller s ON s.seller_id = COALESCE(NULLIF(oi.seller_id, 0), o.seller_id)
    LEFT JOIN user u ON u.user_id = o.user_id

    WHERE o.delivery_staff_id = %s
    AND o.delivery_status IN ('Assigned','Picked Up','Out For Delivery')

    ORDER BY o.order_date DESC
    LIMIT 5
    """, (staff_id,))
    recent_orders_raw = cur.fetchall()

    recent_orders = []
    for r in recent_orders_raw:
        recent_orders.append({
            "order_id": r["order_id"],
            "user_name": r.get("user_name"),
            "user_mobile": str(r.get("user_mobile") or ""),
            "user_address": r.get("user_address"),
            "user_pincode": str(r.get("user_pincode") or ""),
            "seller_id": r.get("seller_id"),
            "seller_name": r.get("seller_name"),
            "seller_mobile": str(r.get("seller_mobile") or ""),
            "shop_name": r.get("shop_name"),
            "shop_address": r.get("shop_address"),
            "seller_pincode": str(r.get("seller_pincode") or ""),
            "total_amount": _num(r.get("total_amount")),
            "order_status": r.get("order_status") or "",
            "payment_status": r.get("payment_status") or "",
            "payment_method": r.get("payment_method") or "",
            "order_date": r["order_date"].isoformat() if r.get("order_date") else None,
            "delivery_status": r.get("delivery_status") or "",
            "earning_amount": _earning_amount(r),
        })

    cur.close()
    conn.close()

    return jsonify({
        "profile": profile,
        "summary": {
            "total_assigned": total_assigned,
            "active_orders": active_orders,
            "delivered_orders": delivered_orders,
            "available_orders": available_orders,
            "avg_rating": avg_rating,
            "total_reviews": total_reviews,
        },
        "earnings": {
            "today": earnings_today,
            "this_month": earnings_month,
            "all_time": earnings_all,
        },
        "recent_orders": recent_orders,
    }), 200


@delivery_staff_bp.route('/api/delivery-staff/profile', methods=['GET'])
@jwt_required()
def get_delivery_staff_profile():
    if not _is_delivery_staff():
        return jsonify({"message": "Access denied. Delivery staff only."}), 403

    staff_id = get_jwt_identity()

    conn = get_db_connection()
    staff = _fetch_delivery_staff_profile(conn, staff_id)
    conn.close()

    if not staff:
        return jsonify({"message": "Delivery staff not found"}), 404

    return jsonify(staff), 200


@delivery_staff_bp.route('/api/delivery-staff/profile', methods=['PUT'])
@jwt_required()
def update_delivery_staff_profile():
    if not _is_delivery_staff():
        return jsonify({"message": "Access denied. Delivery staff only."}), 403

    staff_id = get_jwt_identity()
    data = request.form if request.form else (request.get_json(silent=True) or {})

    name = str(data.get('delivery_staff_name', '')).strip()
    mobile = str(data.get('d_s_mobile', '')).strip()
    address = str(data.get('d_s_address', '')).strip()
    pincode = str(data.get('d_s_pincode', '')).strip()
    vehicle_type = str(data.get('vehicle_type', '')).strip()
    staff_licence_no = str(data.get('staff_licence_no', '')).strip()
    aadhar_card_no = str(data.get('aadhar_card_no', '')).strip()
    remove_profile_image = str(data.get('remove_profile_image', '0')).strip() == '1'
    profile_image_file = request.files.get('profile_image')

    if not name:
        return jsonify({"message": "Name is required"}), 400
    if not mobile:
        return jsonify({"message": "Mobile number is required"}), 400
    if not re.fullmatch(r'\d{10}', mobile):
        return jsonify({"message": "Mobile number must be 10 digits"}), 400
    if not address:
        return jsonify({"message": "Address is required"}), 400
    if not pincode:
        return jsonify({"message": "Pincode is required"}), 400
    if not re.fullmatch(r'\d{6}', pincode):
        return jsonify({"message": "Pincode must be 6 digits"}), 400
    if not vehicle_type:
        return jsonify({"message": "Vehicle type is required"}), 400

    if vehicle_type in ('Cycle', 'None'):
        staff_licence_no = None
    elif not staff_licence_no:
        return jsonify({"message": "Licence number is required for selected vehicle"}), 400

    conn = get_db_connection()
    meta_cur = conn.cursor(dictionary=True)
    has_aadhar_column = _column_exists(meta_cur, 'delivery_staff', 'aadhar_card_no')
    has_profile_image_column = _column_exists(meta_cur, 'delivery_staff', 'profile_image')

    if has_aadhar_column:
        if not aadhar_card_no:
            meta_cur.close()
            conn.close()
            return jsonify({"message": "Aadhar card number is required"}), 400
        if not re.fullmatch(r'\d{12}', aadhar_card_no):
            meta_cur.close()
            conn.close()
            return jsonify({"message": "Aadhar card number must be exactly 12 digits"}), 400

    existing_image = None
    if has_profile_image_column:
        meta_cur.execute(
            "SELECT profile_image FROM delivery_staff WHERE delivery_staff_id = %s LIMIT 1",
            (staff_id,),
        )
        row = meta_cur.fetchone()
        existing_image = (row or {}).get('profile_image')

    new_profile_image = existing_image
    if has_profile_image_column:
        if remove_profile_image:
            new_profile_image = None
        if profile_image_file and getattr(profile_image_file, 'filename', ''):
            saved_name = _save_profile_image(profile_image_file)
            if saved_name:
                new_profile_image = saved_name

    write_cur = conn.cursor()
    if has_aadhar_column and has_profile_image_column:
        write_cur.execute("""
            UPDATE delivery_staff
            SET
                delivery_staff_name = %s,
                d_s_mobile = %s,
                d_s_address = %s,
                d_s_pincode = %s,
                vehicle_type = %s,
                staff_licence_no = %s,
                aadhar_card_no = %s,
                profile_image = %s
            WHERE delivery_staff_id = %s
        """, (name, mobile, address, pincode, vehicle_type, staff_licence_no, aadhar_card_no, new_profile_image, staff_id))
    elif has_aadhar_column:
        write_cur.execute("""
            UPDATE delivery_staff
            SET
                delivery_staff_name = %s,
                d_s_mobile = %s,
                d_s_address = %s,
                d_s_pincode = %s,
                vehicle_type = %s,
                staff_licence_no = %s,
                aadhar_card_no = %s
            WHERE delivery_staff_id = %s
        """, (name, mobile, address, pincode, vehicle_type, staff_licence_no, aadhar_card_no, staff_id))
    elif has_profile_image_column:
        write_cur.execute("""
            UPDATE delivery_staff
            SET
                delivery_staff_name = %s,
                d_s_mobile = %s,
                d_s_address = %s,
                d_s_pincode = %s,
                vehicle_type = %s,
                staff_licence_no = %s,
                profile_image = %s
            WHERE delivery_staff_id = %s
        """, (name, mobile, address, pincode, vehicle_type, staff_licence_no, new_profile_image, staff_id))
    else:
        write_cur.execute("""
            UPDATE delivery_staff
            SET
                delivery_staff_name = %s,
                d_s_mobile = %s,
                d_s_address = %s,
                d_s_pincode = %s,
                vehicle_type = %s,
                staff_licence_no = %s
            WHERE delivery_staff_id = %s
        """, (name, mobile, address, pincode, vehicle_type, staff_licence_no, staff_id))

    conn.commit()
    write_cur.close()
    meta_cur.close()

    updated_profile = _fetch_delivery_staff_profile(conn, staff_id)
    conn.close()

    return jsonify({
        "message": "Profile updated successfully",
        "profile": updated_profile or {},
    }), 200


@delivery_staff_bp.route('/api/delivery-staff/available-orders', methods=['GET'])
@jwt_required()
def get_available_orders():
    if not _is_delivery_staff():
        return jsonify({"message": "Access denied. Delivery staff only."}), 403

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)

    cur.execute("""
    SELECT
    o.order_id,
    o.user_id,
    o.total_amount,
    o.order_status,
    o.payment_status,
    o.payment_method,
    o.order_date,
    o.delivery_status,

    u.user_name,
    u.user_mobile,
    u.user_address,

    o.pincode AS user_pincode,

    COALESCE(NULLIF(oi.seller_id, 0), o.seller_id) AS seller_id,
    s.seller_name,
    s.seller_mobile,
    s.shop_name,
    s.shop_address,
    s.pincode AS seller_pincode

    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    LEFT JOIN seller s ON s.seller_id = COALESCE(NULLIF(oi.seller_id, 0), o.seller_id)
    LEFT JOIN user u ON u.user_id = o.user_id

    WHERE o.delivery_staff_id IS NULL
    AND COALESCE(o.delivery_status,'Unassigned')='Unassigned'
    AND COALESCE(o.order_status,'Pending') <> 'Delivered'

    ORDER BY o.order_id
    """)

    rows = cur.fetchall()

    cur.close()
    conn.close()

    orders = []

    for r in rows:
        orders.append({
        "order_id": r["order_id"],
        "user_id": r.get("user_id"),

        "user_name": r.get("user_name"),
        "user_mobile": "" if r.get("user_mobile") is None else str(r["user_mobile"]),
        "user_address": r.get("user_address"),
        "user_pincode": str(r.get("user_pincode") or ""),

        "seller_id": r.get("seller_id"),
        "seller_name": r.get("seller_name"),
        "seller_mobile": "" if r.get("seller_mobile") is None else str(r["seller_mobile"]),
        "shop_name": r.get("shop_name"),
        "shop_address": r.get("shop_address"),
        "seller_pincode": str(r.get("seller_pincode") or ""),

        "total_amount": _num(r.get("total_amount")),
        "order_status": r.get("order_status") or "",
        "payment_status": r.get("payment_status") or "",
        "payment_method": r.get("payment_method") or "",
        "order_date": r["order_date"].isoformat() if r.get("order_date") else None,
        "delivery_status": r.get("delivery_status") or "",
    })
    return jsonify({"orders": orders}), 200

@delivery_staff_bp.route('/api/delivery-staff/my-orders', methods=['GET'])
@jwt_required()
def get_my_orders():
    if not _is_delivery_staff():
        return jsonify({"message": "Access denied. Delivery staff only."}), 403

    staff_id = get_jwt_identity()
    filter_type = str(request.args.get("filter", "all")).strip().lower()
    start_date = _parse_date_value(request.args.get('start_date'))
    end_date = _parse_date_value(request.args.get('end_date'))

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)

    base_query = """
    SELECT
    o.order_id,
    o.user_id,
    o.total_amount,
    o.order_status,
    o.payment_status,
    o.payment_method,
    o.order_date,
    o.delivery_status,
    o.delivered_at,

    u.user_name,
    u.user_mobile,
    u.user_address,
    o.pincode AS user_pincode,

    COALESCE(NULLIF(oi.seller_id, 0), o.seller_id) AS seller_id,
    s.seller_name,
    s.seller_mobile,
    s.shop_name,
    s.shop_address,
    s.pincode AS seller_pincode

    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    LEFT JOIN seller s ON s.seller_id = COALESCE(NULLIF(oi.seller_id, 0), o.seller_id)
    LEFT JOIN user u ON u.user_id = o.user_id

    WHERE o.delivery_staff_id = %s
    """

    params = [staff_id]

    if filter_type == "active":
        base_query += " AND o.delivery_status IN ('Assigned', 'Picked Up', 'Out For Delivery') "
    elif filter_type == "delivered":
        base_query += " AND o.delivery_status = 'Delivered' "

    if start_date is not None:
        base_query += " AND DATE(COALESCE(o.delivered_at, o.order_date)) >= %s "
        params.append(start_date)
    if end_date is not None:
        base_query += " AND DATE(COALESCE(o.delivered_at, o.order_date)) <= %s "
        params.append(end_date)

    base_query += " ORDER BY o.order_date DESC, o.order_id DESC "

    cur.execute(base_query, tuple(params))
    rows = cur.fetchall()

    orders = []
    for r in rows:
        orders.append({
            "order_id": r["order_id"],
            "user_name": r.get("user_name"),
            "user_mobile": str(r.get("user_mobile") or ""),
            "user_address": r.get("user_address"),
            "user_pincode": str(r.get("user_pincode") or ""),
            "seller_id": r.get("seller_id"),
            "seller_name": r.get("seller_name"),
            "seller_mobile": str(r.get("seller_mobile") or ""),
            "shop_name": r.get("shop_name"),
            "shop_address": r.get("shop_address"),
            "seller_pincode": str(r.get("seller_pincode") or ""),
            "total_amount": _num(r.get("total_amount")),
            "order_status": r.get("order_status") or "",
            "payment_status": r.get("payment_status") or "",
            "payment_method": r.get("payment_method") or "",
            "order_date": r["order_date"].isoformat() if r.get("order_date") else None,
            "delivered_at": r["delivered_at"].isoformat() if r.get("delivered_at") else None,
            "delivery_status": r.get("delivery_status") or "",
            "earning_amount": _earning_amount(r) if (r.get('delivery_status') == 'Delivered') else 0,
        })

    today = datetime.now().date()
    month_start = today.replace(day=1)
    response = {
        "orders": orders,
        "summary": {
            "today": _delivery_staff_earnings_summary(cur, staff_id, today, today),
            "this_month": _delivery_staff_earnings_summary(cur, staff_id, month_start, today),
            "custom": _delivery_staff_earnings_summary(cur, staff_id, start_date, end_date) if (start_date or end_date) else _delivery_staff_earnings_summary(cur, staff_id),
        }
    }

    cur.close()
    conn.close()
    return jsonify(response), 200


@delivery_staff_bp.route('/api/delivery-staff/order/<int:order_id>/seller/<int:seller_id>/items', methods=['GET'])
@jwt_required()
def get_seller_products(order_id, seller_id):

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)

    cur.execute("""
    SELECT
        p.prod_name,
        oi.quantity,
        oi.price
    FROM order_items oi
    JOIN product p ON p.prod_id = oi.prod_id
    JOIN product_seller ps ON ps.prod_id = oi.prod_id
    WHERE oi.order_id = %s
    AND ps.seller_id = %s
    """, (order_id, seller_id))

    items = cur.fetchall()

    cur.close()
    conn.close()

    return jsonify({
        "items": items
    }), 200

@delivery_staff_bp.route('/api/delivery-staff/order/<int:order_id>', methods=['GET'])
@jwt_required()
def get_single_order(order_id):
    try:
        if not _is_delivery_staff():
            return jsonify({"message": "Access denied. Delivery staff only."}), 403

        staff_id = get_jwt_identity()
        conn = get_db_connection()
        cur = conn.cursor(dictionary=True)

        payment_exists = _table_exists(cur, 'payment')
        payment_join = """
            LEFT JOIN payment p ON p.order_id = o.order_id
        """ if payment_exists else """"""
        payment_cols = """
            p.transaction_id,
            p.amount AS payment_amount,
            p.payment_date,
        """ if payment_exists else """
            NULL AS transaction_id,
            NULL AS payment_amount,
            NULL AS payment_date,
        """

        cur.execute(f"""
            SELECT
                o.*,
                u.user_name,
                u.user_mobile,
                u.user_address,
                s.seller_name,
                s.seller_mobile,
                s.shop_name,
                s.shop_address,
                {payment_cols}
                d.delivery_staff_name
            FROM orders o
            LEFT JOIN user u ON u.user_id = o.user_id
            LEFT JOIN seller s ON s.seller_id = o.seller_id
            LEFT JOIN delivery_staff d ON d.delivery_staff_id = o.delivery_staff_id
            {payment_join}
            WHERE o.order_id = %s
            LIMIT 1
        """, (order_id,))

        order = cur.fetchone()

        cur.close()
        conn.close()

        if not order:
            return jsonify({"message": "Order not found"}), 404
        if str(order.get('delivery_staff_id') or '') != str(staff_id):
            return jsonify({"message": "This order is not assigned to you"}), 403

        order['earning_amount'] = _earning_amount(order) if order.get('delivery_status') == 'Delivered' else _earning_amount(order)
        if order.get('payment_amount') is not None:
            order['payment_amount'] = _safe_float(order.get('payment_amount'))
        return jsonify(order), 200

    except Exception as e:
        print("ERROR:", e)
        return jsonify({"message": "Error fetching order"}), 500
    
@delivery_staff_bp.route('/api/delivery-staff/order/<int:order_id>/accept', methods=['PUT'])
@jwt_required()
def accept_order(order_id):
    if not _is_delivery_staff():
        return jsonify({"message": "Access denied"}), 403

    staff_id = get_jwt_identity()

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)

    try:
        # ✅ STEP 1: COUNT ACTIVE ORDERS
        cur.execute("""
            SELECT COUNT(*) AS total
            FROM orders
            WHERE delivery_staff_id = %s
            AND delivery_status IN ('Assigned', 'Picked Up', 'Out For Delivery')
        """, (staff_id,))

        active_orders = cur.fetchone()["total"]

        # ❗ LIMIT CHECK (MAX 3)
        if active_orders >= 3:
            return jsonify({
                "message": "You can only handle 3 active orders at a time"
            }), 400

        # ✅ STEP 2: CHECK ORDER IS STILL AVAILABLE
        cur.execute("""
            SELECT delivery_staff_id
            FROM orders
            WHERE order_id = %s
        """, (order_id,))

        order = cur.fetchone()

        if not order:
            return jsonify({"message": "Order not found"}), 404

        if order["delivery_staff_id"] is not None:
            return jsonify({"message": "Order already accepted"}), 400

        # ✅ STEP 3: ASSIGN ORDER
        write_cur = conn.cursor()

        write_cur.execute("""
            UPDATE orders
            SET delivery_staff_id = %s,
                delivery_status = 'Assigned',
                assigned_at = NOW()
            WHERE order_id = %s
        """, (staff_id, order_id))

        write_cur.execute("""
            UPDATE payment
            SET delivery_staff_id = %s
            WHERE order_id = %s
        """, (staff_id, order_id))

        _sync_delivery_table(conn, order_id, status="Assigned", staff_id=staff_id, delivery_date=datetime.now())
        conn.commit()

        return jsonify({"message": "Order accepted successfully"}), 200

    except Exception as e:
        conn.rollback()
        print("ERROR:", e)
        return jsonify({"message": "Something went wrong"}), 500

    finally:
        cur.close()
        conn.close()
        
@delivery_staff_bp.route('/api/delivery-staff/order/<int:order_id>/picked-up', methods=['PUT'])
@jwt_required()
def mark_picked_up(order_id):
    if not _is_delivery_staff():
        return jsonify({"message": "Access denied. Delivery staff only."}), 403

    staff_id = get_jwt_identity()

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)

    cur.execute("""
        SELECT order_id, delivery_staff_id, delivery_status, notes
        FROM orders
        WHERE order_id = %s
        LIMIT 1
    """, (order_id,))
    order = cur.fetchone()

    if not order:
        cur.close()
        conn.close()
        return jsonify({"message": "Order not found"}), 404

    if str(order.get("delivery_staff_id")) != str(staff_id):
        cur.close()
        conn.close()
        return jsonify({"message": "This order is not assigned to you"}), 403

    if order.get("delivery_status") not in ("Assigned",):
        cur.close()
        conn.close()
        return jsonify({"message": "Only assigned orders can be marked picked up"}), 400

    now = datetime.now()
    cur = conn.cursor()
    cur.execute("""
        UPDATE orders
        SET
            delivery_status = 'Picked Up',
            picked_at = %s
        WHERE order_id = %s
    """, (now, order_id))
    _sync_delivery_table(conn, order_id, status="Picked Up", staff_id=staff_id, delivery_date=now)
    conn.commit()

    cur.close()
    conn.close()

    return jsonify({"message": "Order marked as picked up"}), 200


@delivery_staff_bp.route('/api/delivery-staff/order/<int:order_id>/out-for-delivery', methods=['PUT'])
@jwt_required()
def mark_out_for_delivery(order_id):
    if not _is_delivery_staff():
        return jsonify({"message": "Access denied. Delivery staff only."}), 403

    staff_id = get_jwt_identity()

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)

    cur.execute("""
        SELECT order_id, delivery_staff_id, delivery_status, notes
        FROM orders
        WHERE order_id = %s
        LIMIT 1
    """, (order_id,))
    order = cur.fetchone()

    if not order:
        cur.close()
        conn.close()
        return jsonify({"message": "Order not found"}), 404

    if str(order.get("delivery_staff_id")) != str(staff_id):
        cur.close()
        conn.close()
        return jsonify({"message": "This order is not assigned to you"}), 403

    if order.get("delivery_status") not in ("Picked Up",):
        cur.close()
        conn.close()
        return jsonify({"message": "Only picked up orders can be marked out for delivery"}), 400

    now = datetime.now()
    cur = conn.cursor()
    cur.execute("""
        UPDATE orders
        SET
            delivery_status = 'Out For Delivery',
            out_for_delivery_at = %s
        WHERE order_id = %s
    """, (now, order_id))
    _sync_delivery_table(conn, order_id, status="Out For Delivery", staff_id=staff_id, delivery_date=now)
    conn.commit()

    cur.close()
    conn.close()

    return jsonify({"message": "Order marked as out for delivery"}), 200


@delivery_staff_bp.route('/api/delivery-staff/order/<int:order_id>/delivered', methods=['PUT'])
@jwt_required()
def mark_delivered(order_id):
    if not _is_delivery_staff():
        return jsonify({"message": "Access denied. Delivery staff only."}), 403

    staff_id = get_jwt_identity()

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)

    cur.execute("""
        SELECT order_id, delivery_staff_id, delivery_status, notes
        FROM orders
        WHERE order_id = %s
        LIMIT 1
    """, (order_id,))
    order = cur.fetchone()

    if not order:
        cur.close()
        conn.close()
        return jsonify({"message": "Order not found"}), 404

    if str(order.get("delivery_staff_id")) != str(staff_id):
        cur.close()
        conn.close()
        return jsonify({"message": "This order is not assigned to you"}), 403

    if order.get("delivery_status") not in ("Out For Delivery",):
        cur.close()
        conn.close()
        return jsonify({"message": "Only out for delivery orders can be marked delivered"}), 400

    now = datetime.now()
    cur = conn.cursor()
    cur.execute("""
        UPDATE orders
        SET
            delivery_status = 'Delivered',
            delivered_at = %s,
            order_status = 'Delivered',
            notes = %s
        WHERE order_id = %s
    """, (now, _clean_cod_payment_note(order.get("notes")), order_id))
    _sync_delivery_table(conn, order_id, status="Delivered", staff_id=staff_id, delivery_date=now)
    conn.commit()

    cur.close()
    conn.close()

    return jsonify({"message": "Order marked as delivered"}), 200


@delivery_staff_bp.route('/api/delivery-staff/order/<int:order_id>/payment-status', methods=['PUT'])
@jwt_required()
def update_cod_payment_status(order_id):
    if not _is_delivery_staff():
        return jsonify({"message": "Access denied. Delivery staff only."}), 403

    staff_id = get_jwt_identity()
    body = request.get_json(silent=True) or {}
    new_status = str(body.get("payment_status", "")).strip()

    allowed = ["Paid", "Pending", "Failed"]
    if new_status not in allowed:
        return jsonify({"message": f"Invalid payment status. Allowed: {allowed}"}), 400

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)
    cur.execute("""
        SELECT
            order_id,
            seller_id,
            delivery_staff_id,
            payment_method,
            payment_status,
            delivery_status,
            notes
        FROM orders
        WHERE order_id = %s
        LIMIT 1
    """, (order_id,))
    order = cur.fetchone()

    if not order:
        cur.close()
        conn.close()
        return jsonify({"message": "Order not found"}), 404

    if str(order.get("delivery_staff_id")) != str(staff_id):
        cur.close()
        conn.close()
        return jsonify({"message": "This order is not assigned to you"}), 403

    if str(order.get("payment_method") or "").upper() != "COD":
        cur.close()
        conn.close()
        return jsonify({"message": "Only COD orders can be updated by delivery staff"}), 400

    if order.get("delivery_status") != "Delivered":
        cur.close()
        conn.close()
        return jsonify({"message": "COD payment can be updated only after order is delivered"}), 400

    final_notes = _clean_cod_payment_note(order.get("notes"))

    write_cur = conn.cursor()
    write_cur.execute(
        "UPDATE orders SET payment_status = %s, notes = %s WHERE order_id = %s",
        (new_status, final_notes, order_id),
    )
    _sync_delivery_table(conn, order_id)
    conn.commit()

    write_cur.close()
    cur.close()
    conn.close()

    return jsonify({
        "message": f"COD payment marked as {new_status}",
        "order_id": order_id,
        "payment_status": new_status,
        "seller_id": order.get("seller_id"),
    }), 200

@delivery_staff_bp.route('/api/delivery-staff/reviews/order/<int:order_id>', methods=['GET'])
@jwt_required()
def get_delivery_staff_review_for_order(order_id):
    if not _is_user_role():
        return jsonify({"message": "Access denied. User only."}), 403

    user_id = _current_identity_int()
    if user_id is None:
        return jsonify({"message": "Invalid user identity"}), 401

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)
    try:
        order_row = _fetch_delivery_rating_order(cur, order_id)
        if not order_row:
            return jsonify({"message": "Order not found"}), 404
        if int(order_row.get('user_id') or 0) != user_id:
            return jsonify({"message": "Access denied"}), 403

        review_row = _fetch_delivery_review(cur, order_id)
        return jsonify(_delivery_review_payload(order_row, review_row)), 200
    finally:
        cur.close()
        conn.close()


@delivery_staff_bp.route('/api/delivery-staff/reviews/order/<int:order_id>', methods=['POST', 'PUT'])
@jwt_required()
def save_delivery_staff_review_for_order(order_id):
    if not _is_user_role():
        return jsonify({"message": "Access denied. User only."}), 403

    user_id = _current_identity_int()
    if user_id is None:
        return jsonify({"message": "Invalid user identity"}), 401

    body = request.get_json(silent=True) or {}
    action = str(body.get('action') or 'review').strip().lower()

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)
    write_cur = conn.cursor()
    try:
        order_row = _fetch_delivery_rating_order(cur, order_id)
        if not order_row:
            return jsonify({"message": "Order not found"}), 404
        if int(order_row.get('user_id') or 0) != user_id:
            return jsonify({"message": "Access denied"}), 403
        if not order_row.get('delivery_staff_id'):
            return jsonify({"message": "Delivery partner not assigned for this order"}), 400
        if not _is_delivered_status(order_row):
            return jsonify({"message": "You can rate delivery only after delivery is completed"}), 400

        _ensure_delivery_staff_reviews_table(cur)
        existing = _fetch_delivery_review(cur, order_id)

        if action == 'skip':
            if existing:
                write_cur.execute(
                    """
                    UPDATE delivery_staff_reviews
                    SET rating = NULL, review = NULL, review_tags = NULL, is_skipped = 1, skipped_at = NOW()
                    WHERE order_id = %s
                    """,
                    (order_id,),
                )
            else:
                write_cur.execute(
                    """
                    INSERT INTO delivery_staff_reviews (order_id, user_id, delivery_staff_id, is_skipped, skipped_at)
                    VALUES (%s, %s, %s, 1, NOW())
                    """,
                    (order_id, user_id, order_row.get('delivery_staff_id')),
                )
            conn.commit()
            review_row = _fetch_delivery_review(cur, order_id)
            return jsonify({
                "message": "Delivery rating skipped.",
                **_delivery_review_payload(order_row, review_row),
            }), 200

        rating = body.get('rating')
        try:
            rating = int(rating)
        except Exception:
            rating = 0
        if rating < 1 or rating > 5:
            return jsonify({"message": "Please select a rating between 1 and 5"}), 400

        review_text = str(body.get('review') or '').strip()
        tags = body.get('review_tags')
        if not isinstance(tags, list):
            tags = []
        tags = [str(tag).strip() for tag in tags if str(tag).strip()][:6]
        tags_json = json.dumps(tags, ensure_ascii=False) if tags else None

        if existing:
            write_cur.execute(
                """
                UPDATE delivery_staff_reviews
                SET rating = %s, review = %s, review_tags = %s, is_skipped = 0, skipped_at = NULL
                WHERE order_id = %s
                """,
                (rating, review_text, tags_json, order_id),
            )
        else:
            write_cur.execute(
                """
                INSERT INTO delivery_staff_reviews (order_id, user_id, delivery_staff_id, rating, review, review_tags, is_skipped)
                VALUES (%s, %s, %s, %s, %s, %s, 0)
                """,
                (order_id, user_id, order_row.get('delivery_staff_id'), rating, review_text, tags_json),
            )
        conn.commit()

        review_row = _fetch_delivery_review(cur, order_id)
        return jsonify({
            "message": "Delivery review saved successfully.",
            **_delivery_review_payload(order_row, review_row),
        }), 200
    finally:
        write_cur.close()
        cur.close()
        conn.close()


@delivery_staff_bp.route('/api/delivery-staff/my-ratings', methods=['GET'])
@jwt_required()
def get_my_delivery_staff_ratings():
    if not _is_delivery_staff():
        return jsonify({"message": "Access denied. Delivery staff only."}), 403

    staff_id = _current_identity_int()
    if staff_id is None:
        return jsonify({"message": "Invalid delivery staff identity"}), 401

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)
    try:
        _ensure_delivery_staff_reviews_table(cur)
        cur.execute(
            """
            SELECT
                r.delivery_review_id,
                r.order_id,
                r.user_id,
                COALESCE(u.user_name, CONCAT('User #', r.user_id)) AS user_name,
                r.rating,
                r.review,
                r.review_tags,
                r.is_skipped,
                r.created_at,
                r.updated_at
            FROM delivery_staff_reviews r
            LEFT JOIN user u ON u.user_id = r.user_id
            WHERE r.delivery_staff_id = %s
              AND r.is_skipped = 0
              AND r.rating IS NOT NULL
            ORDER BY r.updated_at DESC, r.created_at DESC
            """,
            (staff_id,),
        )
        ratings = cur.fetchall() or []

        for row in ratings:
            if row.get('review_tags'):
                try:
                    row['review_tags'] = json.loads(row['review_tags'])
                except Exception:
                    row['review_tags'] = []
            else:
                row['review_tags'] = []
            if isinstance(row.get('rating'), Decimal):
                row['rating'] = int(row['rating'])

        cur.execute(
            """
            SELECT AVG(rating) AS average_rating
            FROM delivery_staff_reviews
            WHERE delivery_staff_id = %s
              AND is_skipped = 0
              AND rating IS NOT NULL
            """,
            (staff_id,),
        )
        avg_row = cur.fetchone() or {}
        average_rating = avg_row.get('average_rating') or 0
        if isinstance(average_rating, Decimal):
            average_rating = float(average_rating)

        return jsonify({
            'average_rating': float(average_rating or 0),
            'ratings': ratings,
        }), 200
    finally:
        cur.close()
        conn.close()


@delivery_staff_bp.route('/api/delivery-staff/ratings', methods=['GET'])
@jwt_required()
def get_delivery_staff_ratings_alias():
    return get_my_delivery_staff_ratings()
