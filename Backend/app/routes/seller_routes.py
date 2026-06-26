import os
import uuid
from decimal import Decimal
from datetime import datetime, date, timedelta

from flask import Blueprint, jsonify, request, current_app, send_from_directory
from flask_jwt_extended import jwt_required, get_jwt, get_jwt_identity
from werkzeug.utils import secure_filename

from db import get_db_connection


seller_bp = Blueprint("seller_bp", __name__, url_prefix="/api/seller")

ALLOWED_IMAGE_EXTENSIONS = {"png", "jpg", "jpeg", "webp"}
STORE_LOGO_FOLDER = os.path.join("uploads", "store_logo")
PRODUCT_IMAGE_FOLDER = os.path.join("uploads", "products")


# ======================================================
# Helpers
# ======================================================
def _is_seller():
    return str(get_jwt().get("role", "")).lower() == "seller"


def _seller_identity_int():
    try:
        return int(get_jwt_identity())
    except Exception:
        return None


def _to_json_safe(val):
    if isinstance(val, Decimal):
        return float(val)
    if isinstance(val, (datetime, date)):
        return val.isoformat()
    return val


def _serialize_row(row):
    if not isinstance(row, dict):
        return row
    return {k: _to_json_safe(v) for k, v in row.items()}


def _safe_int(v, default=0):
    try:
        return int(v)
    except Exception:
        return default


def _safe_float(v, default=0.0):
    try:
        return float(v)
    except Exception:
        return default


def _allowed_file(filename):
    return "." in filename and filename.rsplit(".", 1)[1].lower() in ALLOWED_IMAGE_EXTENSIONS


def _ensure_upload_dir(relative_path):
    path = os.path.join(current_app.root_path, relative_path)
    os.makedirs(path, exist_ok=True)
    return path


def _build_store_logo_url(filename):
    if not filename:
        return None
    base = request.host_url.rstrip("/")
    return f"{base}/api/seller/logo/{filename}"


def _build_product_image_url(filename):
    if not filename:
        return None
    clean = str(filename).replace("\\", "/").strip()
    if not clean:
        return None
    if clean.startswith("http://") or clean.startswith("https://"):
        return clean
    if clean.startswith("uploads/"):
        clean = clean[len("uploads/"):]
    base = request.host_url.rstrip("/")
    return f"{base}/uploads/{clean}"


def _save_uploaded_image(file_storage, folder_relative_path, prefix):
    if file_storage is None or not getattr(file_storage, "filename", ""):
        return None
    if not _allowed_file(file_storage.filename):
        raise ValueError("Only png, jpg, jpeg and webp images are allowed")

    upload_dir = _ensure_upload_dir(folder_relative_path)
    original_name = secure_filename(file_storage.filename)
    ext = original_name.rsplit(".", 1)[1].lower()
    final_name = f"{prefix}_{uuid.uuid4().hex}.{ext}"
    save_path = os.path.join(upload_dir, final_name)
    file_storage.save(save_path)
    return f"{folder_relative_path.replace('\\', '/')}/{final_name}".replace("\\", "/")


def _table_exists(cur, table_name):
    cur.execute("SHOW TABLES LIKE %s", (table_name,))
    return cur.fetchone() is not None


def _column_exists(cur, table_name, column_name):
    cur.execute(f"SHOW COLUMNS FROM `{table_name}` LIKE %s", (column_name,))
    return cur.fetchone() is not None


def _first_existing_column(cur, table_name, candidates):
    for col in candidates:
        if _column_exists(cur, table_name, col):
            return col
    return None


def _current_product_columns(cur):
    cols = [
        "prod_id",
        "prod_name",
        "category_id",
        "brand",
        "description",
        "prod_price",
        "unit_type",
        "stock_quantity",
        "stock_status",
        "prod_image",
        "prod_image2",
        "prod_image3",
        "expiry_at",
        "prod_status",
    ]
    return [c for c in cols if _column_exists(cur, "product", c)]


def _fetch_seller_profile_row(cur, seller_id):
    cur.execute(
        """
        SELECT
            seller_id,
            seller_name,
            seller_email,
            seller_mobile,
            shop_address,
            shop_name,
            store_logo,
            registration_date,
            pincode,
            licence_no,
            status,
            updated_at
        FROM seller
        WHERE seller_id = %s
        LIMIT 1
        """,
        (seller_id,),
    )
    seller = cur.fetchone()
    if not seller:
        return None

    seller["seller_mobile"] = "" if seller.get("seller_mobile") is None else str(seller["seller_mobile"])
    seller["pincode"] = "" if seller.get("pincode") is None else str(seller["pincode"])
    seller["store_logo"] = seller.get("store_logo") or ""
    seller["store_logo_url"] = _build_store_logo_url(seller.get("store_logo"))
    return seller


def _format_seller_order(order):
    order_date = order.get("order_date")
    formatted_date = ""
    formatted_time = ""
    if isinstance(order_date, datetime):
        formatted_date = order_date.strftime("%d %b %Y")
        formatted_time = order_date.strftime("%I:%M %p")

    return {
        "order_id": order.get("order_id"),
        "seller_id": order.get("seller_id"),
        "cart_id": order.get("cart_id"),
        "user_id": order.get("user_id"),
        "delivery_staff_id": order.get("delivery_staff_id"),
        "order_date": order_date.strftime("%Y-%m-%d %H:%M:%S") if isinstance(order_date, datetime) else "",
        "total_amount": _safe_float(order.get("total_amount")),
        "payment_method": order.get("payment_method") or "",
        "payment_status": order.get("payment_status") or "",
        "order_status": order.get("order_status") or "",
        "delivery_status": order.get("delivery_status") or "",
        "delivery_address": order.get("delivery_address") or "",
        "pincode": "" if order.get("pincode") is None else str(order.get("pincode")),
        "notes": order.get("notes") or "",
        "orderId": f"#ORD{order.get('order_id')}",
        "customer": f"Cart #{order.get('cart_id')}",
        "date": formatted_date,
        "time": formatted_time,
        "amount": _safe_float(order.get("total_amount")),
        "status": order.get("order_status") or "",
        "payment": order.get("payment_status") or "",
    }


# ======================================================
# Seller Dashboard
# ======================================================
@seller_bp.route("/dashboard", methods=["GET"])
@jwt_required()
def seller_dashboard():
    if not _is_seller():
        return jsonify({"message": "Access denied. Seller only."}), 403

    seller_id = _seller_identity_int()
    if seller_id is None:
        return jsonify({"message": "Invalid seller identity"}), 401

    conn = None
    cur = None
    try:
        conn = get_db_connection()
        cur = conn.cursor(dictionary=True)

        seller = _fetch_seller_profile_row(cur, seller_id)
        if not seller:
            return jsonify({"success": False, "message": "Seller not found"}), 404

        cur.execute(
            """
            SELECT
                COUNT(DISTINCT ps.prod_id) AS total_products,
                SUM(CASE WHEN ps.stock_qty > 0 AND ps.stock_qty <= 5 AND ps.ps_status = 'Active' THEN 1 ELSE 0 END) AS low_stock_products,
                SUM(CASE WHEN (ps.stock_qty <= 0 OR p.stock_status = 'Out of Stock') AND ps.ps_status = 'Active' THEN 1 ELSE 0 END) AS out_of_stock_products
            FROM product_seller ps
            LEFT JOIN product p ON p.prod_id = ps.prod_id
            WHERE ps.seller_id = %s
            """,
            (seller_id,),
        )
        product_summary = cur.fetchone() or {}

        cur.execute(
            """
            SELECT
                COUNT(*) AS total_orders,
                SUM(CASE WHEN order_status = 'Pending' THEN 1 ELSE 0 END) AS new_orders,
                SUM(CASE WHEN order_status = 'Pending' THEN 1 ELSE 0 END) AS pending_orders,
                SUM(CASE WHEN order_status = 'Delivered' THEN 1 ELSE 0 END) AS delivered_orders
            FROM orders
            WHERE seller_id = %s
            """,
            (seller_id,),
        )
        order_summary = cur.fetchone() or {}

        cur.execute(
            """
            SELECT
                p.prod_id,
                p.prod_name,
                p.category_id,
                p.brand,
                p.description,
                COALESCE(ps.selling_price, p.prod_price) AS prod_price,
                p.unit_type,
                COALESCE(ps.stock_qty, p.stock_quantity) AS stock_quantity,
                CASE
                    WHEN COALESCE(ps.stock_qty, p.stock_quantity) <= 0 THEN 'Out of Stock'
                    ELSE 'Available'
                END AS stock_status,
                p.prod_image,
                p.prod_image2,
                p.prod_image3,
                p.expiry_at,
                COALESCE(ps.ps_status, p.prod_status) AS prod_status
            FROM product_seller ps
            LEFT JOIN product p ON p.prod_id = ps.prod_id
            WHERE ps.seller_id = %s
            ORDER BY p.prod_id DESC
            LIMIT 5
            """,
            (seller_id,),
        )
        recent_products = []
        for row in cur.fetchall() or []:
            row = _serialize_row(row)
            row["prod_image_url"] = _build_product_image_url(row.get("prod_image"))
            row["prod_image2_url"] = _build_product_image_url(row.get("prod_image2"))
            row["prod_image3_url"] = _build_product_image_url(row.get("prod_image3"))
            recent_products.append(row)

        cur.execute(
            """
            SELECT
                order_id,
                seller_id,
                cart_id,
                user_id,
                delivery_staff_id,
                order_date,
                total_amount,
                payment_method,
                payment_status,
                order_status,
                delivery_status,
                delivery_address,
                pincode,
                notes
            FROM orders
            WHERE seller_id = %s
            ORDER BY order_id DESC
            LIMIT 5
            """,
            (seller_id,),
        )
        recent_orders = [_format_seller_order(row) for row in (cur.fetchall() or [])]

        return jsonify({
            "success": True,
            "message": "Dashboard data fetched successfully",
            "seller": _serialize_row(seller),
            "summary": {
                "total_products": _safe_int(product_summary.get("total_products")),
                "total_orders": _safe_int(order_summary.get("total_orders")),
                "new_orders": _safe_int(order_summary.get("new_orders")),
                "pending_orders": _safe_int(order_summary.get("pending_orders")),
                "delivered_orders": _safe_int(order_summary.get("delivered_orders")),
                "low_stock_products": _safe_int(product_summary.get("low_stock_products")),
                "out_of_stock_products": _safe_int(product_summary.get("out_of_stock_products")),
            },
            "recent_products": recent_products,
            "recent_orders": recent_orders,
        }), 200

    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500
    finally:
        if cur:
            cur.close()
        if conn:
            conn.close()


# ======================================================
# Seller Profile
# ======================================================
@seller_bp.route("/profile", methods=["GET"])
@jwt_required()
def get_seller_profile():
    if not _is_seller():
        return jsonify({"message": "Access denied. Seller only."}), 403

    seller_id = _seller_identity_int()
    conn = None
    cur = None
    try:
        conn = get_db_connection()
        cur = conn.cursor(dictionary=True)
        seller = _fetch_seller_profile_row(cur, seller_id)
        if not seller:
            return jsonify({"success": False, "message": "Seller not found"}), 404

        return jsonify({"success": True, "seller": _serialize_row(seller)}), 200
    except Exception as e:
        return jsonify({"success": False, "message": f"Error fetching profile: {str(e)}"}), 500
    finally:
        if cur:
            cur.close()
        if conn:
            conn.close()


@seller_bp.route("/profile/update", methods=["PUT"])
@jwt_required()
def update_seller_profile():
    if not _is_seller():
        return jsonify({"message": "Access denied. Seller only."}), 403

    seller_id = _seller_identity_int()
    conn = None
    cur = None
    try:
        conn = get_db_connection()
        cur = conn.cursor(dictionary=True)

        existing = _fetch_seller_profile_row(cur, seller_id)
        if not existing:
            return jsonify({"success": False, "message": "Seller not found"}), 404

        is_multipart = request.content_type and "multipart/form-data" in request.content_type.lower()
        data = request.form if is_multipart else (request.get_json(silent=True) or {})

        seller_name = str(data.get("seller_name", existing.get("seller_name") or "")).strip()
        seller_email = str(data.get("seller_email", existing.get("seller_email") or "")).strip()
        seller_mobile = str(data.get("seller_mobile", existing.get("seller_mobile") or "")).strip()
        shop_name = str(data.get("shop_name", existing.get("shop_name") or "")).strip()
        shop_address = str(data.get("shop_address", existing.get("shop_address") or "")).strip()
        pincode = str(data.get("pincode", existing.get("pincode") or "")).strip()
        licence_no = str(data.get("licence_no", existing.get("licence_no") or "")).strip()
        remove_store_logo = str(data.get("remove_store_logo", "0")).strip() == "1"

        if not seller_name or not seller_email or not seller_mobile or not shop_name or not shop_address:
            return jsonify({"success": False, "message": "Seller name, email, mobile, shop name and shop address are required"}), 400

        store_logo = existing.get("store_logo") or None
        if remove_store_logo:
            store_logo = None

        logo_file = request.files.get("store_logo") if is_multipart else None
        if logo_file and getattr(logo_file, "filename", ""):
            store_logo = _save_uploaded_image(logo_file, STORE_LOGO_FOLDER, f"seller_{seller_id}")
            store_logo = os.path.basename(store_logo)

        write_cur = conn.cursor()
        write_cur.execute(
            """
            UPDATE seller
            SET
                seller_name = %s,
                seller_email = %s,
                seller_mobile = %s,
                shop_name = %s,
                shop_address = %s,
                pincode = %s,
                licence_no = %s,
                store_logo = %s,
                updated_at = NOW()
            WHERE seller_id = %s
            """,
            (
                seller_name,
                seller_email,
                seller_mobile,
                shop_name,
                shop_address,
                pincode if pincode != "" else None,
                licence_no if licence_no != "" else None,
                store_logo,
                seller_id,
            ),
        )
        conn.commit()
        write_cur.close()

        cur = conn.cursor(dictionary=True)
        updated = _fetch_seller_profile_row(cur, seller_id)
        return jsonify({
            "success": True,
            "message": "Seller profile updated successfully",
            "seller": _serialize_row(updated),
        }), 200

    except ValueError as e:
        return jsonify({"success": False, "message": str(e)}), 400
    except Exception as e:
        return jsonify({"success": False, "message": f"Error updating profile: {str(e)}"}), 500
    finally:
        if cur:
            cur.close()
        if conn:
            conn.close()


@seller_bp.route("/logo/<path:filename>", methods=["GET"])
def get_store_logo(filename):
    upload_folder = os.path.join(current_app.root_path, STORE_LOGO_FOLDER)
    return send_from_directory(upload_folder, filename)


# ======================================================
# Seller Feedback
# ======================================================
@seller_bp.route("/feedback", methods=["GET"])
@jwt_required()
def get_seller_feedback():
    if not _is_seller():
        return jsonify({"message": "Access denied. Seller only."}), 403

    seller_id = _seller_identity_int()
    if seller_id is None:
        return jsonify({"message": "Invalid seller identity"}), 401

    conn = None
    cur = None
    try:
        conn = get_db_connection()
        cur = conn.cursor(dictionary=True)

        feedback_rows = []

        if _table_exists(cur, "product_reviews"):
            review_product_col = _first_existing_column(cur, "product_reviews", ["prod_id", "product_id"])
            review_text_col = _first_existing_column(cur, "product_reviews", ["review", "comments", "comment"])
            review_date_col = _first_existing_column(cur, "product_reviews", ["created_at", "feedback_date", "updated_at"])
            review_rating_col = _first_existing_column(cur, "product_reviews", ["rating"])
            review_seller_col = _first_existing_column(cur, "product_reviews", ["seller_id"])

            if review_product_col and review_rating_col and review_seller_col:
                review_text_sql = f"pr.`{review_text_col}`" if review_text_col else "''"
                review_date_sql = f"pr.`{review_date_col}`" if review_date_col else "NULL"
                cur.execute(
                    f"""
                    SELECT
                        pr.review_id AS feedback_id,
                        pr.`{review_product_col}` AS prod_id,
                        p.prod_name AS product_name,
                        COALESCE(pr.`{review_rating_col}`, 0) AS rating,
                        COALESCE({review_text_sql}, '') AS comment,
                        {review_date_sql} AS created_at
                    FROM product_reviews pr
                    INNER JOIN product p ON p.prod_id = pr.`{review_product_col}`
                    WHERE pr.`{review_seller_col}` = %s
                    ORDER BY {review_date_sql} DESC, pr.review_id DESC
                    """,
                    (seller_id,),
                )
                feedback_rows = cur.fetchall() or []

        if not feedback_rows and _table_exists(cur, "feedback"):
            legacy_product_col = _first_existing_column(cur, "feedback", ["prod_id", "product_id"])
            legacy_order_col = _first_existing_column(cur, "feedback", ["oder_id", "order_id"])
            legacy_rating_col = _first_existing_column(cur, "feedback", ["rating"])
            legacy_comment_col = _first_existing_column(cur, "feedback", ["comments", "comment", "review"])
            legacy_date_col = _first_existing_column(cur, "feedback", ["feedback_date", "created_at", "updated_at"])

            if legacy_product_col and legacy_rating_col:
                legacy_comment_sql = f"f.`{legacy_comment_col}`" if legacy_comment_col else "''"
                legacy_date_sql = f"f.`{legacy_date_col}`" if legacy_date_col else "NULL"
                if legacy_order_col:
                    seller_filter_join = f"LEFT JOIN orders o ON o.order_id = f.`{legacy_order_col}`"
                    seller_filter_where = "o.seller_id = %s"
                else:
                    seller_filter_join = f"INNER JOIN product_seller ps ON ps.prod_id = f.`{legacy_product_col}`"
                    seller_filter_where = "ps.seller_id = %s"

                cur.execute(
                    f"""
                    SELECT
                        f.feedback_id AS feedback_id,
                        f.`{legacy_product_col}` AS prod_id,
                        p.prod_name AS product_name,
                        COALESCE(f.`{legacy_rating_col}`, 0) AS rating,
                        COALESCE({legacy_comment_sql}, '') AS comment,
                        {legacy_date_sql} AS created_at
                    FROM feedback f
                    INNER JOIN product p ON p.prod_id = f.`{legacy_product_col}`
                    {seller_filter_join}
                    WHERE {seller_filter_where}
                    ORDER BY {legacy_date_sql} DESC, f.feedback_id DESC
                    """,
                    (seller_id,),
                )
                feedback_rows = cur.fetchall() or []

        feedback = []
        for row in feedback_rows:
            row = _serialize_row(row)
            feedback.append({
                "feedback_id": row.get("feedback_id"),
                "prod_id": row.get("prod_id"),
                "product_name": row.get("product_name") or "Product",
                "rating": _safe_float(row.get("rating")),
                "comment": (row.get("comment") or "").strip(),
                "created_at": row.get("created_at") or "",
            })

        return jsonify({
            "success": True,
            "feedback": feedback,
        }), 200

    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500
    finally:
        if cur:
            cur.close()
        if conn:
            conn.close()


@seller_bp.route("/product/add", methods=["POST"])
@jwt_required()
def add_seller_product():
    if not _is_seller():
        return jsonify({"message": "Access denied. Seller only."}), 403

    seller_id = _seller_identity_int()
    conn = None
    meta_cur = None
    write_cur = None
    try:
        product_name = request.form.get("product_name", "").strip()
        category_id = request.form.get("category", "").strip()
        price = request.form.get("price", "").strip()
        quantity = request.form.get("quantity", "").strip()
        description = request.form.get("description", "").strip()
        brand = request.form.get("brand", "").strip() or "No Brand"
        unit_type = request.form.get("unit_type", "").strip() or request.form.get("unit", "").strip() or "pcs"
        expiry_at = request.form.get("expiry_at", "").strip()

        images = request.files.getlist("images")
        if not images:
            single = request.files.get("image")
            if single:
                images = [single]

        if not product_name:
            return jsonify({"success": False, "message": "Product name is required"}), 400
        if not category_id:
            return jsonify({"success": False, "message": "Category is required"}), 400
        if not price:
            return jsonify({"success": False, "message": "Price is required"}), 400
        if not quantity:
            return jsonify({"success": False, "message": "Quantity is required"}), 400
        if not description:
            return jsonify({"success": False, "message": "Description is required"}), 400

        category_id = _safe_int(category_id, None)
        if category_id is None:
            return jsonify({"success": False, "message": "Invalid category"}), 400

        price = _safe_float(price, None)
        quantity = _safe_float(quantity, None)
        if price is None or price < 0:
            return jsonify({"success": False, "message": "Invalid price"}), 400
        if quantity is None or quantity < 0:
            return jsonify({"success": False, "message": "Invalid quantity"}), 400

        stock_status = "Out of Stock" if quantity <= 0 else "Available"
        prod_status = "Active"

        saved_images = []
        for image in images[:3]:
            if image and getattr(image, "filename", ""):
                saved_images.append(_save_uploaded_image(image, PRODUCT_IMAGE_FOLDER, f"prod_{seller_id}"))

        prod_image = saved_images[0] if len(saved_images) > 0 else ""
        prod_image2 = saved_images[1] if len(saved_images) > 1 else None
        prod_image3 = saved_images[2] if len(saved_images) > 2 else None

        if expiry_at:
            try:
                expiry_value = datetime.fromisoformat(expiry_at)
            except Exception:
                try:
                    expiry_value = datetime.strptime(expiry_at, "%Y-%m-%d")
                except Exception:
                    return jsonify({"success": False, "message": "Invalid expiry_at format. Use YYYY-MM-DD or ISO datetime."}), 400
        else:
            expiry_value = datetime.now()

        conn = get_db_connection()
        meta_cur = conn.cursor(dictionary=True)

        meta_cur.execute("SELECT category_id FROM category WHERE category_id = %s LIMIT 1", (category_id,))
        if not meta_cur.fetchone():
            return jsonify({"success": False, "message": "Category not found"}), 404

        meta_cur.execute("SELECT COALESCE(MAX(prod_id), 0) AS max_prod_id FROM product")
        max_row = meta_cur.fetchone() or {}
        next_prod_id = _safe_int(max_row.get("max_prod_id")) + 1

        write_cur = conn.cursor()
        write_cur.execute(
            """
            INSERT INTO product (
                prod_id,
                prod_name,
                category_id,
                brand,
                description,
                prod_price,
                unit_type,
                stock_quantity,
                stock_status,
                prod_image,
                prod_image2,
                prod_image3,
                expiry_at,
                prod_status
            )
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            """,
            (
                next_prod_id,
                product_name,
                category_id,
                brand,
                description,
                price,
                unit_type,
                quantity,
                stock_status,
                prod_image,
                prod_image2,
                prod_image3,
                expiry_value,
                prod_status,
            ),
        )
        prod_id = next_prod_id

        write_cur.execute(
            """
            INSERT INTO product_seller (prod_id, seller_id, stock_qty, selling_price, ps_status)
            VALUES (%s, %s, %s, %s, %s)
            """,
            (prod_id, seller_id, quantity, price, "Active"),
        )

        conn.commit()
        return jsonify({
            "success": True,
            "message": "Product added successfully",
            "prod_id": prod_id,
        }), 201

    except ValueError as e:
        if conn:
            conn.rollback()
        return jsonify({"success": False, "message": str(e)}), 400
    except Exception as e:
        if conn:
            conn.rollback()
        return jsonify({"success": False, "message": str(e)}), 500
    finally:
        if meta_cur:
            meta_cur.close()
        if write_cur:
            write_cur.close()
        if conn:
            conn.close()


@seller_bp.route("/product/update/<int:prod_id>", methods=["PUT"])
@jwt_required()
def update_seller_product(prod_id):
    if not _is_seller():
        return jsonify({"message": "Access denied. Seller only."}), 403

    seller_id = _seller_identity_int()
    conn = None
    cur = None
    write_cur = None
    try:
        conn = get_db_connection()
        cur = conn.cursor(dictionary=True)
        cur.execute(
            """
            SELECT
                p.prod_id,
                p.prod_name,
                p.category_id,
                p.brand,
                p.description,
                p.prod_price,
                p.unit_type,
                p.stock_quantity,
                p.stock_status,
                p.prod_image,
                p.prod_image2,
                p.prod_image3,
                p.expiry_at,
                p.prod_status,
                ps.ps_id,
                ps.stock_qty,
                ps.selling_price,
                ps.ps_status,
                ps.seller_id
            FROM product p
            INNER JOIN product_seller ps ON ps.prod_id = p.prod_id
            WHERE p.prod_id = %s AND ps.seller_id = %s
            LIMIT 1
            """,
            (prod_id, seller_id),
        )
        existing = cur.fetchone()
        if not existing:
            return jsonify({"success": False, "message": "Product not found for this seller"}), 404

        is_multipart = request.content_type and "multipart/form-data" in request.content_type.lower()
        data = request.form if is_multipart else (request.get_json(silent=True) or {})

        prod_name = str(data.get("product_name", data.get("name", existing.get("prod_name") or ""))).strip()
        category_id = str(data.get("category_id", data.get("category", existing.get("category_id") or ""))).strip()
        description = str(data.get("description", existing.get("description") or "")).strip()
        brand = str(data.get("brand", existing.get("brand") or "No Brand")).strip() or "No Brand"
        unit_type = str(data.get("unit_type", data.get("unit", existing.get("unit_type") or "pcs"))).strip() or "pcs"
        price_raw = data.get("price", existing.get("selling_price") if existing.get("selling_price") is not None else existing.get("prod_price"))
        quantity_raw = data.get("quantity", data.get("stock", existing.get("stock_qty") if existing.get("stock_qty") is not None else existing.get("stock_quantity")))
        expiry_raw = data.get("expiry_at", existing.get("expiry_at"))
        prod_status = str(data.get("prod_status", data.get("status", existing.get("ps_status") or existing.get("prod_status") or "Active"))).strip() or "Active"

        if not prod_name:
            return jsonify({"success": False, "message": "Product name is required"}), 400
        if not category_id:
            return jsonify({"success": False, "message": "Category is required"}), 400
        if not description:
            return jsonify({"success": False, "message": "Description is required"}), 400

        category_id = _safe_int(category_id, None)
        if category_id is None:
            return jsonify({"success": False, "message": "Invalid category"}), 400

        price = _safe_float(price_raw, None)
        quantity = _safe_float(quantity_raw, None)
        if price is None or price < 0:
            return jsonify({"success": False, "message": "Invalid price"}), 400
        if quantity is None or quantity < 0:
            return jsonify({"success": False, "message": "Invalid stock quantity"}), 400

        if isinstance(expiry_raw, datetime):
            expiry_value = expiry_raw
        elif expiry_raw:
            try:
                expiry_value = datetime.fromisoformat(str(expiry_raw))
            except Exception:
                try:
                    expiry_value = datetime.strptime(str(expiry_raw), "%Y-%m-%d")
                except Exception:
                    return jsonify({"success": False, "message": "Invalid expiry_at format. Use YYYY-MM-DD or ISO datetime."}), 400
        else:
            expiry_value = existing.get("expiry_at") or datetime.now()

        stock_status = "Out of Stock" if quantity <= 0 else "Available"

        prod_image = existing.get("prod_image")
        prod_image2 = existing.get("prod_image2")
        prod_image3 = existing.get("prod_image3")

        image_file = request.files.get("image") if is_multipart else None
        image1_file = request.files.get("image1") if is_multipart else None
        image2_file = request.files.get("image2") if is_multipart else None
        image3_file = request.files.get("image3") if is_multipart else None

        if image_file and getattr(image_file, "filename", ""):
            prod_image = _save_uploaded_image(image_file, PRODUCT_IMAGE_FOLDER, f"prod_{seller_id}")

        if image1_file and getattr(image1_file, "filename", ""):
            prod_image = _save_uploaded_image(image1_file, PRODUCT_IMAGE_FOLDER, f"prod_{seller_id}_1")
        if image2_file and getattr(image2_file, "filename", ""):
            prod_image2 = _save_uploaded_image(image2_file, PRODUCT_IMAGE_FOLDER, f"prod_{seller_id}_2")
        if image3_file and getattr(image3_file, "filename", ""):
            prod_image3 = _save_uploaded_image(image3_file, PRODUCT_IMAGE_FOLDER, f"prod_{seller_id}_3")

        write_cur = conn.cursor()
        write_cur.execute(
            """
            UPDATE product
            SET
                prod_name = %s,
                category_id = %s,
                brand = %s,
                description = %s,
                prod_price = %s,
                unit_type = %s,
                stock_quantity = %s,
                stock_status = %s,
                prod_image = %s,
                prod_image2 = %s,
                prod_image3 = %s,
                expiry_at = %s,
                prod_status = %s
            WHERE prod_id = %s
            """,
            (
                prod_name,
                category_id,
                brand,
                description,
                price,
                unit_type,
                quantity,
                stock_status,
                prod_image,
                prod_image2,
                prod_image3,
                expiry_value,
                prod_status,
                prod_id,
            ),
        )
        write_cur.execute(
            """
            UPDATE product_seller
            SET
                stock_qty = %s,
                selling_price = %s,
                ps_status = %s
            WHERE prod_id = %s AND seller_id = %s
            """,
            (quantity, price, prod_status, prod_id, seller_id),
        )
        conn.commit()
        write_cur.close()

        cur = conn.cursor(dictionary=True)
        cur.execute(
            """
            SELECT
                p.prod_id,
                p.prod_name,
                p.category_id,
                p.brand,
                p.description,
                COALESCE(ps.selling_price, p.prod_price) AS prod_price,
                p.unit_type,
                COALESCE(ps.stock_qty, p.stock_quantity) AS stock_quantity,
                CASE
                    WHEN COALESCE(ps.stock_qty, p.stock_quantity) <= 0 THEN 'Out of Stock'
                    ELSE 'Available'
                END AS stock_status,
                p.prod_image,
                p.prod_image2,
                p.prod_image3,
                p.expiry_at,
                COALESCE(ps.ps_status, p.prod_status) AS prod_status,
                ps.ps_id,
                ps.seller_id
            FROM product p
            INNER JOIN product_seller ps ON ps.prod_id = p.prod_id
            WHERE p.prod_id = %s AND ps.seller_id = %s
            LIMIT 1
            """,
            (prod_id, seller_id),
        )
        updated = cur.fetchone()
        updated = _serialize_row(updated)
        updated["prod_image_url"] = _build_product_image_url(updated.get("prod_image"))
        updated["prod_image2_url"] = _build_product_image_url(updated.get("prod_image2"))
        updated["prod_image3_url"] = _build_product_image_url(updated.get("prod_image3"))
        updated["images"] = [
            img for img in [
                updated.get("prod_image_url"),
                updated.get("prod_image2_url"),
                updated.get("prod_image3_url"),
            ] if img
        ]

        return jsonify({
            "success": True,
            "message": "Product updated successfully",
            "product": updated,
        }), 200

    except ValueError as e:
        if conn:
            conn.rollback()
        return jsonify({"success": False, "message": str(e)}), 400
    except Exception as e:
        if conn:
            conn.rollback()
        return jsonify({"success": False, "message": str(e)}), 500
    finally:
        if cur:
            cur.close()
        if write_cur:
            write_cur.close()
        if conn:
            conn.close()


# ======================================================
# Seller Orders
# ======================================================
@seller_bp.route("/orders", methods=["GET"])
@jwt_required()
def get_seller_orders():
    if not _is_seller():
        return jsonify({"message": "Access denied. Seller only."}), 403

    seller_id = _seller_identity_int()
    search = request.args.get("search", default="", type=str).strip()
    sort = request.args.get("sort", default="Date", type=str).strip()

    conn = None
    cur = None
    try:
        conn = get_db_connection()
        cur = conn.cursor(dictionary=True)

        base_query = """
            SELECT
                order_id,
                seller_id,
                cart_id,
                user_id,
                delivery_staff_id,
                order_date,
                total_amount,
                payment_method,
                payment_status,
                order_status,
                delivery_status,
                delivery_address,
                pincode,
                notes
            FROM orders
            WHERE seller_id = %s
        """
        params = [seller_id]

        if search:
            like_value = f"%{search}%"
            base_query += """
                AND (
                    CAST(order_id AS CHAR) LIKE %s OR
                    CAST(cart_id AS CHAR) LIKE %s OR
                    CAST(user_id AS CHAR) LIKE %s OR
                    CAST(delivery_staff_id AS CHAR) LIKE %s OR
                    payment_method LIKE %s OR
                    payment_status LIKE %s OR
                    order_status LIKE %s OR
                    delivery_status LIKE %s OR
                    delivery_address LIKE %s OR
                    CAST(pincode AS CHAR) LIKE %s OR
                    notes LIKE %s OR
                    CAST(total_amount AS CHAR) LIKE %s
                )
            """
            params.extend([like_value] * 12)

        if sort in ("Date", "Time"):
            base_query += " ORDER BY order_date DESC"
        elif sort == "Accepted":
            base_query += " ORDER BY CASE WHEN order_status = 'Confirmed' THEN 0 ELSE 1 END, order_date DESC"
        elif sort == "Delivered":
            base_query += " ORDER BY CASE WHEN order_status = 'Delivered' THEN 0 ELSE 1 END, order_date DESC"
        elif sort == "Pending":
            base_query += " ORDER BY CASE WHEN order_status = 'Pending' THEN 0 ELSE 1 END, order_date DESC"
        elif sort == "Failed":
            base_query += " ORDER BY CASE WHEN payment_status = 'Failed' THEN 0 ELSE 1 END, order_date DESC"
        elif sort == "Customized":
            base_query += " ORDER BY total_amount DESC"
        else:
            base_query += " ORDER BY order_date DESC"

        cur.execute(base_query, tuple(params))
        orders = cur.fetchall() or []

        return jsonify({
            "success": True,
            "orders": [_format_seller_order(order) for order in orders],
        }), 200

    except Exception as e:
        return jsonify({"success": False, "message": "Failed to fetch orders", "error": str(e)}), 500
    finally:
        if cur:
            cur.close()
        if conn:
            conn.close()


@seller_bp.route("/order-details/<int:order_id>", methods=["GET"])
@jwt_required()
def get_seller_order_details(order_id):
    if not _is_seller():
        return jsonify({"message": "Access denied. Seller only."}), 403

    seller_id = _seller_identity_int()
    conn = None
    cur = None
    try:
        conn = get_db_connection()
        cur = conn.cursor(dictionary=True)

        cur.execute(
            """
            SELECT
                o.order_id,
                o.seller_id,
                o.cart_id,
                o.user_id,
                o.delivery_staff_id,
                o.order_date,
                o.total_amount,
                o.payment_method,
                o.payment_status,
                o.order_status,
                o.delivery_status,
                o.delivery_address,
                o.pincode,
                o.notes,
                u.user_name AS user_name,
                u.user_email AS user_email,
                u.user_mobile AS user_mobile
            FROM orders o
            LEFT JOIN user u ON u.user_id = o.user_id
            WHERE o.order_id = %s AND o.seller_id = %s
            LIMIT 1
            """,
            (order_id, seller_id),
        )
        order = cur.fetchone()
        if not order:
            return jsonify({"success": False, "message": "Order not found"}), 404

        order_date = order.get("order_date")
        formatted_date = order_date.strftime("%d %b %Y") if isinstance(order_date, datetime) else ""

        customer_name = (
            order.get("user_name") or
            (f"User #{order.get('user_id')}" if order.get("user_id") is not None else f"Cart #{order.get('cart_id')}")
        )

        response = {
            "order_id": order["order_id"],
            "seller_id": order["seller_id"],
            "cart_id": order["cart_id"],
            "user_id": order.get("user_id"),
            "user_name": customer_name,
            "user_email": order.get("user_email") or "",
            "user_mobile": "" if order.get("user_mobile") is None else str(order.get("user_mobile")),
            "delivery_staff_id": order["delivery_staff_id"],
            "order_date": order_date.strftime("%Y-%m-%d %H:%M:%S") if isinstance(order_date, datetime) else "",
            "total_amount": _safe_float(order["total_amount"]),
            "payment_method": order["payment_method"] or "",
            "payment_status": order["payment_status"] or "",
            "order_status": order["order_status"] or "",
            "delivery_status": order.get("delivery_status") or "",
            "delivery_address": order["delivery_address"] or "",
            "pincode": "" if order.get("pincode") is None else str(order.get("pincode")),
            "notes": order["notes"] or "",
            "orderId": f"#ORD{order['order_id']}",
            "customer": customer_name,
            "customer_name": customer_name,
            "date": formatted_date,
            "amount": _safe_float(order["total_amount"]),
            "status": order["order_status"] or "",
        }

        return jsonify({"success": True, "order": response}), 200

    except Exception as e:
        return jsonify({"success": False, "message": "Failed to fetch order details", "error": str(e)}), 500
    finally:
        if cur:
            cur.close()
        if conn:
            conn.close()


def _num(v):
    if v is None:
        return 0
    if isinstance(v, Decimal):
        return float(v)
    return float(v)


def _parse_date_param(value):
    if not value:
        return None
    value = str(value).strip()
    if not value:
        return None

    for fmt in ("%Y-%m-%d", "%d-%m-%Y"):
        try:
            return datetime.strptime(value, fmt)
        except ValueError:
            pass

    try:
        return datetime.fromisoformat(value)
    except ValueError:
        return None


def _get_report_range_dates():
    start_raw = request.args.get("start_date")
    end_raw = request.args.get("end_date")

    start_dt = _parse_date_param(start_raw)
    end_dt = _parse_date_param(end_raw)

    if start_dt and end_dt:
        start = start_dt.replace(hour=0, minute=0, second=0, microsecond=0)
        end = end_dt.replace(hour=23, minute=59, second=59, microsecond=999999)
        if end < start:
            start, end = end.replace(hour=0, minute=0, second=0, microsecond=0), start.replace(hour=23, minute=59, second=59, microsecond=999999)
        return "custom", start, end

    rng = (request.args.get("range") or "week").strip().lower()
    now = datetime.now()

    if rng == "today":
        start = now.replace(hour=0, minute=0, second=0, microsecond=0)
        end = now
    elif rng == "yesterday":
        y = now - timedelta(days=1)
        start = y.replace(hour=0, minute=0, second=0, microsecond=0)
        end = y.replace(hour=23, minute=59, second=59, microsecond=999999)
    elif rng == "month":
        start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        end = now
    else:
        rng = "week"
        start = now - timedelta(days=7)
        end = now

    return rng, start, end


def _status_count_map(rows, key_name):
    result = {}
    for row in rows:
        key = (row.get(key_name) or "Unknown").strip()
        result[key] = int(row.get("cnt") or 0)
    return result


def _seller_reports_most_sold_products(cur, seller_id, start, end):
    products = []

    if _table_exists(cur, "order_items"):
        oi_order_col = _first_existing_column(cur, "order_items", ["order_id"])
        oi_product_col = _first_existing_column(cur, "order_items", ["product_id", "prod_id"])
        oi_qty_col = _first_existing_column(cur, "order_items", ["quantity", "qty"])
        oi_total_col = _first_existing_column(cur, "order_items", ["subtotal", "line_total", "total_amount", "amount"])
        oi_price_col = _first_existing_column(cur, "order_items", ["price", "unit_price", "product_price"])

        if oi_order_col and oi_product_col:
            qty_expr = f"COALESCE(SUM(oi.`{oi_qty_col}`), COUNT(*))" if oi_qty_col else "COUNT(*)"
            revenue_expr = (
                f"COALESCE(SUM(oi.`{oi_total_col}`), 0)"
                if oi_total_col
                else (
                    f"COALESCE(SUM(oi.`{oi_price_col}` * COALESCE(oi.`{oi_qty_col}`, 1)), 0)"
                    if oi_price_col and oi_qty_col
                    else (
                        f"COALESCE(SUM(oi.`{oi_price_col}`), 0)"
                        if oi_price_col
                        else "COALESCE(SUM(o.total_amount), 0)"
                    )
                )
            )

            cur.execute(
                f'''
                SELECT
                    p.prod_id AS product_id,
                    p.prod_name AS product_name,
                    COALESCE(ps.selling_price, p.prod_price) AS price,
                    COALESCE(ps.stock_qty, p.stock_quantity) AS stock,
                    COALESCE(ps.ps_status, p.prod_status) AS status,
                    {qty_expr} AS sold_qty,
                    {revenue_expr} AS revenue
                FROM orders o
                INNER JOIN order_items oi
                    ON oi.`{oi_order_col}` = o.order_id
                INNER JOIN product p
                    ON p.prod_id = oi.`{oi_product_col}`
                INNER JOIN product_seller ps
                    ON ps.prod_id = p.prod_id AND ps.seller_id = o.seller_id
                WHERE o.seller_id = %s
                  AND o.order_date BETWEEN %s AND %s
                GROUP BY
                    p.prod_id,
                    p.prod_name,
                    COALESCE(ps.selling_price, p.prod_price),
                    COALESCE(ps.stock_qty, p.stock_quantity),
                    COALESCE(ps.ps_status, p.prod_status)
                ORDER BY sold_qty DESC, revenue DESC, p.prod_name ASC
                LIMIT 10
                ''',
                (seller_id, start, end),
            )
            rows = cur.fetchall() or []
            products = [
                {
                    "product_id": row.get("product_id"),
                    "product_name": row.get("product_name") or "",
                    "price": _num(row.get("price")),
                    "stock": _safe_int(row.get("stock")),
                    "status": row.get("status") or "",
                    "sold_qty": _safe_int(row.get("sold_qty")),
                    "revenue": _num(row.get("revenue")),
                }
                for row in rows
            ]
            if products:
                return products

    order_product_col = _first_existing_column(cur, "orders", ["product_id", "prod_id"])
    if order_product_col:
        cur.execute(
            f'''
            SELECT
                p.prod_id AS product_id,
                p.prod_name AS product_name,
                COALESCE(ps.selling_price, p.prod_price) AS price,
                COALESCE(ps.stock_qty, p.stock_quantity) AS stock,
                COALESCE(ps.ps_status, p.prod_status) AS status,
                COUNT(o.order_id) AS sold_qty,
                COALESCE(SUM(o.total_amount), 0) AS revenue
            FROM orders o
            INNER JOIN product p ON p.prod_id = o.`{order_product_col}`
            INNER JOIN product_seller ps ON ps.prod_id = p.prod_id AND ps.seller_id = o.seller_id
            WHERE o.seller_id = %s
              AND o.order_date BETWEEN %s AND %s
            GROUP BY
                p.prod_id,
                p.prod_name,
                COALESCE(ps.selling_price, p.prod_price),
                COALESCE(ps.stock_qty, p.stock_quantity),
                COALESCE(ps.ps_status, p.prod_status)
            ORDER BY sold_qty DESC, revenue DESC, p.prod_name ASC
            LIMIT 10
            ''',
            (seller_id, start, end),
        )
        rows = cur.fetchall() or []
        products = [
            {
                "product_id": row.get("product_id"),
                "product_name": row.get("product_name") or "",
                "price": _num(row.get("price")),
                "stock": _safe_int(row.get("stock")),
                "status": row.get("status") or "",
                "sold_qty": _safe_int(row.get("sold_qty")),
                "revenue": _num(row.get("revenue")),
            }
            for row in rows
        ]

    return products


# ======================================================
# Seller Reports
# ======================================================
@seller_bp.route("/reports/summary", methods=["GET"])
@jwt_required()
def get_seller_reports_summary():
    if not _is_seller():
        return jsonify({"message": "Access denied. Seller only."}), 403

    seller_id = _seller_identity_int()
    if seller_id is None:
        return jsonify({"message": "Invalid seller identity"}), 401

    rng, start, end = _get_report_range_dates()

    conn = None
    cur = None
    try:
        conn = get_db_connection()
        cur = conn.cursor(dictionary=True)

        seller = _fetch_seller_profile_row(cur, seller_id)
        if not seller:
            return jsonify({"success": False, "message": "Seller not found"}), 404

        cur.execute(
            '''
            SELECT COUNT(DISTINCT prod_id) AS total_products
            FROM product_seller
            WHERE seller_id = %s
            ''',
            (seller_id,),
        )
        product_row = cur.fetchone() or {}

        cur.execute(
            '''
            SELECT
                COUNT(*) AS total_orders,
                COALESCE(SUM(CASE WHEN payment_status = 'Paid' THEN total_amount ELSE 0 END), 0) AS total_revenue,
                COALESCE(AVG(total_amount), 0) AS avg_order_value,
                SUM(CASE WHEN payment_status = 'Paid' THEN 1 ELSE 0 END) AS paid_orders,
                SUM(CASE WHEN payment_status = 'Pending' THEN 1 ELSE 0 END) AS pending_payments,
                SUM(CASE WHEN payment_status = 'Failed' THEN 1 ELSE 0 END) AS failed_payments,
                MAX(order_date) AS last_order_date
            FROM orders
            WHERE seller_id = %s
              AND order_date BETWEEN %s AND %s
            ''',
            (seller_id, start, end),
        )
        order_stats = cur.fetchone() or {}

        cur.execute(
            '''
            SELECT order_status, COUNT(*) AS cnt
            FROM orders
            WHERE seller_id = %s
              AND order_date BETWEEN %s AND %s
            GROUP BY order_status
            ''',
            (seller_id, start, end),
        )
        order_status_counts = _status_count_map(cur.fetchall() or [], "order_status")

        cur.execute(
            '''
            SELECT payment_status, COUNT(*) AS cnt
            FROM orders
            WHERE seller_id = %s
              AND order_date BETWEEN %s AND %s
            GROUP BY payment_status
            ''',
            (seller_id, start, end),
        )
        payment_status_counts = _status_count_map(cur.fetchall() or [], "payment_status")

        cur.execute(
            '''
            SELECT payment_method, COUNT(*) AS cnt
            FROM orders
            WHERE seller_id = %s
              AND order_date BETWEEN %s AND %s
              AND payment_method IS NOT NULL
              AND payment_method <> ''
            GROUP BY payment_method
            ORDER BY cnt DESC, payment_method ASC
            ''',
            (seller_id, start, end),
        )
        pm_rows = cur.fetchall() or []
        payment_method_counts = {
            row.get("payment_method"): _safe_int(row.get("cnt"))
            for row in pm_rows
            if row.get("payment_method")
        }

        cur.execute(
            '''
            SELECT
                DATE(order_date) AS day,
                COALESCE(SUM(CASE WHEN payment_status = 'Paid' THEN total_amount ELSE 0 END), 0) AS total
            FROM orders
            WHERE seller_id = %s
              AND order_date BETWEEN %s AND %s
            GROUP BY DATE(order_date)
            ORDER BY day ASC
            ''',
            (seller_id, start, end),
        )
        revenue_by_day = [
            {
                "day": str(row.get("day")),
                "total": _num(row.get("total")),
            }
            for row in (cur.fetchall() or [])
        ]

        most_sold_products = _seller_reports_most_sold_products(cur, seller_id, start, end)

        cur.execute(
            '''
            SELECT
                order_id,
                user_id,
                total_amount,
                order_status,
                payment_status,
                payment_method,
                order_date
            FROM orders
            WHERE seller_id = %s
              AND order_date BETWEEN %s AND %s
            ORDER BY order_date DESC, order_id DESC
            LIMIT 10
            ''',
            (seller_id, start, end),
        )
        recent_orders = [
            {
                "order_id": row.get("order_id"),
                "user_id": row.get("user_id"),
                "total_amount": _num(row.get("total_amount")),
                "order_status": row.get("order_status") or "",
                "payment_status": row.get("payment_status") or "",
                "payment_method": row.get("payment_method") or "",
                "order_date": row.get("order_date").isoformat() if isinstance(row.get("order_date"), datetime) else "",
            }
            for row in (cur.fetchall() or [])
        ]

        return jsonify({
            "success": True,
            "range": rng,
            "start": start.isoformat(),
            "end": end.isoformat(),
            "profile": {
                "id": seller.get("seller_id"),
                "name": seller.get("seller_name"),
                "email": seller.get("seller_email"),
                "mobile": seller.get("seller_mobile"),
                "registration_at": seller.get("registration_date").isoformat() if seller.get("registration_date") else None,
            },
            "cards": {
                "total_products": _safe_int(product_row.get("total_products")),
                "total_orders": _safe_int(order_stats.get("total_orders")),
                "total_revenue": _num(order_stats.get("total_revenue")),
                "avg_order_value": _num(order_stats.get("avg_order_value")),
                "paid_orders": _safe_int(order_stats.get("paid_orders")),
                "pending_payments": _safe_int(order_stats.get("pending_payments")),
                "failed_payments": _safe_int(order_stats.get("failed_payments")),
                "last_order_date": order_stats.get("last_order_date").isoformat() if order_stats.get("last_order_date") else None,
            },
            "order_status_counts": order_status_counts,
            "payment_status_counts": payment_status_counts,
            "payment_method_counts": payment_method_counts,
            "revenue_by_day": revenue_by_day,
            "most_sold_products": most_sold_products,
            "recent_orders": recent_orders,
        }), 200

    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500
    finally:
        if cur:
            cur.close()
        if conn:
            conn.close()


# ======================================================
# Seller Products
# ======================================================
@seller_bp.route("/products", methods=["GET"])
@jwt_required()
def get_seller_products():
    if not _is_seller():
        return jsonify({"message": "Access denied. Seller only."}), 403

    seller_id = _seller_identity_int()
    search = request.args.get("search", "").strip()
    filter_mode = request.args.get("filter_mode", "").strip().lower()

    conn = None
    cur = None
    try:
        conn = get_db_connection()
        cur = conn.cursor(dictionary=True)

        rating_join = ""
        rating_select = "0 AS avg_rating, 0 AS review_count"
        rating_join_params = []

        if _table_exists(cur, "product_reviews"):
            review_product_col = _first_existing_column(cur, "product_reviews", ["prod_id", "product_id"])
            review_rating_col = _first_existing_column(cur, "product_reviews", ["rating"])
            review_seller_col = _first_existing_column(cur, "product_reviews", ["seller_id"])

            if review_product_col and review_rating_col and review_seller_col:
                rating_select = """
                    COALESCE(rr.avg_rating, 0) AS avg_rating,
                    COALESCE(rr.review_count, 0) AS review_count
                """
                rating_join = f"""
                    LEFT JOIN (
                        SELECT
                            `{review_product_col}` AS rating_product_id,
                            ROUND(AVG(COALESCE(`{review_rating_col}`, 0)), 1) AS avg_rating,
                            COUNT(*) AS review_count
                        FROM product_reviews
                        WHERE `{review_seller_col}` = %s
                        GROUP BY `{review_product_col}`
                    ) rr ON rr.rating_product_id = p.prod_id
                """
                rating_join_params.append(seller_id)

        elif _table_exists(cur, "feedback"):
            feedback_product_col = _first_existing_column(cur, "feedback", ["product_id", "prod_id"])
            feedback_rating_col = _first_existing_column(cur, "feedback", ["rating"])

            if feedback_product_col and feedback_rating_col:
                rating_select = """
                    COALESCE(rr.avg_rating, 0) AS avg_rating,
                    COALESCE(rr.review_count, 0) AS review_count
                """
                rating_join = f"""
                    LEFT JOIN (
                        SELECT
                            `{feedback_product_col}` AS rating_product_id,
                            ROUND(AVG(COALESCE(`{feedback_rating_col}`, 0)), 1) AS avg_rating,
                            COUNT(*) AS review_count
                        FROM feedback
                        GROUP BY `{feedback_product_col}`
                    ) rr ON rr.rating_product_id = p.prod_id
                """

        sql = f"""
            SELECT
                p.prod_id,
                p.prod_name,
                p.category_id,
                c.category_name,
                p.brand,
                p.description,
                COALESCE(ps.selling_price, p.prod_price) AS prod_price,
                p.unit_type,
                COALESCE(ps.stock_qty, p.stock_quantity) AS stock_quantity,
                CASE
                    WHEN COALESCE(ps.stock_qty, p.stock_quantity) <= 0 THEN 'Out of Stock'
                    ELSE 'Available'
                END AS stock_status,
                p.prod_image,
                p.prod_image2,
                p.prod_image3,
                p.expiry_at,
                COALESCE(ps.ps_status, p.prod_status) AS prod_status,
                ps.ps_id,
                ps.seller_id,
                {rating_select}
            FROM product_seller ps
            LEFT JOIN product p ON p.prod_id = ps.prod_id
            LEFT JOIN category c ON c.category_id = p.category_id
            {rating_join}
            WHERE ps.seller_id = %s
        """

        params = []
        params.extend(rating_join_params)
        params.append(seller_id)

        if search:
            like_value = f"%{search}%"
            sql += """
                AND (
                    p.prod_name LIKE %s OR
                    c.category_name LIKE %s OR
                    p.brand LIKE %s OR
                    p.description LIKE %s
                )
            """
            params.extend([like_value, like_value, like_value, like_value])

        if filter_mode == "low_stock":
            sql += " AND COALESCE(ps.stock_qty, p.stock_quantity) > 0 AND COALESCE(ps.stock_qty, p.stock_quantity) <= 5 "
        elif filter_mode == "out_of_stock":
            sql += " AND COALESCE(ps.stock_qty, p.stock_quantity) <= 0 "

        sql += " ORDER BY p.prod_id DESC "

        cur.execute(sql, tuple(params))
        rows = cur.fetchall() or []

        products = []
        for row in rows:
            row = _serialize_row(row)
            images = []
            for key in ("prod_image", "prod_image2", "prod_image3"):
                image_url = _build_product_image_url(row.get(key))
                if image_url:
                    images.append(image_url)

            products.append({
                "id": row.get("prod_id"),
                "ps_id": row.get("ps_id"),
                "seller_id": row.get("seller_id"),
                "name": row.get("prod_name") or "",
                "category_id": row.get("category_id"),
                "category": row.get("category_name") or "Unknown",
                "brand": row.get("brand") or "",
                "description": row.get("description") or "",
                "price": _safe_float(row.get("prod_price")),
                "stock": _safe_float(row.get("stock_quantity")),
                "unit": row.get("unit_type") or "",
                "status": row.get("prod_status") or "",
                "stock_status": row.get("stock_status") or "",
                "expiry_at": row.get("expiry_at"),
                "images": images,
                "prod_image": row.get("prod_image") or "",
                "prod_image2": row.get("prod_image2") or "",
                "prod_image3": row.get("prod_image3") or "",
                "avg_rating": _safe_float(row.get("avg_rating")),
                "review_count": _safe_int(row.get("review_count")),
            })

        return jsonify({"success": True, "products": products}), 200

    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500
    finally:
        if cur:
            cur.close()
        if conn:
            conn.close()