import os
from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required, get_jwt, get_jwt_identity, verify_jwt_in_request
from db import get_db_connection
from decimal import Decimal
from datetime import datetime, date

user_public_bp = Blueprint("user_public_bp", __name__)


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


def _build_upload_url(path_or_name, *, prefer_seller_logo_route=False):
    if not path_or_name:
        return None
    clean = str(path_or_name).replace('\\', '/').strip()
    if not clean:
        return None
    if clean.startswith('http://') or clean.startswith('https://'):
        return clean

    base = request.host_url.rstrip('/')

    if prefer_seller_logo_route and '/' not in clean:
        return f"{base}/api/seller/logo/{clean}"

    if clean.startswith('uploads/'):
        clean = clean[len('uploads/'):]
    return f"{base}/uploads/{clean}"


def _image_urls(*values):
    out = []
    for value in values:
        url = _build_upload_url(value)
        if url and url not in out:
            out.append(url)
    return out


def _safe_int(value, default=0):
    try:
        return int(value)
    except Exception:
        return default


def _safe_bool(value):
    return str(value).strip().lower() in {'1', 'true', 'yes', 'y'}


def _safe_float(value, default=0.0):
    try:
        return float(value)
    except Exception:
        return default


def _is_user():
    try:
        return str(get_jwt().get('role', '')).lower() == 'user'
    except Exception:
        return False


def _normalize_seller_id(value):
    seller_id = _safe_int(value, 0)
    return seller_id if seller_id > 0 else 0


def _current_user_id_optional():
    try:
        verify_jwt_in_request(optional=True)
        identity = get_jwt_identity()
        return int(identity) if identity is not None else None
    except Exception:
        return None


def _ensure_product_reviews_table(cur):
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS product_reviews (
            review_id INT AUTO_INCREMENT PRIMARY KEY,
            user_id INT NOT NULL,
            prod_id INT NOT NULL,
            seller_id INT NOT NULL DEFAULT 0,
            rating INT NOT NULL,
            review TEXT,
            created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            CONSTRAINT chk_product_reviews_rating CHECK (rating BETWEEN 1 AND 5),
            UNIQUE KEY uq_product_review_user_product_seller (user_id, prod_id, seller_id),
            INDEX idx_product_reviews_product (prod_id, seller_id),
            INDEX idx_product_reviews_user (user_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
        """
    )


def _user_can_review_product(cur, user_id, prod_id, seller_id=0):
    seller_filter = _normalize_seller_id(seller_id)
    cur.execute(
        """
        SELECT 1
        FROM orders o
        LEFT JOIN order_items oi ON oi.order_id = o.order_id
        LEFT JOIN cart c ON c.cart_id = o.cart_id
        WHERE o.user_id = %s
          AND (
              LOWER(COALESCE(o.order_status, '')) = 'delivered'
              OR LOWER(REPLACE(COALESCE(o.delivery_status, ''), ' ', '')) = 'delivered'
          )
          AND (
              COALESCE(oi.prod_id, 0) = %s
              OR COALESCE(c.prod_id, 0) = %s
          )
          AND (
              %s = 0
              OR COALESCE(c.seller_id, o.seller_id, 0) = %s
          )
        LIMIT 1
        """,
        (user_id, prod_id, prod_id, seller_filter, seller_filter),
    )
    return cur.fetchone() is not None


def _fetch_user_review(cur, user_id, prod_id, seller_id=0):
    cur.execute(
        """
        SELECT review_id, user_id, prod_id, seller_id, rating, review, created_at, updated_at
        FROM product_reviews
        WHERE user_id = %s AND prod_id = %s AND seller_id = %s
        LIMIT 1
        """,
        (user_id, prod_id, _normalize_seller_id(seller_id)),
    )
    row = cur.fetchone()
    return _serialize_row(row) if row else None


def _is_nearby_search(search_text):
    normalized = ' '.join(str(search_text or '').lower().replace('-', ' ').split())
    return normalized in {'seller near by me', 'sellers near by me', 'seller nearby me', 'sellers nearby me', 'near by me', 'nearby me'}


def _ensure_wishlist_table(cur):
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS wishlist (
            wishlist_id INT AUTO_INCREMENT PRIMARY KEY,
            user_id INT NOT NULL,
            prod_id INT NOT NULL,
            seller_id INT NOT NULL DEFAULT 0,
            created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            UNIQUE KEY uq_wishlist_user_product_seller (user_id, prod_id, seller_id),
            INDEX idx_wishlist_user (user_id),
            INDEX idx_wishlist_product (prod_id, seller_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
        """
    )


def _current_user_id_required():
    if not _is_user():
        return None, (jsonify({'message': 'Access denied. User only.'}), 403)

    try:
        identity = get_jwt_identity()
        return int(identity), None
    except Exception:
        return None, (jsonify({'message': 'Invalid user token'}), 401)


@user_public_bp.route('/api/user/wishlist', methods=['GET'])
@jwt_required()
def get_user_wishlist():
    user_id, auth_error = _current_user_id_required()
    if auth_error:
        return auth_error

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)
    try:
        _ensure_wishlist_table(cur)
        conn.commit()

        cur.execute(
            """
            SELECT wishlist_id, user_id, prod_id, seller_id, created_at, updated_at
            FROM wishlist
            WHERE user_id = %s
            ORDER BY updated_at DESC, wishlist_id DESC
            """,
            (user_id,),
        )
        wishlist_rows = cur.fetchall() or []

        data = []
        for wish in wishlist_rows:
            prod_id = _safe_int(wish.get('prod_id'))
            seller_id = _normalize_seller_id(wish.get('seller_id'))

            detail_sql = """
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
                    COALESCE(ps.ps_status, p.prod_status) AS prod_status,
                    ps.seller_id,
                    s.seller_name,
                    s.shop_name,
                    s.store_logo,
                    COALESCE(reviews.avg_rating, 0) AS avg_rating,
                    COALESCE(reviews.review_count, 0) AS review_count
                FROM product p
                LEFT JOIN category c ON c.category_id = p.category_id
                LEFT JOIN product_seller ps ON ps.prod_id = p.prod_id
                LEFT JOIN seller s ON s.seller_id = ps.seller_id
                LEFT JOIN (
                    SELECT
                        prod_id,
                        seller_id,
                        ROUND(AVG(rating), 1) AS avg_rating,
                        COUNT(*) AS review_count
                    FROM product_reviews
                    GROUP BY prod_id, seller_id
                ) reviews ON reviews.prod_id = p.prod_id AND reviews.seller_id = COALESCE(ps.seller_id, 0)
                WHERE p.prod_id = %s
                  AND COALESCE(ps.ps_status, p.prod_status, 'Active') = 'Active'
            """
            params = [prod_id]
            if seller_id > 0:
                detail_sql += " AND ps.seller_id = %s"
                params.append(seller_id)
            detail_sql += " ORDER BY ps.seller_id ASC LIMIT 1"

            cur.execute(detail_sql, tuple(params))
            row = cur.fetchone()
            if not row:
                continue

            row = _serialize_row(row)
            row['wishlist_id'] = wish.get('wishlist_id')
            row['user_id'] = user_id
            row['seller_id'] = _safe_int(row.get('seller_id'))
            row['prod_price'] = _safe_float(row.get('prod_price'))
            row['stock_quantity'] = _safe_int(row.get('stock_quantity'))
            row['avg_rating'] = _safe_float(row.get('avg_rating'))
            row['review_count'] = _safe_int(row.get('review_count'))
            row['product_images'] = _image_urls(row.get('prod_image'), row.get('prod_image2'), row.get('prod_image3'))
            row['prod_image_url'] = row['product_images'][0] if row['product_images'] else None
            row['store_logo_url'] = _build_upload_url(row.get('store_logo'), prefer_seller_logo_route=True)
            data.append(row)

        return jsonify(data), 200
    finally:
        cur.close()
        conn.close()


@user_public_bp.route('/api/user/wishlist', methods=['POST'])
@jwt_required()
def add_user_wishlist():
    user_id, auth_error = _current_user_id_required()
    if auth_error:
        return auth_error

    data = request.get_json(silent=True) or {}
    prod_id = _safe_int(data.get('prod_id'))
    seller_id = _normalize_seller_id(data.get('seller_id'))

    if prod_id <= 0:
        return jsonify({'message': 'prod_id is required'}), 400

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)
    try:
        _ensure_wishlist_table(cur)

        cur.execute(
            """
            SELECT p.prod_id
            FROM product p
            WHERE p.prod_id = %s AND p.prod_status = 'Active'
            LIMIT 1
            """,
            (prod_id,),
        )
        product = cur.fetchone()
        if not product:
            conn.rollback()
            return jsonify({'message': 'Product not found'}), 404

        if seller_id > 0:
            cur.execute(
                """
                SELECT seller_id
                FROM product_seller
                WHERE prod_id = %s AND seller_id = %s AND ps_status = 'Active'
                LIMIT 1
                """,
                (prod_id, seller_id),
            )
            seller_row = cur.fetchone()
            if not seller_row:
                conn.rollback()
                return jsonify({'message': 'Seller product not found'}), 404

        write_cur = conn.cursor()
        write_cur.execute(
            """
            INSERT INTO wishlist (user_id, prod_id, seller_id)
            VALUES (%s, %s, %s)
            ON DUPLICATE KEY UPDATE updated_at = CURRENT_TIMESTAMP
            """,
            (user_id, prod_id, seller_id),
        )
        conn.commit()
        write_cur.close()

        return jsonify({'message': 'Added to wishlist', 'user_id': user_id, 'prod_id': prod_id, 'seller_id': seller_id}), 200
    except Exception as e:
        conn.rollback()
        return jsonify({'message': f'Error adding wishlist item: {str(e)}'}), 500
    finally:
        cur.close()
        conn.close()


@user_public_bp.route('/api/user/wishlist', methods=['DELETE'])
@jwt_required()
def remove_user_wishlist():
    user_id, auth_error = _current_user_id_required()
    if auth_error:
        return auth_error

    data = request.get_json(silent=True) or {}
    prod_id = _safe_int(data.get('prod_id'))
    seller_id = _normalize_seller_id(data.get('seller_id'))

    if prod_id <= 0:
        return jsonify({'message': 'prod_id is required'}), 400

    conn = get_db_connection()
    cur = conn.cursor()
    try:
        _ensure_wishlist_table(cur)
        cur.execute(
            """
            DELETE FROM wishlist
            WHERE user_id = %s AND prod_id = %s AND seller_id = %s
            """,
            (user_id, prod_id, seller_id),
        )
        conn.commit()
        return jsonify({'message': 'Removed from wishlist', 'user_id': user_id, 'prod_id': prod_id, 'seller_id': seller_id}), 200
    except Exception as e:
        conn.rollback()
        return jsonify({'message': f'Error removing wishlist item: {str(e)}'}), 500
    finally:
        cur.close()
        conn.close()


@user_public_bp.route('/api/categories/public', methods=['GET'])
def public_categories():
    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)
    try:
        cur.execute("""
            SELECT category_id, category_name, description, category_image, status
            FROM category
            WHERE status = 'active'
            ORDER BY category_name ASC
        """)
        rows = cur.fetchall() or []

        data = []
        for row in rows:
            row = _serialize_row(row)
            row['category_image_url'] = _build_upload_url(row.get('category_image'))
            data.append(row)

        return jsonify(data), 200
    finally:
        cur.close()
        conn.close()


@user_public_bp.route('/api/products/public', methods=['GET'])
def public_products():
    category_id = request.args.get('category_id', type=int)
    seller_id = request.args.get('seller_id', type=int)
    search = (request.args.get('search') or '').strip()
    nearby_user_id = request.args.get('nearby_user_id', type=int)
    nearby_only = _safe_bool(request.args.get('nearby_only')) or _is_nearby_search(search)

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)
    try:
        user_pincode = None
        if nearby_user_id is not None:
            cur.execute("SELECT pincode FROM user WHERE user_id = %s LIMIT 1", (nearby_user_id,))
            user_row = cur.fetchone() or {}
            user_pincode = str(user_row.get('pincode') or '').strip()
            if not user_pincode:
                nearby_only = False

        sql = """
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
                COALESCE(ps.ps_status, p.prod_status) AS prod_status,
                ps.seller_id,
                s.seller_name,
                s.shop_name,
                s.store_logo,
                s.pincode AS seller_pincode,
                COALESCE(reviews.avg_rating, 0) AS avg_rating,
                COALESCE(reviews.review_count, 0) AS review_count,
                COALESCE(sales.total_sold_qty, 0) AS total_sold_qty,
                COALESCE(sales.total_orders, 0) AS total_orders,
                CASE
                    WHEN %s IS NOT NULL AND COALESCE(CAST(s.pincode AS CHAR), '') = %s THEN 1
                    ELSE 0
                END AS is_nearby
            FROM product p
            LEFT JOIN category c ON c.category_id = p.category_id
            LEFT JOIN (
                SELECT prod_id, seller_id, stock_qty, selling_price, ps_status
                FROM product_seller
            ) ps ON ps.prod_id = p.prod_id
            LEFT JOIN seller s ON s.seller_id = ps.seller_id
            LEFT JOIN (
                SELECT
                    prod_id,
                    seller_id,
                    ROUND(AVG(rating), 1) AS avg_rating,
                    COUNT(*) AS review_count
                FROM product_reviews
                GROUP BY prod_id, seller_id
            ) reviews ON reviews.prod_id = p.prod_id AND reviews.seller_id = COALESCE(ps.seller_id, 0)
            LEFT JOIN (
                SELECT
                    c.prod_id,
                    c.seller_id,
                    SUM(COALESCE(c.quantity, 0)) AS total_sold_qty,
                    COUNT(DISTINCT o.order_id) AS total_orders
                FROM orders o
                INNER JOIN cart c ON c.cart_id = o.cart_id
                WHERE LOWER(COALESCE(o.order_status, '')) IN ('delivered', 'outfordelivery', 'packed', 'confirmed', 'pending')
                GROUP BY c.prod_id, c.seller_id
            ) sales ON sales.prod_id = p.prod_id AND sales.seller_id = ps.seller_id
            WHERE 1=1
              AND COALESCE(ps.ps_status, p.prod_status, 'Active') = 'Active'
        """
        params = [user_pincode, user_pincode]

        if category_id is not None:
            sql += " AND p.category_id = %s"
            params.append(category_id)
        if seller_id is not None:
            sql += " AND ps.seller_id = %s"
            params.append(seller_id)
        if search and not _is_nearby_search(search):
            like = f"%{search}%"
            sql += " AND (p.prod_name LIKE %s OR p.brand LIKE %s OR p.description LIKE %s OR c.category_name LIKE %s)"
            params.extend([like, like, like, like])
        if nearby_only and user_pincode:
            sql += " AND COALESCE(CAST(s.pincode AS CHAR), '') = %s"
            params.append(user_pincode)

        sql += " ORDER BY is_nearby DESC, total_sold_qty DESC, total_orders DESC, p.prod_id DESC, ps.seller_id ASC"
        cur.execute(sql, tuple(params))
        rows = cur.fetchall() or []

        data = []
        for row in rows:
            row = _serialize_row(row)
            row['prod_price'] = float(row.get('prod_price') or 0)
            row['avg_rating'] = _safe_float(row.get('avg_rating'))
            row['review_count'] = _safe_int(row.get('review_count'))
            row['stock_quantity'] = _safe_int(row.get('stock_quantity'))
            row['avg_rating'] = _safe_float(row.get('avg_rating'))
            row['review_count'] = _safe_int(row.get('review_count'))
            row['total_sold_qty'] = _safe_int(row.get('total_sold_qty'))
            row['total_orders'] = _safe_int(row.get('total_orders'))
            row['is_nearby'] = bool(_safe_int(row.get('is_nearby')))
            row['product_images'] = _image_urls(row.get('prod_image'), row.get('prod_image2'), row.get('prod_image3'))
            row['prod_image_url'] = row['product_images'][0] if row['product_images'] else None
            row['store_logo_url'] = _build_upload_url(row.get('store_logo'), prefer_seller_logo_route=True)
            data.append(row)

        return jsonify(data), 200
    finally:
        cur.close()
        conn.close()


@user_public_bp.route('/api/products/public/<int:prod_id>', methods=['GET'])
def public_product_detail(prod_id):
    seller_id = request.args.get('seller_id', type=int)

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)
    try:
        sql = """
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
                COALESCE(ps.ps_status, p.prod_status) AS prod_status,
                ps.seller_id,
                s.seller_name,
                s.shop_name,
                s.shop_address,
                s.seller_mobile,
                s.seller_email,
                s.store_logo,
                COALESCE(reviews.avg_rating, 0) AS avg_rating,
                COALESCE(reviews.review_count, 0) AS review_count
            FROM product p
            LEFT JOIN category c ON c.category_id = p.category_id
            LEFT JOIN product_seller ps ON ps.prod_id = p.prod_id
            LEFT JOIN seller s ON s.seller_id = ps.seller_id
            LEFT JOIN (
                SELECT
                    prod_id,
                    seller_id,
                    ROUND(AVG(rating), 1) AS avg_rating,
                    COUNT(*) AS review_count
                FROM product_reviews
                GROUP BY prod_id, seller_id
            ) reviews ON reviews.prod_id = p.prod_id AND reviews.seller_id = COALESCE(ps.seller_id, 0)
            WHERE p.prod_id = %s
              AND COALESCE(ps.ps_status, p.prod_status, 'Active') = 'Active'
        """
        params = [prod_id]
        if seller_id is not None:
            sql += " AND ps.seller_id = %s"
            params.append(seller_id)
        sql += " ORDER BY ps.seller_id ASC LIMIT 1"

        cur.execute(sql, tuple(params))
        row = cur.fetchone()
        if not row:
            return jsonify({'message': 'Product not found'}), 404

        row = _serialize_row(row)
        row['prod_price'] = float(row.get('prod_price') or 0)
        row['stock_quantity'] = _safe_int(row.get('stock_quantity'))
        row['product_images'] = _image_urls(row.get('prod_image'), row.get('prod_image2'), row.get('prod_image3'))
        row['prod_image_url'] = row['product_images'][0] if row['product_images'] else None
        row['store_logo_url'] = _build_upload_url(row.get('store_logo'), prefer_seller_logo_route=True)
        return jsonify(row), 200
    finally:
        cur.close()
        conn.close()


@user_public_bp.route('/api/sellers/public', methods=['GET'])
def public_sellers():
    search = (request.args.get('search') or '').strip()
    nearby_user_id = request.args.get('nearby_user_id', type=int)
    nearby_only = _safe_bool(request.args.get('nearby_only')) or _is_nearby_search(search)

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)
    try:
        user_pincode = None
        if nearby_user_id is not None:
            cur.execute("SELECT pincode FROM user WHERE user_id = %s LIMIT 1", (nearby_user_id,))
            user_row = cur.fetchone() or {}
            user_pincode = str(user_row.get('pincode') or '').strip()
            if not user_pincode:
                nearby_only = False

        cur.execute("""
            SELECT
                s.seller_id,
                s.seller_name,
                s.shop_name,
                s.shop_address,
                s.seller_mobile,
                s.seller_email,
                s.store_logo,
                s.pincode,
                s.status,
                COALESCE(seller_sales.total_sold_qty, 0) AS total_sold_qty,
                COALESCE(seller_sales.total_orders, 0) AS delivered_orders,
                COUNT(DISTINCT CASE WHEN COALESCE(ps.ps_status, 'Active') = 'Active' THEN ps.prod_id END) AS total_products,
                CASE
                    WHEN %s IS NOT NULL AND COALESCE(CAST(s.pincode AS CHAR), '') = %s THEN 1
                    ELSE 0
                END AS is_nearby
            FROM seller s
            LEFT JOIN product_seller ps ON ps.seller_id = s.seller_id
            LEFT JOIN (
                SELECT
                    o.seller_id,
                    SUM(COALESCE(c.quantity, 0)) AS total_sold_qty,
                    COUNT(DISTINCT o.order_id) AS total_orders
                FROM orders o
                INNER JOIN cart c ON c.cart_id = o.cart_id
                WHERE LOWER(COALESCE(o.order_status, '')) IN ('delivered', 'outfordelivery', 'packed', 'confirmed', 'pending')
                GROUP BY o.seller_id
            ) seller_sales ON seller_sales.seller_id = s.seller_id
            WHERE LOWER(COALESCE(s.status, 'active')) = 'active'
            """ + (" AND (s.seller_name LIKE %s OR s.shop_name LIKE %s OR s.shop_address LIKE %s)" if search and not _is_nearby_search(search) else "") + (" AND COALESCE(CAST(s.pincode AS CHAR), '') = %s" if nearby_only and user_pincode else "") + """
            GROUP BY s.seller_id, s.seller_name, s.shop_name, s.shop_address, s.seller_mobile, s.seller_email, s.store_logo, s.pincode, s.status, seller_sales.total_sold_qty, seller_sales.total_orders
            ORDER BY is_nearby DESC, total_sold_qty DESC, delivered_orders DESC, total_products DESC, s.seller_id DESC
        """, tuple([user_pincode, user_pincode] + ([f'%{search}%', f'%{search}%', f'%{search}%'] if search and not _is_nearby_search(search) else []) + ([user_pincode] if nearby_only and user_pincode else [])))
        rows = cur.fetchall() or []

        data = []
        for row in rows:
            row = _serialize_row(row)
            row['total_sold_qty'] = _safe_int(row.get('total_sold_qty'))
            row['delivered_orders'] = _safe_int(row.get('delivered_orders'))
            row['total_products'] = _safe_int(row.get('total_products'))
            row['is_nearby'] = bool(_safe_int(row.get('is_nearby')))
            row['store_logo_url'] = _build_upload_url(row.get('store_logo'), prefer_seller_logo_route=True)
            data.append(row)
        return jsonify(data), 200
    finally:
        cur.close()
        conn.close()


@user_public_bp.route('/api/sellers/public/<int:seller_id>', methods=['GET'])
def public_seller_detail(seller_id):
    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)
    try:
        cur.execute("""
            SELECT seller_id, seller_name, shop_name, shop_address, seller_mobile,
                   seller_email, store_logo, status
            FROM seller
            WHERE seller_id = %s AND COALESCE(status, 'Active') = 'Active'
            LIMIT 1
        """, (seller_id,))
        seller = cur.fetchone()
        if not seller:
            return jsonify({'message': 'Seller not found'}), 404

        cur.execute("""
            SELECT COUNT(DISTINCT ps.prod_id) AS total_products
            FROM product_seller ps
            WHERE ps.seller_id = %s AND COALESCE(ps.ps_status, 'Active') = 'Active'
        """, (seller_id,))
        count_row = cur.fetchone() or {}

        seller = _serialize_row(seller)
        seller['store_logo_url'] = _build_upload_url(seller.get('store_logo'), prefer_seller_logo_route=True)
        seller['total_products'] = _safe_int(count_row.get('total_products'))
        return jsonify(seller), 200
    finally:
        cur.close()
        conn.close()


@user_public_bp.route('/api/sellers/public/<int:seller_id>/products', methods=['GET'])
def public_seller_products(seller_id):
    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)
    try:
        cur.execute("""
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
                COALESCE(ps.ps_status, p.prod_status) AS prod_status,
                ps.seller_id,
                COALESCE(reviews.avg_rating, 0) AS avg_rating,
                COALESCE(reviews.review_count, 0) AS review_count
            FROM product p
            INNER JOIN product_seller ps ON ps.prod_id = p.prod_id
            LEFT JOIN category c ON c.category_id = p.category_id
            LEFT JOIN (
                SELECT
                    prod_id,
                    seller_id,
                    ROUND(AVG(rating), 1) AS avg_rating,
                    COUNT(*) AS review_count
                FROM product_reviews
                GROUP BY prod_id, seller_id
            ) reviews ON reviews.prod_id = p.prod_id AND reviews.seller_id = COALESCE(ps.seller_id, 0)
            WHERE ps.seller_id = %s
              AND COALESCE(ps.ps_status, p.prod_status, 'Active') = 'Active'
            ORDER BY p.prod_id DESC
        """, (seller_id,))
        rows = cur.fetchall() or []

        data = []
        for row in rows:
            row = _serialize_row(row)
            row['prod_price'] = float(row.get('prod_price') or 0)
            row['avg_rating'] = _safe_float(row.get('avg_rating'))
            row['review_count'] = _safe_int(row.get('review_count'))
            row['stock_quantity'] = _safe_int(row.get('stock_quantity'))
            row['product_images'] = _image_urls(row.get('prod_image'), row.get('prod_image2'), row.get('prod_image3'))
            row['prod_image_url'] = row['product_images'][0] if row['product_images'] else None
            data.append(row)
        return jsonify(data), 200
    finally:
        cur.close()
        conn.close()
 

@user_public_bp.route('/api/reviews/product/<int:prod_id>', methods=['GET'])
def get_product_reviews(prod_id):
    seller_id = _normalize_seller_id(request.args.get('seller_id', type=int))
    current_user_id = _current_user_id_optional()

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)
    try:
        _ensure_product_reviews_table(cur)
        conn.commit()

        cur.execute(
            """
            SELECT
                r.review_id,
                r.user_id,
                r.prod_id,
                r.seller_id,
                r.rating,
                r.review,
                r.created_at,
                r.updated_at,
                u.user_name
            FROM product_reviews r
            LEFT JOIN user u ON u.user_id = r.user_id
            WHERE r.prod_id = %s AND r.seller_id = %s
            ORDER BY r.updated_at DESC, r.created_at DESC
            """,
            (prod_id, seller_id),
        )
        review_rows = [_serialize_row(row) for row in (cur.fetchall() or [])]

        cur.execute(
            """
            SELECT ROUND(AVG(rating), 1) AS avg_rating, COUNT(*) AS review_count
            FROM product_reviews
            WHERE prod_id = %s AND seller_id = %s
            """,
            (prod_id, seller_id),
        )
        stats = cur.fetchone() or {}

        user_review = None
        can_review = False
        if current_user_id is not None:
            user_review = _fetch_user_review(cur, current_user_id, prod_id, seller_id)
            can_review = _user_can_review_product(cur, current_user_id, prod_id, seller_id)

        return jsonify({
            'success': True,
            'prod_id': prod_id,
            'seller_id': seller_id,
            'avg_rating': _safe_float(stats.get('avg_rating')),
            'review_count': _safe_int(stats.get('review_count')),
            'user_review': user_review,
            'can_review': can_review,
            'reviews': review_rows,
        }), 200
    finally:
        cur.close()
        conn.close()


@user_public_bp.route('/api/reviews', methods=['POST'])
@jwt_required()
def add_product_review():
    if not _is_user():
        return jsonify({'success': False, 'message': 'Access denied. User only.'}), 403

    user_id = int(get_jwt_identity())
    data = request.get_json(silent=True) or {}
    prod_id = _safe_int(data.get('prod_id'))
    seller_id = _normalize_seller_id(data.get('seller_id'))
    rating = _safe_int(data.get('rating'))
    review = str(data.get('review') or '').strip()

    if prod_id <= 0:
        return jsonify({'success': False, 'message': 'Valid prod_id is required'}), 400
    if rating < 1 or rating > 5:
        return jsonify({'success': False, 'message': 'Rating must be between 1 and 5'}), 400

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)
    try:
        _ensure_product_reviews_table(cur)
        conn.commit()

        if not _user_can_review_product(cur, user_id, prod_id, seller_id):
            return jsonify({'success': False, 'message': 'You can review only delivered products purchased by you'}), 403

        existing = _fetch_user_review(cur, user_id, prod_id, seller_id)
        if existing:
            return jsonify({'success': False, 'message': 'Review already exists. Please edit your review instead.'}), 400

        write_cur = conn.cursor()
        write_cur.execute(
            """
            INSERT INTO product_reviews (user_id, prod_id, seller_id, rating, review)
            VALUES (%s, %s, %s, %s, %s)
            """,
            (user_id, prod_id, seller_id, rating, review),
        )
        conn.commit()
        write_cur.close()

        created = _fetch_user_review(cur, user_id, prod_id, seller_id)
        return jsonify({'success': True, 'message': 'Review submitted successfully', 'review': created}), 200
    finally:
        cur.close()
        conn.close()


@user_public_bp.route('/api/reviews', methods=['PUT'])
@jwt_required()
def update_product_review():
    if not _is_user():
        return jsonify({'success': False, 'message': 'Access denied. User only.'}), 403

    user_id = int(get_jwt_identity())
    data = request.get_json(silent=True) or {}
    prod_id = _safe_int(data.get('prod_id'))
    seller_id = _normalize_seller_id(data.get('seller_id'))
    rating = _safe_int(data.get('rating'))
    review = str(data.get('review') or '').strip()

    if prod_id <= 0:
        return jsonify({'success': False, 'message': 'Valid prod_id is required'}), 400
    if rating < 1 or rating > 5:
        return jsonify({'success': False, 'message': 'Rating must be between 1 and 5'}), 400

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)
    try:
        _ensure_product_reviews_table(cur)
        conn.commit()

        if not _user_can_review_product(cur, user_id, prod_id, seller_id):
            return jsonify({'success': False, 'message': 'You can review only delivered products purchased by you'}), 403

        existing = _fetch_user_review(cur, user_id, prod_id, seller_id)
        if not existing:
            return jsonify({'success': False, 'message': 'Review not found'}), 404

        write_cur = conn.cursor()
        write_cur.execute(
            """
            UPDATE product_reviews
            SET rating = %s, review = %s
            WHERE user_id = %s AND prod_id = %s AND seller_id = %s
            """,
            (rating, review, user_id, prod_id, seller_id),
        )
        conn.commit()
        write_cur.close()

        updated = _fetch_user_review(cur, user_id, prod_id, seller_id)
        return jsonify({'success': True, 'message': 'Review updated successfully', 'review': updated}), 200
    finally:
        cur.close()
        conn.close()
