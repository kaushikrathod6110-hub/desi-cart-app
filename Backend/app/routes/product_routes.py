from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required, get_jwt
from db import get_db_connection
from decimal import Decimal
from datetime import datetime, date

product_bp = Blueprint("product_bp", __name__)


def _is_admin():
    claims = get_jwt()
    return claims.get("role") == "admin"


def _to_json_safe(val):
    """Convert Decimal / datetime / date into JSON friendly types."""
    if isinstance(val, Decimal):
        # keep as float (or you can return str(val) if you want exact)
        return float(val)
    if isinstance(val, (datetime, date)):
        return val.isoformat()
    return val


def _serialize_row(row: dict):
    """Convert any non-JSON-safe values in dict."""
    if not isinstance(row, dict):
        return row
    out = {}
    for k, v in row.items():
        out[k] = _to_json_safe(v)
    return out


# ------------------- STATS -------------------
@product_bp.route("/api/admin/products/stats", methods=["GET"])
@jwt_required()
def products_stats():
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)

    cur.execute("""
        SELECT
            COUNT(*) AS total,

            SUM(prod_status='Active' AND stock_status='Available') AS active_available,
            SUM(prod_status='Active' AND stock_status='Out of Stock') AS active_out,

            SUM(prod_status='Inactive' AND stock_status='Available') AS inactive_available,
            SUM(prod_status='Inactive' AND stock_status='Out of Stock') AS inactive_out,

            SUM(
                expiry_at IS NOT NULL
                AND expiry_at >= NOW()
                AND expiry_at <= DATE_ADD(NOW(), INTERVAL 7 DAY)
            ) AS expiring_7d
        FROM product
    """)

    stats = cur.fetchone() or {}

    cur.close()
    conn.close()

    # Make sure null -> 0 and all ints
    keys = ["total", "active_available", "active_out", "inactive_available", "inactive_out", "expiring_7d"]
    for k in keys:
        stats[k] = int(stats.get(k) or 0)

    return jsonify(stats), 200


# ------------------- LIST ALL PRODUCTS -------------------
@product_bp.route("/api/admin/products", methods=["GET"])
@jwt_required()
def get_all_products():
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    filter_type = (request.args.get("filter") or "").strip().lower()

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)

    conditions = []

    if filter_type == "out_of_stock":
        conditions.append("p.stock_status = 'Out of Stock'")
    elif filter_type == "expiring":
        conditions.append("""
            p.expiry_at IS NOT NULL
            AND p.expiry_at >= NOW()
            AND p.expiry_at <= DATE_ADD(NOW(), INTERVAL 7 DAY)
        """)

    where_sql = f" WHERE {' AND '.join(conditions)}" if conditions else ""

    try:
        cur.execute(f"""
            SELECT
                p.*,
                c.category_name,
                ps_map.seller_id,
                s.seller_name,
                COALESCE(rv.avg_rating, 0) AS avg_rating,
                COALESCE(rv.review_count, 0) AS review_count
            FROM product p
            LEFT JOIN category c ON c.category_id = p.category_id
            LEFT JOIN (
                SELECT prod_id, MIN(seller_id) AS seller_id
                FROM product_seller
                GROUP BY prod_id
            ) ps_map ON ps_map.prod_id = p.prod_id
            LEFT JOIN seller s ON s.seller_id = ps_map.seller_id
            LEFT JOIN (
                SELECT prod_id,
                       ROUND(AVG(rating), 1) AS avg_rating,
                       COUNT(*) AS review_count
                FROM product_reviews
                GROUP BY prod_id
            ) rv ON rv.prod_id = p.prod_id
            {where_sql}
            ORDER BY p.prod_id DESC
        """)
        rows = cur.fetchall()

    except Exception:
        try:
            cur.execute(f"""
                SELECT
                    p.*,
                    c.category_name,
                    ps_map.seller_id,
                    COALESCE(rv.avg_rating, 0) AS avg_rating,
                    COALESCE(rv.review_count, 0) AS review_count
                FROM product p
                LEFT JOIN category c ON c.category_id = p.category_id
                LEFT JOIN (
                    SELECT prod_id, MIN(seller_id) AS seller_id
                    FROM product_seller
                    GROUP BY prod_id
                ) ps_map ON ps_map.prod_id = p.prod_id
                LEFT JOIN (
                    SELECT prod_id,
                           ROUND(AVG(rating), 1) AS avg_rating,
                           COUNT(*) AS review_count
                    FROM product_reviews
                    GROUP BY prod_id
                ) rv ON rv.prod_id = p.prod_id
                {where_sql}
                ORDER BY p.prod_id DESC
            """)
            rows = cur.fetchall()
        except Exception:
            simple_where = ""
            if filter_type == "out_of_stock":
                simple_where = " WHERE stock_status = 'Out of Stock'"
            elif filter_type == "expiring":
                simple_where = """
                 WHERE expiry_at IS NOT NULL
                   AND expiry_at >= NOW()
                   AND expiry_at <= DATE_ADD(NOW(), INTERVAL 7 DAY)
                """
            cur.execute(f"SELECT * FROM product{simple_where} ORDER BY prod_id DESC")
            rows = cur.fetchall()

    cur.close()
    conn.close()

    data = []
    for r in rows:
        r = _serialize_row(r)

        if r.get("seller_id") is None:
            r["seller_id"] = None

        if not r.get("prod_status"):
            r["prod_status"] = "Active"
        if not r.get("stock_status"):
            r["stock_status"] = "Available"
        r["avg_rating"] = float(r.get("avg_rating") or 0)
        r["review_count"] = int(r.get("review_count") or 0)

        data.append(r)

    return jsonify(data), 200



# ------------------- GET SINGLE PRODUCT -------------------
@product_bp.route("/api/admin/products/<int:prod_id>", methods=["GET"])
@jwt_required()
def get_single_product(prod_id):
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)

    try:
        row = None

        try:
            cur.execute(
                """
                SELECT
                    p.*,
                    c.category_name,
                    ps_map.seller_id,
                    s.seller_name,
                    COALESCE(rv.avg_rating, 0) AS avg_rating,
                    COALESCE(rv.review_count, 0) AS review_count
                FROM product p
                LEFT JOIN category c ON c.category_id = p.category_id
                LEFT JOIN (
                    SELECT prod_id, MIN(seller_id) AS seller_id
                    FROM product_seller
                    GROUP BY prod_id
                ) ps_map ON ps_map.prod_id = p.prod_id
                LEFT JOIN seller s ON s.seller_id = ps_map.seller_id
                LEFT JOIN (
                    SELECT prod_id,
                           ROUND(AVG(rating), 1) AS avg_rating,
                           COUNT(*) AS review_count
                    FROM product_reviews
                    GROUP BY prod_id
                ) rv ON rv.prod_id = p.prod_id
                WHERE p.prod_id = %s
                LIMIT 1
                """,
                (prod_id,),
            )
            row = cur.fetchone()
        except Exception:
            try:
                cur.execute(
                    """
                    SELECT
                        p.*,
                        c.category_name,
                        ps_map.seller_id,
                        COALESCE(rv.avg_rating, 0) AS avg_rating,
                        COALESCE(rv.review_count, 0) AS review_count
                    FROM product p
                    LEFT JOIN category c ON c.category_id = p.category_id
                    LEFT JOIN (
                        SELECT prod_id, MIN(seller_id) AS seller_id
                        FROM product_seller
                        GROUP BY prod_id
                    ) ps_map ON ps_map.prod_id = p.prod_id
                    LEFT JOIN (
                        SELECT prod_id,
                               ROUND(AVG(rating), 1) AS avg_rating,
                               COUNT(*) AS review_count
                        FROM product_reviews
                        GROUP BY prod_id
                    ) rv ON rv.prod_id = p.prod_id
                    WHERE p.prod_id = %s
                    LIMIT 1
                    """,
                    (prod_id,),
                )
                row = cur.fetchone()
            except Exception:
                cur.execute("SELECT * FROM product WHERE prod_id = %s LIMIT 1", (prod_id,))
                row = cur.fetchone()

        if not row:
            return jsonify({"error": "Product not found"}), 404

        row = _serialize_row(row)
        if row.get("seller_id") is None:
            row["seller_id"] = None
        if not row.get("prod_status"):
            row["prod_status"] = "Active"
        if not row.get("stock_status"):
            row["stock_status"] = "Available"
        row["avg_rating"] = float(row.get("avg_rating") or 0)
        row["review_count"] = int(row.get("review_count") or 0)
        if "seller_name" not in row or row.get("seller_name") in [None, ""]:
            row["seller_name"] = "—"
        if "category_name" not in row or row.get("category_name") in [None, ""]:
            row["category_name"] = "—"

        return jsonify(row), 200
    finally:
        cur.close()
        conn.close()


# ------------------- UPDATE PRODUCT STATUS (Active/Inactive) -------------------
@product_bp.route("/api/admin/products/<int:prod_id>/status", methods=["PUT"])
@jwt_required()
def update_product_status(prod_id):
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    body = request.get_json(silent=True) or {}
    new_status = str(body.get("prod_status", "")).strip()

    if new_status not in ["Active", "Inactive"]:
        return jsonify({"error": "Invalid prod_status. Use 'Active' or 'Inactive'."}), 400

    conn = get_db_connection()
    cur = conn.cursor()

    cur.execute("UPDATE product SET prod_status=%s WHERE prod_id=%s", (new_status, prod_id))
    conn.commit()

    affected = cur.rowcount
    cur.close()
    conn.close()

    if affected == 0:
        return jsonify({"error": "Product not found"}), 404

    return jsonify({"message": "Product status updated", "prod_id": prod_id, "prod_status": new_status}), 200