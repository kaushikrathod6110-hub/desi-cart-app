from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required, get_jwt, get_jwt_identity
from db import get_db_connection
from decimal import Decimal

cart_bp = Blueprint("cart_bp", __name__)


def _is_user():
    return str(get_jwt().get("role", "")).lower() == "user"


def _current_user_id():
    try:
        return int(get_jwt_identity())
    except Exception:
        return None


def _ensure_same_user(user_id):
    if not _is_user():
        return jsonify({"message": "Access denied. User only."}), 403
    current_user_id = _current_user_id()
    if current_user_id is None:
        return jsonify({"message": "Invalid user identity"}), 401
    if int(user_id) != current_user_id:
        return jsonify({"message": "You can access only your own cart data."}), 403
    return None


def _to_float(value, default=0.0):
    try:
        if value is None:
            return float(default)
        if isinstance(value, Decimal):
            return float(value)
        return float(value)
    except Exception:
        return float(default)


def _to_int(value, default=0):
    try:
        return int(value)
    except Exception:
        return int(default)



def _build_upload_url(path_value):
    if not path_value:
        return None

    raw = str(path_value).replace("\\", "/").strip()
    if not raw:
        return None

    if raw.startswith("http://") or raw.startswith("https://"):
        return raw

    if raw.startswith("uploads/"):
        raw = raw[len("uploads/"):]

    base = request.host_url.rstrip("/")
    return f"{base}/uploads/{raw}"



def _product_payload_from_row(row):
    if not row:
        return None

    image1 = _build_upload_url(row.get("prod_image"))
    image2 = _build_upload_url(row.get("prod_image2"))
    image3 = _build_upload_url(row.get("prod_image3"))

    images = [img for img in [image1, image2, image3] if img]

    return {
        "prod_id": row.get("prod_id"),
        "prod_name": row.get("prod_name") or "",
        "prod_price": _to_float(row.get("selling_price") if row.get("selling_price") is not None else row.get("prod_price")),
        "brand": row.get("brand") or "",
        "description": row.get("description") or "",
        "unit_type": row.get("unit_type") or "",
        "category_id": row.get("category_id"),
        "seller_id": row.get("seller_id"),
        "seller_name": row.get("seller_name") or "",
        "stock_quantity": _to_float(row.get("stock_qty") if row.get("stock_qty") is not None else row.get("stock_quantity")),
        "stock_status": row.get("stock_status") or "",
        "prod_status": row.get("ps_status") or row.get("prod_status") or "",
        "prod_image": image1,
        "prod_image2": image2,
        "prod_image3": image3,
        "prod_images": images,
    }



def _fetch_product_for_cart(cur, prod_id, seller_id=None):
    if seller_id is not None:
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
                p.prod_status,
                ps.seller_id,
                ps.stock_qty,
                ps.selling_price,
                ps.ps_status,
                s.seller_name
            FROM product p
            INNER JOIN product_seller ps ON ps.prod_id = p.prod_id
            INNER JOIN seller s ON s.seller_id = ps.seller_id
            WHERE p.prod_id = %s
              AND ps.seller_id = %s
              AND p.prod_status = 'Active'
              AND ps.ps_status = 'Active'
            LIMIT 1
            """,
            (prod_id, seller_id),
        )
        row = cur.fetchone()
        if row:
            return row

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
            p.prod_status,
            ps.seller_id,
            ps.stock_qty,
            ps.selling_price,
            ps.ps_status,
            s.seller_name
        FROM product p
        INNER JOIN product_seller ps ON ps.prod_id = p.prod_id
        INNER JOIN seller s ON s.seller_id = ps.seller_id
        WHERE p.prod_id = %s
          AND p.prod_status = 'Active'
          AND ps.ps_status = 'Active'
        ORDER BY ps.ps_id ASC
        LIMIT 1
        """,
        (prod_id,),
    )
    return cur.fetchone()


@cart_bp.route("/add_to_cart", methods=["POST"])
@jwt_required()
def add_to_cart():
    data = request.get_json(silent=True) or {}

    user_id = _to_int(data.get("user_id"), 0)
    prod_id = _to_int(data.get("prod_id"), 0)
    seller_id = data.get("seller_id")
    seller_id = _to_int(seller_id, 0) if seller_id not in (None, "") else None
    quantity = _to_int(data.get("quantity"), 0)

    if user_id <= 0 or prod_id <= 0 or quantity <= 0:
        return jsonify({"message": "user_id, prod_id and valid quantity are required"}), 400

    auth_error = _ensure_same_user(user_id)
    if auth_error:
        return auth_error

    conn = None
    cur = None
    try:
        conn = get_db_connection()
        cur = conn.cursor(dictionary=True)

        cur.execute("SELECT user_id FROM user WHERE user_id = %s LIMIT 1", (user_id,))
        user = cur.fetchone()
        if not user:
            return jsonify({"message": "User not found"}), 404

        product = _fetch_product_for_cart(cur, prod_id, seller_id)
        if not product:
            return jsonify({"message": "Product not found"}), 404

        final_seller_id = _to_int(product.get("seller_id"), 0)
        available_stock = _to_float(product.get("stock_qty") if product.get("stock_qty") is not None else product.get("stock_quantity"))
        price = _to_float(product.get("selling_price") if product.get("selling_price") is not None else product.get("prod_price"))

        cur.execute(
            """
            SELECT cart_id, quantity
            FROM cart
            WHERE user_id = %s AND prod_id = %s AND seller_id = %s AND cart_status = 'Active'
            LIMIT 1
            """,
            (user_id, prod_id, final_seller_id),
        )
        existing = cur.fetchone()

        requested_quantity = quantity
        if existing:
            requested_quantity = _to_int(existing.get("quantity"), 0) + quantity

        if available_stock > 0:
            if requested_quantity > int(available_stock) and available_stock.is_integer():
                return jsonify({"message": f"Only {int(available_stock)} item(s) available in stock"}), 400
            if requested_quantity > available_stock:
                return jsonify({"message": f"Only {available_stock} item(s) available in stock"}), 400

        total_price = round(price * requested_quantity, 2)

        write_cur = conn.cursor()
        if existing:
            write_cur.execute(
                """
                UPDATE cart
                SET quantity = %s,
                    price_at_time = %s,
                    total_price = %s,
                    updated_at = CURRENT_TIMESTAMP
                WHERE cart_id = %s
                """,
                (requested_quantity, price, total_price, existing["cart_id"]),
            )
            message = "Cart updated successfully"
            cart_id = existing["cart_id"]
        else:
            write_cur.execute(
                """
                INSERT INTO cart (user_id, seller_id, prod_id, quantity, price_at_time, total_price, cart_status)
                VALUES (%s, %s, %s, %s, %s, %s, 'Active')
                """,
                (user_id, final_seller_id, prod_id, quantity, price, round(price * quantity, 2)),
            )
            message = "Added to cart"
            cart_id = write_cur.lastrowid

        conn.commit()
        write_cur.close()

        return jsonify({
            "message": message,
            "cart_id": cart_id,
            "user_id": user_id,
            "prod_id": prod_id,
            "seller_id": final_seller_id,
            "quantity": requested_quantity if existing else quantity,
            "price_at_time": price,
            "total_price": total_price if existing else round(price * quantity, 2),
        }), 200

    except Exception as e:
        if conn:
            conn.rollback()
        return jsonify({"message": f"Error adding to cart: {str(e)}"}), 500
    finally:
        if cur:
            cur.close()
        if conn:
            conn.close()


@cart_bp.route("/update_cart", methods=["POST"])
@jwt_required()
def update_cart():
    data = request.get_json(silent=True) or {}

    cart_id = _to_int(data.get("cart_id"), 0)
    quantity = _to_int(data.get("quantity"), 0)

    if cart_id <= 0 or quantity <= 0:
        return jsonify({"message": "cart_id and valid quantity are required"}), 400

    conn = None
    cur = None
    try:
        conn = get_db_connection()
        cur = conn.cursor(dictionary=True)

        cur.execute(
            """
            SELECT c.cart_id, c.user_id, c.seller_id, c.prod_id,
                   p.prod_price, p.stock_quantity,
                   ps.stock_qty, ps.selling_price, ps.ps_status,
                   p.prod_status
            FROM cart c
            LEFT JOIN product p ON p.prod_id = c.prod_id
            LEFT JOIN product_seller ps ON ps.prod_id = c.prod_id AND ps.seller_id = c.seller_id
            WHERE c.cart_id = %s AND c.cart_status = 'Active'
            LIMIT 1
            """,
            (cart_id,),
        )
        cart_row = cur.fetchone()

        if not cart_row:
            return jsonify({"message": "Cart item not found"}), 404

        auth_error = _ensure_same_user(cart_row.get("user_id") or 0)
        if auth_error:
            return auth_error

        if str(cart_row.get("prod_status") or "").lower() != "active":
            return jsonify({"message": "Product is inactive"}), 400

        if cart_row.get("ps_status") is not None and str(cart_row.get("ps_status") or "").lower() != "active":
            return jsonify({"message": "Seller product is inactive"}), 400

        available_stock = _to_float(cart_row.get("stock_qty") if cart_row.get("stock_qty") is not None else cart_row.get("stock_quantity"))
        price = _to_float(cart_row.get("selling_price") if cart_row.get("selling_price") is not None else cart_row.get("prod_price"))

        if available_stock > 0:
            if quantity > int(available_stock) and available_stock.is_integer():
                return jsonify({"message": f"Only {int(available_stock)} item(s) available in stock"}), 400
            if quantity > available_stock:
                return jsonify({"message": f"Only {available_stock} item(s) available in stock"}), 400

        total_price = round(price * quantity, 2)

        write_cur = conn.cursor()
        write_cur.execute(
            """
            UPDATE cart
            SET quantity = %s,
                price_at_time = %s,
                total_price = %s,
                updated_at = CURRENT_TIMESTAMP
            WHERE cart_id = %s
            """,
            (quantity, price, total_price, cart_id),
        )
        conn.commit()
        write_cur.close()

        return jsonify({
            "message": "Updated",
            "cart_id": cart_id,
            "quantity": quantity,
            "price_at_time": price,
            "total_price": total_price,
        }), 200

    except Exception as e:
        if conn:
            conn.rollback()
        return jsonify({"message": f"Error updating cart: {str(e)}"}), 500
    finally:
        if cur:
            cur.close()
        if conn:
            conn.close()


@cart_bp.route("/remove_cart/<int:cart_id>", methods=["DELETE"])
@jwt_required()
def remove_cart(cart_id):
    conn = None
    cur = None
    try:
        conn = get_db_connection()
        auth_cur = conn.cursor(dictionary=True)
        auth_cur.execute("SELECT cart_id, user_id FROM cart WHERE cart_id = %s LIMIT 1", (cart_id,))
        cart_row = auth_cur.fetchone()
        auth_cur.close()

        if not cart_row:
            return jsonify({"message": "Cart item not found"}), 404

        auth_error = _ensure_same_user(cart_row.get("user_id") or 0)
        if auth_error:
            return auth_error

        cur = conn.cursor()
        cur.execute(
            "UPDATE cart SET cart_status = 'Removed', updated_at = CURRENT_TIMESTAMP WHERE cart_id = %s",
            (cart_id,),
        )
        conn.commit()

        if cur.rowcount == 0:
            return jsonify({"message": "Cart item not found"}), 404

        return jsonify({"message": "Removed"}), 200

    except Exception as e:
        if conn:
            conn.rollback()
        return jsonify({"message": f"Error removing cart item: {str(e)}"}), 500
    finally:
        if cur:
            cur.close()
        if conn:
            conn.close()


@cart_bp.route("/get_cart/<int:user_id>", methods=["GET"])
@jwt_required()
def get_cart(user_id):
    auth_error = _ensure_same_user(user_id)
    if auth_error:
        return auth_error

    conn = None
    cur = None
    try:
        conn = get_db_connection()
        cur = conn.cursor(dictionary=True)
        cur.execute(
            """
            SELECT
                c.cart_id,
                c.user_id,
                c.seller_id,
                c.prod_id,
                c.quantity,
                c.price_at_time,
                c.total_price,
                c.added_at,
                c.updated_at,
                c.cart_status,
                p.prod_name,
                p.brand,
                p.description,
                p.category_id,
                p.unit_type,
                p.prod_price,
                p.prod_image,
                p.prod_image2,
                p.prod_image3,
                p.prod_status,
                CASE
                    WHEN COALESCE(ps.stock_qty, p.stock_quantity, 0) <= 0 THEN 'Out of Stock'
                    ELSE 'Available'
                END AS stock_status,
                COALESCE(ps.stock_qty, p.stock_quantity) AS stock_quantity,
                COALESCE(ps.selling_price, p.prod_price) AS selling_price,
                COALESCE(ps.ps_status, p.prod_status) AS ps_status,
                s.seller_name
            FROM cart c
            LEFT JOIN product p ON p.prod_id = c.prod_id
            LEFT JOIN product_seller ps ON ps.prod_id = c.prod_id AND ps.seller_id = c.seller_id
            LEFT JOIN seller s ON s.seller_id = c.seller_id
            WHERE c.user_id = %s AND c.cart_status = 'Active'
            ORDER BY c.cart_id DESC
            """,
            (user_id,),
        )
        rows = cur.fetchall()

        items = []
        for row in rows:
            item = {
                "cart_id": row.get("cart_id"),
                "user_id": row.get("user_id"),
                "seller_id": row.get("seller_id"),
                "prod_id": row.get("prod_id"),
                "quantity": _to_int(row.get("quantity"), 0),
                "price_at_time": _to_float(row.get("price_at_time")),
                "total_price": _to_float(row.get("total_price")),
                "added_at": row.get("added_at").isoformat() if row.get("added_at") else None,
                "updated_at": row.get("updated_at").isoformat() if row.get("updated_at") else None,
                "cart_status": row.get("cart_status") or "",
                "prod_name": row.get("prod_name") or "",
                "prod_price": _to_float(row.get("selling_price") if row.get("selling_price") is not None else row.get("prod_price")),
                "brand": row.get("brand") or "",
                "description": row.get("description") or "",
                "category_id": row.get("category_id"),
                "unit_type": row.get("unit_type") or "",
                "seller_name": row.get("seller_name") or "",
                "stock_quantity": _to_float(row.get("stock_quantity")),
                "stock_status": row.get("stock_status") or "",
                "prod_status": row.get("ps_status") or row.get("prod_status") or "",
                "prod_image": _build_upload_url(row.get("prod_image")),
                "prod_image2": _build_upload_url(row.get("prod_image2")),
                "prod_image3": _build_upload_url(row.get("prod_image3")),
            }
            item["prod_images"] = [img for img in [item["prod_image"], item["prod_image2"], item["prod_image3"]] if img]
            items.append(item)

        return jsonify(items), 200

    except Exception as e:
        return jsonify({"message": f"Error fetching cart: {str(e)}"}), 500
    finally:
        if cur:
            cur.close()
        if conn:
            conn.close()


@cart_bp.route("/order_summary/<int:user_id>", methods=["GET"])
@jwt_required()
def order_summary(user_id):
    auth_error = _ensure_same_user(user_id)
    if auth_error:
        return auth_error

    conn = None
    cur = None
    try:
        conn = get_db_connection()
        cur = conn.cursor(dictionary=True)

        cur.execute(
            """
            SELECT
                c.cart_id,
                c.user_id,
                c.seller_id,
                c.prod_id,
                c.quantity,
                c.price_at_time,
                c.total_price,
                p.prod_name,
                p.brand,
                p.description,
                p.category_id,
                p.unit_type,
                p.prod_image,
                p.prod_image2,
                p.prod_image3,
                COALESCE(ps.selling_price, p.prod_price) AS prod_price,
                COALESCE(ps.stock_qty, p.stock_quantity) AS stock_quantity,
                COALESCE(ps.ps_status, p.prod_status) AS prod_status,
                s.seller_name
            FROM cart c
            LEFT JOIN product p ON p.prod_id = c.prod_id
            LEFT JOIN product_seller ps ON ps.prod_id = c.prod_id AND ps.seller_id = c.seller_id
            LEFT JOIN seller s ON s.seller_id = c.seller_id
            WHERE c.user_id = %s AND c.cart_status = 'Active'
            ORDER BY c.cart_id DESC
            """,
            (user_id,),
        )
        cart_rows = cur.fetchall()

        items = []
        grand_total = 0.0
        for row in cart_rows:
            total_price = _to_float(row.get("total_price"))
            grand_total += total_price
            item = {
                "cart_id": row.get("cart_id"),
                "prod_id": row.get("prod_id"),
                "seller_id": row.get("seller_id"),
                "prod_name": row.get("prod_name") or "",
                "prod_price": _to_float(row.get("prod_price")),
                "brand": row.get("brand") or "",
                "description": row.get("description") or "",
                "unit_type": row.get("unit_type") or "",
                "seller_name": row.get("seller_name") or "",
                "quantity": _to_int(row.get("quantity"), 0),
                "stock_quantity": _to_float(row.get("stock_quantity")),
                "total_price": total_price,
                "prod_image": _build_upload_url(row.get("prod_image")),
                "prod_image2": _build_upload_url(row.get("prod_image2")),
                "prod_image3": _build_upload_url(row.get("prod_image3")),
            }
            item["prod_images"] = [img for img in [item["prod_image"], item["prod_image2"], item["prod_image3"]] if img]
            items.append(item)

        cur.execute(
            """
            SELECT
                user_id,
                user_name,
                user_email,
                user_mobile,
                user_address,
                pincode,
                status,
                profile_image,
                registration_at,
                updated_at
            FROM user
            WHERE user_id = %s
            LIMIT 1
            """,
            (user_id,),
        )
        user = cur.fetchone()
        if not user:
            return jsonify({"message": "User not found"}), 404

        user["user_mobile"] = "" if user.get("user_mobile") is None else str(user.get("user_mobile"))
        user["pincode"] = "" if user.get("pincode") is None else str(user.get("pincode"))
        user["profile_image_url"] = _build_upload_url(user.get("profile_image"))
        if user.get("registration_at"):
            user["registration_at"] = user["registration_at"].isoformat()
        if user.get("updated_at"):
            user["updated_at"] = user["updated_at"].isoformat()

        return jsonify({
            "items": items,
            "user": user,
            "grand_total": round(grand_total, 2),
            "total_items": len(items),
        }), 200

    except Exception as e:
        return jsonify({"message": f"Error fetching order summary: {str(e)}"}), 500
    finally:
        if cur:
            cur.close()
        if conn:
            conn.close()


@cart_bp.route("/buy_now", methods=["POST"])
def buy_now():
    data = request.get_json(silent=True) or {}

    prod_id = _to_int(data.get("prod_id"), 0)
    seller_id = data.get("seller_id")
    seller_id = _to_int(seller_id, 0) if seller_id not in (None, "") else None
    quantity = _to_int(data.get("quantity"), 0)

    if prod_id <= 0 or quantity <= 0:
        return jsonify({"message": "prod_id and valid quantity are required"}), 400

    conn = None
    cur = None
    try:
        conn = get_db_connection()
        cur = conn.cursor(dictionary=True)

        product_row = _fetch_product_for_cart(cur, prod_id, seller_id)
        if not product_row:
            return jsonify({"message": "Product not found"}), 404

        payload = _product_payload_from_row(product_row)
        available_stock = _to_float(payload.get("stock_quantity"))
        if available_stock <= 0:
            return jsonify({"message": "Product is out of stock"}), 400
        if quantity > int(available_stock) and available_stock.is_integer():
            return jsonify({"message": f"Only {int(available_stock)} item(s) available in stock"}), 400
        if quantity > available_stock:
            return jsonify({"message": f"Only {available_stock} item(s) available in stock"}), 400

        item = {
            "prod_id": payload.get("prod_id"),
            "prod_name": payload.get("prod_name"),
            "prod_price": payload.get("prod_price"),
            "prod_image": payload.get("prod_image"),
            "prod_image2": payload.get("prod_image2"),
            "prod_image3": payload.get("prod_image3"),
            "prod_images": payload.get("prod_images"),
            "brand": payload.get("brand"),
            "description": payload.get("description"),
            "unit_type": payload.get("unit_type"),
            "seller_id": payload.get("seller_id"),
            "seller_name": payload.get("seller_name"),
            "quantity": quantity,
            "total_price": round(_to_float(payload.get("prod_price")) * quantity, 2),
        }

        return jsonify({"items": [item]}), 200

    except Exception as e:
        return jsonify({"message": f"Error preparing buy now item: {str(e)}"}), 500
    finally:
        if cur:
            cur.close()
        if conn:
            conn.close()
