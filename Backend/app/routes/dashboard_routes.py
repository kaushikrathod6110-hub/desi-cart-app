from flask import Blueprint, jsonify
from flask_jwt_extended import jwt_required, get_jwt
from db import get_db_connection
from decimal import Decimal
from datetime import datetime, date

dashboard_bp = Blueprint("dashboard_bp", __name__)

def _is_admin():
    claims = get_jwt()
    return claims.get("role") == "admin"

def _to_json_safe(val):
    if isinstance(val, Decimal):
        return float(val)
    if isinstance(val, (datetime, date)):
        return val.isoformat()
    return val


@dashboard_bp.route("/api/admin/dashboard/summary", methods=["GET"])
@jwt_required()
def admin_dashboard_summary():
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)

    # ---- Total counts ----
    cur.execute("SELECT COUNT(*) AS total_users FROM user")
    total_users = int((cur.fetchone() or {}).get("total_users") or 0)

    cur.execute("SELECT COUNT(*) AS total_sellers FROM seller")
    total_sellers = int((cur.fetchone() or {}).get("total_sellers") or 0)

    cur.execute("SELECT COUNT(*) AS total_products FROM product")
    total_products = int((cur.fetchone() or {}).get("total_products") or 0)

    cur.execute("SELECT COUNT(*) AS total_orders FROM orders")
    total_orders = int((cur.fetchone() or {}).get("total_orders") or 0)

    cur.execute("SELECT COUNT(*) AS total_delivery_staff FROM delivery_staff")
    total_delivery_staff = int((cur.fetchone() or {}).get("total_delivery_staff") or 0)

    # ---- Today orders + today revenue ----
    cur.execute("""
        SELECT
            COUNT(*) AS today_orders,
            COALESCE(SUM(CASE WHEN payment_status = 'Paid' THEN total_amount ELSE 0 END), 0) AS today_revenue
        FROM orders
        WHERE DATE(order_date) = CURDATE()
    """)
    row = cur.fetchone() or {}
    today_orders = int(row.get("today_orders") or 0)
    today_revenue = _to_json_safe(row.get("today_revenue") or 0)

    # ---- Alerts ----
    cur.execute("""
        SELECT COUNT(*) AS out_of_stock
        FROM product
        WHERE prod_status='Active' AND stock_status='Out of Stock'
    """)
    out_of_stock = int((cur.fetchone() or {}).get("out_of_stock") or 0)

    cur.execute("""
        SELECT COUNT(*) AS expiring_7d
        FROM product
        WHERE prod_status='Active'
          AND expiry_at IS NOT NULL
          AND expiry_at >= NOW()
          AND expiry_at <= DATE_ADD(NOW(), INTERVAL 7 DAY)
    """)
    expiring_7d = int((cur.fetchone() or {}).get("expiring_7d") or 0)

    # ---- Recent orders (last 5) ----
    cur.execute("""
        SELECT order_id, seller_id, user_id, order_date, total_amount,
               payment_method, payment_status, order_status
        FROM orders
        ORDER BY order_id DESC
        LIMIT 5
    """)
    recent_orders = cur.fetchall() or []
    for r in recent_orders:
        for k in list(r.keys()):
            r[k] = _to_json_safe(r[k])

    cur.close()
    conn.close()

    return jsonify({
        "counts": {
            "total_users": total_users,
            "total_sellers": total_sellers,
            "total_products": total_products,
            "total_orders": total_orders,
            "total_delivery_staff": total_delivery_staff,
            "today_orders": today_orders,
            "today_revenue": today_revenue
        },
        "alerts": {
            "out_of_stock": out_of_stock,
            "expiring_7d": expiring_7d
        },
        "recent_orders": recent_orders
    }), 200