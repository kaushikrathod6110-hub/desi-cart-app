from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required, get_jwt
from db import get_db_connection
from datetime import datetime, timedelta
from decimal import Decimal

reports_bp = Blueprint("reports_bp", __name__)


def _is_admin():
    return get_jwt().get("role") == "admin"


def _num(v):
    if v is None:
        return 0
    if isinstance(v, Decimal):
        return float(v)
    return float(v)


def _safe_int(v):
    return int(v or 0)


def _get_range_dates(rng: str):
    now = datetime.now()
    if rng == "today":
        start = now.replace(hour=0, minute=0, second=0, microsecond=0)
        end = now
    elif rng == "yesterday":
        yesterday = now - timedelta(days=1)
        start = yesterday.replace(hour=0, minute=0, second=0, microsecond=0)
        end = yesterday.replace(hour=23, minute=59, second=59, microsecond=999999)
    elif rng == "month":
        start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        end = now
    else:
        start = now - timedelta(days=7)
        end = now
    return start, end


def _parse_date_param(value: str | None):
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


def _resolve_report_dates():
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

    rng = (request.args.get("range") or "today").strip().lower()
    if rng == "7d":
        rng = "week"
    start, end = _get_range_dates(rng)
    return rng, start, end


def _status_count_map(rows, key_name):
    result = {}
    for r in rows:
        key = (r.get(key_name) or "Unknown").strip()
        result[key] = int(r.get("cnt") or 0)
    return result


def _table_exists(cur, table_name):
    cur.execute("SHOW TABLES LIKE %s", (table_name,))
    return cur.fetchone() is not None


def _column_exists(cur, table_name, column_name):
    cur.execute(f"SHOW COLUMNS FROM `{table_name}` LIKE %s", (column_name,))
    return cur.fetchone() is not None


def _first_existing_column(cur, table_name, candidates):
    for column_name in candidates:
        if _column_exists(cur, table_name, column_name):
            return column_name
    return None


def _order_item_name_column(cur):
    return _first_existing_column(
        cur,
        "order_items",
        [
            "product_name",
            "prod_name",
            "name",
            "item_name",
            "title",
            "product_title",
        ],
    )


def _order_product_name_column(cur):
    return _first_existing_column(cur, "orders", ["product_name", "prod_name", "name", "title", "product_title"])


def _order_product_id_column(cur):
    return _first_existing_column(cur, "orders", ["product_id", "prod_id"])


def _existing_columns(cur, table_name, candidates):
    found = []
    for column_name in candidates:
        if _column_exists(cur, table_name, column_name):
            found.append(column_name)
    return found


def _to_iso(v):
    return v.isoformat() if v else None


def _profile_date_column(cur, table_name):
    return _first_existing_column(
        cur,
        table_name,
        [
            "registration_at",
            "created_at",
            "created_date",
            "created_on",
            "register_at",
            "registered_at",
            "joined_at",
            "date_created",
        ],
    )


def _fetch_user_profile(cur, user_id):
    date_col = _profile_date_column(cur, "user")
    if date_col:
        cur.execute(
            f"""
            SELECT user_id, user_name, user_email, user_mobile, `{date_col}` AS registration_at
            FROM user
            WHERE user_id = %s
            """,
            (user_id,),
        )
    else:
        cur.execute(
            """
            SELECT user_id, user_name, user_email, user_mobile
            FROM user
            WHERE user_id = %s
            """,
            (user_id,),
        )
    user = cur.fetchone()
    if user and "registration_at" not in user:
        user["registration_at"] = None
    return user


def _fetch_seller_profile(cur, seller_id):
    date_col = _profile_date_column(cur, "seller")
    if date_col:
        cur.execute(
            f"""
            SELECT seller_id, seller_name, seller_email, seller_mobile, `{date_col}` AS registration_at
            FROM seller
            WHERE seller_id = %s
            """,
            (seller_id,),
        )
    else:
        cur.execute(
            """
            SELECT seller_id, seller_name, seller_email, seller_mobile
            FROM seller
            WHERE seller_id = %s
            """,
            (seller_id,),
        )
    seller = cur.fetchone()
    if seller and "registration_at" not in seller:
        seller["registration_at"] = None
    return seller


def _product_name_value(row):
    return (
        row.get("product_name")
        or row.get("name")
        or row.get("prod_name")
        or row.get("title")
        or row.get("product_title")
        or ""
    )


def _product_price_value(row):
    return row.get("price") if row.get("price") is not None else row.get("prod_price")


def _product_image_value(row):
    return row.get("product_image") or row.get("prod_image")


def _product_status_value(row):
    return row.get("status") or row.get("prod_status")


def _product_id_column(cur):
    return _first_existing_column(cur, "product", ["product_id", "prod_id"])

def _product_seller_columns(cur):
    if not _table_exists(cur, "product_seller"):
        return None, None
    return (
        _first_existing_column(cur, "product_seller", ["prod_id", "product_id"]),
        _first_existing_column(cur, "product_seller", ["seller_id"]),
    )


def _product_seller_ids(cur, product_id):
    ps_product_col, ps_seller_col = _product_seller_columns(cur)
    if not ps_product_col or not ps_seller_col or product_id is None:
        return []
    cur.execute(
        f"SELECT DISTINCT `{ps_seller_col}` AS seller_id FROM product_seller WHERE `{ps_product_col}` = %s ORDER BY `{ps_seller_col}`",
        (product_id,),
    )
    return [int(r["seller_id"]) for r in cur.fetchall() if r.get("seller_id") is not None]


def _single_product_seller_id(cur, product_id):
    seller_ids = _product_seller_ids(cur, product_id)
    if len(seller_ids) == 1:
        return seller_ids[0]
    return None


def _product_stock_value(row):
    if row.get("stock_quantity") is not None:
        return row.get("stock_quantity")
    if row.get("stock_qty") is not None:
        return row.get("stock_qty")
    if row.get("stock") is not None:
        return row.get("stock")
    return row.get("quantity")

def _row_has_product_identity(row):
    if not row:
        return False
    product_id = row.get("product_id") if row.get("product_id") is not None else row.get("prod_id")
    if product_id is not None:
        return True
    return bool(_product_name_value(row).strip())


def _minimal_product_row(name, total_amount=0, seller_id=None, ordered_qty=1, ordered_price=None, ordered_total=None):
    clean_name = str(name or "").strip()
    if not clean_name:
        clean_name = "Product Not Available"
    total_value = _num(total_amount)
    ordered_price_value = total_value if ordered_price is None else _num(ordered_price)
    ordered_total_value = total_value if ordered_total is None else _num(ordered_total)
    return {
        "product_id": None,
        "product_name": clean_name,
        "description": None,
        "price": total_value,
        "stock": 0,
        "quantity": None,
        "unit_type": None,
        "brand": None,
        "category_id": None,
        "seller_id": seller_id,
        "product_image": None,
        "status": None,
        "ordered_qty": ordered_qty,
        "ordered_price": ordered_price_value,
        "ordered_total": ordered_total_value,
    }


def _seller_product_count(cur, seller_id):
    ps_product_col, ps_seller_col = _product_seller_columns(cur)
    if not ps_product_col or not ps_seller_col or seller_id is None:
        return 0
    cur.execute(
        f"""
        SELECT COUNT(DISTINCT `{ps_product_col}`) AS total_products
        FROM product_seller
        WHERE `{ps_seller_col}` = %s
        """,
        (seller_id,),
    )
    row = cur.fetchone() or {}
    return _safe_int(row.get("total_products"))


def _seller_product_rows(cur, seller_id):
    rows_by_id = {}
    if seller_id is None or not _table_exists(cur, "product"):
        return []

    product_id_col = _product_id_column(cur)
    product_name_col = _first_existing_column(cur, "product", ["prod_name", "product_name", "name", "title", "product_title"])
    price_col = _first_existing_column(cur, "product", ["prod_price", "price"])
    stock_col = _first_existing_column(cur, "product", ["stock_quantity", "stock_qty", "stock", "quantity"])
    ps_product_col, ps_seller_col = _product_seller_columns(cur)
    ps_stock_col = _first_existing_column(cur, "product_seller", ["stock_qty"]) if _table_exists(cur, "product_seller") else None
    ps_price_col = _first_existing_column(cur, "product_seller", ["selling_price"]) if _table_exists(cur, "product_seller") else None
    ps_status_col = _first_existing_column(cur, "product_seller", ["ps_status"]) if _table_exists(cur, "product_seller") else None

    if not product_id_col or not product_name_col or not ps_product_col or not ps_seller_col:
        return []

    cur.execute(
        f"""
        SELECT
            p.`{product_id_col}` AS product_id,
            p.`{product_name_col}` AS product_name,
            {f'COALESCE(ps.`{ps_price_col}`, p.`{price_col}`) AS product_price,' if price_col and ps_price_col else (f'ps.`{ps_price_col}` AS product_price,' if ps_price_col else (f'p.`{price_col}` AS product_price,' if price_col else '0 AS product_price,'))}
            {f'COALESCE(ps.`{ps_stock_col}`, p.`{stock_col}`) AS stock_value,' if stock_col and ps_stock_col else (f'ps.`{ps_stock_col}` AS stock_value,' if ps_stock_col else (f'p.`{stock_col}` AS stock_value,' if stock_col else '0 AS stock_value,'))}
            {f'ps.`{ps_status_col}` AS mapping_status,' if ps_status_col else 'NULL AS mapping_status,'}
            ps.`{ps_seller_col}` AS seller_id
        FROM product_seller ps
        LEFT JOIN product p ON p.`{product_id_col}` = ps.`{ps_product_col}`
        WHERE ps.`{ps_seller_col}` = %s
        ORDER BY p.`{product_id_col}`
        """,
        (seller_id,),
    )

    for row in cur.fetchall():
        pid = row.get("product_id")
        if pid is not None:
            rows_by_id[int(pid)] = row

    return list(rows_by_id.values())


def _cart_product_id_column(cur):
    return _first_existing_column(cur, "cart", ["product_id", "prod_id"])



def _cart_product_name_column(cur):
    return _first_existing_column(cur, "cart", ["product_name", "prod_name", "name", "title", "product_title"])



def _cart_quantity_column(cur):
    return _first_existing_column(cur, "cart", ["quantity", "qty"])



def _cart_price_column(cur):
    return _first_existing_column(cur, "cart", ["price", "unit_price", "product_price", "subtotal", "amount", "total_amount"])



def _infer_products_from_order(cur, order_id):
    if not _table_exists(cur, "orders"):
        return []

    order_product_col = _order_product_id_column(cur)
    order_name_col = _order_product_name_column(cur)
    seller_col = _first_existing_column(cur, "orders", ["seller_id"])
    cart_col = _first_existing_column(cur, "orders", ["cart_id"])

    select_parts = ["order_id", "total_amount"]
    if order_product_col:
        select_parts.append(f"`{order_product_col}` AS order_product_id")
    else:
        select_parts.append("NULL AS order_product_id")
    if order_name_col:
        select_parts.append(f"`{order_name_col}` AS order_product_name")
    else:
        select_parts.append("NULL AS order_product_name")
    if seller_col:
        select_parts.append(f"`{seller_col}` AS seller_id")
    else:
        select_parts.append("NULL AS seller_id")
    if cart_col:
        select_parts.append(f"`{cart_col}` AS cart_id")
    else:
        select_parts.append("NULL AS cart_id")

    cur.execute(f"SELECT {', '.join(select_parts)} FROM orders WHERE order_id = %s LIMIT 1", (order_id,))
    order_row = cur.fetchone() or {}
    if not order_row:
        return []

    products = []
    product_id = order_row.get("order_product_id")
    if product_id is not None:
        base = _get_product_base_row(cur, product_id)
        if base:
            price_val = _product_price_value(base)
            stock_val = _product_stock_value(base)
            products.append({
                "product_id": base.get("product_id") if base.get("product_id") is not None else base.get("prod_id"),
                "product_name": _product_name_value(base) or (order_row.get("order_product_name") or "").strip(),
                "description": base.get("description"),
                "price": _num(price_val) if price_val is not None else _num(order_row.get("total_amount")),
                "stock": _safe_int(stock_val) if stock_val is not None else 0,
                "quantity": base.get("quantity"),
                "unit_type": base.get("unit_type"),
                "brand": base.get("brand"),
                "category_id": base.get("category_id"),
                "seller_id": _single_product_seller_id(cur, base.get("product_id") if base.get("product_id") is not None else base.get("prod_id")) if (base.get("product_id") is not None or base.get("prod_id") is not None) else order_row.get("seller_id"),
                "product_image": _product_image_value(base),
                "status": _product_status_value(base),
                "ordered_qty": 1,
                "ordered_price": _num(order_row.get("total_amount")),
                "ordered_total": _num(order_row.get("total_amount")),
            })
            return products

    order_name = (order_row.get("order_product_name") or "").strip()
    if order_name:
        products.append({
            "product_id": None,
            "product_name": order_name,
            "description": None,
            "price": _num(order_row.get("total_amount")),
            "stock": 0,
            "quantity": None,
            "unit_type": None,
            "brand": None,
            "category_id": None,
            "seller_id": order_row.get("seller_id"),
            "product_image": None,
            "status": None,
            "ordered_qty": 1,
            "ordered_price": _num(order_row.get("total_amount")),
            "ordered_total": _num(order_row.get("total_amount")),
        })
        return products

    if _table_exists(cur, "cart") and order_row.get("cart_id") is not None:
        cart_product_col = _cart_product_id_column(cur)
        cart_name_col = _cart_product_name_column(cur)
        cart_qty_col = _cart_quantity_column(cur)
        cart_price_col = _cart_price_column(cur)
        cart_select_parts = []
        if cart_product_col:
            cart_select_parts.append(f"`{cart_product_col}` AS cart_product_id")
        else:
            cart_select_parts.append("NULL AS cart_product_id")
        if cart_name_col:
            cart_select_parts.append(f"`{cart_name_col}` AS cart_product_name")
        else:
            cart_select_parts.append("NULL AS cart_product_name")
        if cart_qty_col:
            cart_select_parts.append(f"`{cart_qty_col}` AS cart_qty")
        else:
            cart_select_parts.append("1 AS cart_qty")
        if cart_price_col:
            cart_select_parts.append(f"`{cart_price_col}` AS cart_price")
        else:
            cart_select_parts.append("NULL AS cart_price")

        cur.execute(
            f"SELECT {', '.join(cart_select_parts)} FROM cart WHERE cart_id = %s LIMIT 1",
            (order_row.get("cart_id"),),
        )
        cart_row = cur.fetchone() or {}

        cart_product_id = cart_row.get("cart_product_id")
        if cart_product_id is not None:
            base = _get_product_base_row(cur, cart_product_id)
            if base:
                price_val = _product_price_value(base)
                stock_val = _product_stock_value(base)
                ordered_qty = _safe_int(cart_row.get("cart_qty")) if cart_row.get("cart_qty") is not None else 1
                ordered_price = cart_row.get("cart_price") if cart_row.get("cart_price") is not None else price_val
                ordered_total = order_row.get("total_amount")
                return [{
                    "product_id": base.get("product_id") if base.get("product_id") is not None else base.get("prod_id"),
                    "product_name": _product_name_value(base) or (cart_row.get("cart_product_name") or "").strip(),
                    "description": base.get("description"),
                    "price": _num(price_val) if price_val is not None else _num(ordered_total),
                    "stock": _safe_int(stock_val) if stock_val is not None else 0,
                    "quantity": base.get("quantity"),
                    "unit_type": base.get("unit_type"),
                    "brand": base.get("brand"),
                    "category_id": base.get("category_id"),
                    "seller_id": _single_product_seller_id(cur, base.get("product_id") if base.get("product_id") is not None else base.get("prod_id")) if (base.get("product_id") is not None or base.get("prod_id") is not None) else order_row.get("seller_id"),
                    "product_image": _product_image_value(base),
                    "status": _product_status_value(base),
                    "ordered_qty": ordered_qty,
                    "ordered_price": _num(ordered_price) if ordered_price is not None else None,
                    "ordered_total": _num(ordered_total),
                }]

        cart_name = (cart_row.get("cart_product_name") or "").strip()
        if cart_name:
            return [_minimal_product_row(
                cart_name,
                total_amount=order_row.get("total_amount"),
                seller_id=order_row.get("seller_id"),
                ordered_qty=_safe_int(cart_row.get("cart_qty")) if cart_row.get("cart_qty") is not None else 1,
                ordered_price=cart_row.get("cart_price"),
                ordered_total=order_row.get("total_amount"),
            )]

    seller_products = _seller_product_rows(cur, order_row.get("seller_id"))
    if len(seller_products) == 1:
        row = seller_products[0]
        row_name = (row.get("product_name") or "").strip()
        if row_name:
            price_val = row.get("product_price") if row.get("product_price") is not None else order_row.get("total_amount")
            stock_val = row.get("stock_value")
            products.append({
                "product_id": row.get("product_id"),
                "product_name": row_name,
                "description": None,
                "price": _num(price_val) if price_val is not None else 0,
                "stock": _safe_int(stock_val) if stock_val is not None else 0,
                "quantity": None,
                "unit_type": None,
                "brand": None,
                "category_id": None,
                "seller_id": row.get("seller_id") if row.get("seller_id") is not None else order_row.get("seller_id"),
                "product_image": None,
                "status": None,
                "ordered_qty": 1,
                "ordered_price": _num(order_row.get("total_amount")),
                "ordered_total": _num(order_row.get("total_amount")),
            })
            return products

    return []


def _order_product_names(cur, order_id):
    names = []
    seen = set()

    has_order_items = _table_exists(cur, "order_items")
    has_product = _table_exists(cur, "product")

    if has_order_items:
        oi_order_col = _first_existing_column(cur, "order_items", ["order_id"])
        oi_product_col = _first_existing_column(cur, "order_items", ["product_id", "prod_id"])
        oi_name_col = _order_item_name_column(cur)
        if oi_order_col:
            if has_product:
                product_id_col = _product_id_column(cur)
                product_name_col = _first_existing_column(cur, "product", ["prod_name", "product_name", "name", "title", "product_title"])
            else:
                product_id_col = None
                product_name_col = None

            if product_id_col and product_name_col and oi_product_col:
                select_sql = f"""
                    SELECT p.`{product_name_col}` AS product_name,
                           oi.`{oi_name_col}` AS order_item_name
                    FROM order_items oi
                    LEFT JOIN product p ON p.`{product_id_col}` = oi.`{oi_product_col}`
                    WHERE oi.`{oi_order_col}` = %s
                    ORDER BY oi.`{oi_product_col}`
                """ if oi_name_col else f"""
                    SELECT p.`{product_name_col}` AS product_name,
                           NULL AS order_item_name
                    FROM order_items oi
                    LEFT JOIN product p ON p.`{product_id_col}` = oi.`{oi_product_col}`
                    WHERE oi.`{oi_order_col}` = %s
                    ORDER BY oi.`{oi_product_col}`
                """
                cur.execute(select_sql, (order_id,))
            else:
                select_sql = f"""
                    SELECT oi.`{oi_name_col}` AS order_item_name
                    FROM order_items oi
                    WHERE oi.`{oi_order_col}` = %s
                """ if oi_name_col else f"""
                    SELECT NULL AS order_item_name
                    FROM order_items oi
                    WHERE oi.`{oi_order_col}` = %s
                """
                cur.execute(select_sql, (order_id,))

            for row in cur.fetchall():
                name = (row.get("product_name") or row.get("order_item_name") or "").strip()
                if name and name not in seen:
                    names.append(name)
                    seen.add(name)

    if names:
        return names

    inferred_products = _infer_products_from_order(cur, order_id)
    inferred_names = []
    for product in inferred_products:
        name = (product.get("product_name") or "").strip()
        if name and name not in inferred_names:
            inferred_names.append(name)
    if inferred_names:
        return inferred_names

    if _table_exists(cur, "orders"):
        order_name_col = _first_existing_column(cur, "orders", ["product_name", "prod_name", "name", "title", "product_title"])
        if order_name_col:
            cur.execute(
                f"SELECT `{order_name_col}` AS product_name FROM orders WHERE order_id = %s LIMIT 1",
                (order_id,),
            )
            row = cur.fetchone() or {}
            name = (row.get("product_name") or "").strip()
            if name:
                return [name]

    return []


def _unique_strings(values):
    seen = set()
    result = []
    for value in values:
        text = str(value or '').strip()
        if text and text not in seen:
            seen.add(text)
            result.append(text)
    return result


def _grouped_order_status(order_statuses):
    order = {
        'Pending': 0,
        'Confirmed': 1,
        'Packed': 2,
        'OutForDelivery': 3,
        'Delivered': 4,
        'Cancelled': 5,
    }
    values = _unique_strings(order_statuses)
    if not values:
        return ''
    values.sort(key=lambda s: order.get(s, 99))
    return values[0]


def _grouped_products_for_orders(cur, order_ids):
    grouped = []
    seen_keys = set()
    for oid in order_ids:
        products = _get_products_for_order(cur, oid)
        for product in products:
            key = (
                product.get('product_id'),
                (product.get('product_name') or '').strip().lower(),
                product.get('seller_id'),
            )
            if key in seen_keys:
                for item in grouped:
                    item_key = (
                        item.get('product_id'),
                        (item.get('product_name') or '').strip().lower(),
                        item.get('seller_id'),
                    )
                    if item_key == key:
                        existing_ids = item.get('order_ids') if isinstance(item.get('order_ids'), list) else []
                        if oid not in existing_ids:
                            existing_ids.append(oid)
                        item['order_ids'] = existing_ids
                        qty_a = _safe_int(item.get('ordered_qty')) if item.get('ordered_qty') is not None else 0
                        qty_b = _safe_int(product.get('ordered_qty')) if product.get('ordered_qty') is not None else 0
                        item['ordered_qty'] = qty_a + qty_b if (qty_a or qty_b) else None
                        total_a = _num(item.get('ordered_total')) if item.get('ordered_total') is not None else 0
                        total_b = _num(product.get('ordered_total')) if product.get('ordered_total') is not None else 0
                        if total_a or total_b:
                            item['ordered_total'] = total_a + total_b
                        break
                continue
            item = dict(product)
            item['order_ids'] = [oid]
            grouped.append(item)
            seen_keys.add(key)
    return grouped


def _get_product_rating_summary(cur, product_id=None):
    if not _table_exists(cur, "product_reviews"):
        if product_id is None:
            return {}
        return {"avg_rating": 0.0, "review_count": 0}

    if product_id is None:
        cur.execute(
            """
            SELECT prod_id AS product_id,
                   ROUND(AVG(rating), 1) AS avg_rating,
                   COUNT(*) AS review_count
            FROM product_reviews
            GROUP BY prod_id
            """
        )
        return {int(r["product_id"]): {
            "avg_rating": _num(r.get("avg_rating")),
            "review_count": _safe_int(r.get("review_count")),
        } for r in cur.fetchall() if r.get("product_id") is not None}

    cur.execute(
        """
        SELECT ROUND(AVG(rating), 1) AS avg_rating,
               COUNT(*) AS review_count
        FROM product_reviews
        WHERE prod_id = %s
        """,
        (product_id,),
    )
    row = cur.fetchone() or {}
    return {
        "avg_rating": _num(row.get("avg_rating")),
        "review_count": _safe_int(row.get("review_count")),
    }


def _get_product_base_row(cur, product_id):
    id_col = _product_id_column(cur)
    if not id_col:
        return None

    product_columns = _existing_columns(
        cur,
        "product",
        [
            "product_id",
            "prod_id",
            "prod_name",
            "product_name",
            "name",
            "description",
            "prod_price",
            "price",
            "stock_quantity",
            "stock_qty",
            "stock",
            "quantity",
            "unit_type",
            "brand",
            "category_id",
            "seller_id",
            "prod_image",
            "product_image",
            "prod_status",
            "status",
        ],
    )
    if not product_columns:
        return None

    select_parts = [f"`{col}` AS `{col}`" for col in product_columns]
    cur.execute(
        f"SELECT {', '.join(select_parts)} FROM product WHERE `{id_col}` = %s LIMIT 1",
        (product_id,),
    )
    row = cur.fetchone()
    if not row:
        return None

    rating_summary = _get_product_rating_summary(cur, product_id)
    row["avg_rating"] = rating_summary["avg_rating"]
    row["review_count"] = rating_summary["review_count"]
    return row


def _get_products_for_order(cur, order_id):
    products = []
    has_orders = _table_exists(cur, "orders")
    has_product = _table_exists(cur, "product")
    has_order_items = _table_exists(cur, "order_items")

    if has_order_items and has_product:
        oi_order_col = _first_existing_column(cur, "order_items", ["order_id"])
        oi_product_col = _first_existing_column(cur, "order_items", ["product_id", "prod_id"])
        qty_col = _first_existing_column(cur, "order_items", ["quantity", "qty"])
        item_price_col = _first_existing_column(cur, "order_items", ["price", "unit_price", "product_price"])
        item_total_col = _first_existing_column(cur, "order_items", ["subtotal", "amount", "total_amount", "line_total"])
        oi_name_col = _order_item_name_column(cur)

        product_columns = _existing_columns(
            cur,
            "product",
            [
                "product_id",
                "prod_id",
                "prod_name",
                "product_name",
                "name",
                "description",
                "prod_price",
                "price",
                "stock_quantity",
                "stock_qty",
                "stock",
                "quantity",
                "unit_type",
                "brand",
                "category_id",
                "seller_id",
                "prod_image",
                "product_image",
                "prod_status",
                "status",
            ],
        )

        if oi_order_col and oi_product_col and product_columns:
            select_parts = [f"p.`{col}` AS `{col}`" for col in product_columns]
            if qty_col:
                select_parts.append(f"oi.`{qty_col}` AS `ordered_qty`")
            if item_price_col:
                select_parts.append(f"oi.`{item_price_col}` AS `ordered_price`")
            if item_total_col:
                select_parts.append(f"oi.`{item_total_col}` AS `ordered_total`")
            if oi_name_col:
                select_parts.append(f"oi.`{oi_name_col}` AS `order_item_name`")

            product_id_col = _product_id_column(cur)
            cur.execute(
                f"""
                SELECT {", ".join(select_parts)}
                FROM order_items oi
                LEFT JOIN product p ON p.`{product_id_col}` = oi.`{oi_product_col}`
                WHERE oi.`{oi_order_col}` = %s
                ORDER BY p.`{product_id_col}`
                """,
                (order_id,),
            )
            rows = cur.fetchall()

            for row in rows:
                order_item_name = (row.get("order_item_name") or "").strip()
                if _row_has_product_identity(row):
                    price_val = _product_price_value(row)
                    stock_val = _product_stock_value(row)
                    products.append({
                        "product_id": row.get("product_id") if row.get("product_id") is not None else row.get("prod_id"),
                        "product_name": _product_name_value(row) or order_item_name,
                        "description": row.get("description"),
                        "price": _num(price_val) if price_val is not None else _num(row.get("ordered_total") or row.get("ordered_price") or 0),
                        "stock": _safe_int(stock_val) if stock_val is not None else 0,
                        "quantity": row.get("quantity"),
                        "unit_type": row.get("unit_type"),
                        "brand": row.get("brand"),
                        "category_id": row.get("category_id"),
                        "seller_id": _single_product_seller_id(cur, row.get("product_id") or row.get("prod_id")),
                        "product_image": _product_image_value(row),
                        "status": _product_status_value(row),
                        "ordered_qty": _safe_int(row.get("ordered_qty")) if row.get("ordered_qty") is not None else None,
                        "ordered_price": _num(row.get("ordered_price")) if row.get("ordered_price") is not None else None,
                        "ordered_total": _num(row.get("ordered_total")) if row.get("ordered_total") is not None else None,
                    })
                elif order_item_name:
                    products.append(_minimal_product_row(
                        order_item_name,
                        total_amount=row.get("ordered_total") or row.get("ordered_price") or 0,
                        seller_id=None,
                        ordered_qty=_safe_int(row.get("ordered_qty")) if row.get("ordered_qty") is not None else 1,
                        ordered_price=row.get("ordered_price"),
                        ordered_total=row.get("ordered_total") or row.get("ordered_price"),
                    ))
            if products:
                return products

    if has_orders and has_product:
        order_product_col = _first_existing_column(cur, "orders", ["product_id", "prod_id"])
        if order_product_col:
            product_columns = _existing_columns(
                cur,
                "product",
                [
                    "product_id",
                    "prod_id",
                    "prod_name",
                    "product_name",
                    "name",
                    "description",
                    "prod_price",
                    "price",
                    "stock",
                    "quantity",
                    "unit_type",
                    "brand",
                    "category_id",
                    "seller_id",
                    "prod_image",
                    "product_image",
                    "prod_status",
                    "status",
                ],
            )
            if product_columns:
                select_parts = [f"p.`{col}` AS `{col}`" for col in product_columns]
                product_id_col = _product_id_column(cur)
                cur.execute(
                    f"""
                    SELECT {", ".join(select_parts)}
                    FROM orders o
                    LEFT JOIN product p ON p.`{product_id_col}` = o.`{order_product_col}`
                    WHERE o.order_id = %s
                    LIMIT 1
                    """,
                    (order_id,),
                )
                row = cur.fetchone()
                if row and _row_has_product_identity(row):
                    price_val = _product_price_value(row)
                    stock_val = _product_stock_value(row)
                    products.append({
                        "product_id": row.get("product_id") if row.get("product_id") is not None else row.get("prod_id"),
                        "product_name": _product_name_value(row),
                        "description": row.get("description"),
                        "price": _num(price_val) if price_val is not None else 0,
                        "stock": _safe_int(stock_val) if stock_val is not None else 0,
                        "quantity": row.get("quantity"),
                        "unit_type": row.get("unit_type"),
                        "brand": row.get("brand"),
                        "category_id": row.get("category_id"),
                        "seller_id": _single_product_seller_id(cur, row.get("product_id") or row.get("prod_id")),
                        "product_image": _product_image_value(row),
                        "status": _product_status_value(row),
                        "ordered_qty": None,
                        "ordered_price": None,
                        "ordered_total": None,
                    })
                    return products

    inferred_products = _infer_products_from_order(cur, order_id)
    if inferred_products:
        return inferred_products

    if has_orders:
        order_name_col = _first_existing_column(cur, "orders", ["product_name", "prod_name", "name"])
        if order_name_col:
            cur.execute(
                f"SELECT `{order_name_col}` AS product_name FROM orders WHERE order_id = %s LIMIT 1",
                (order_id,),
            )
            row = cur.fetchone()
            if row:
                products.append({
                    "product_id": None,
                    "product_name": row.get("product_name") or "",
                    "description": None,
                    "price": 0,
                    "stock": 0,
                    "quantity": None,
                    "unit_type": None,
                    "brand": None,
                    "category_id": None,
                    "seller_id": None,
                    "product_image": None,
                    "status": None,
                    "ordered_qty": None,
                    "ordered_price": None,
                    "ordered_total": None,
                })
    return products


def _get_product_order_stats(cur, product_id, start, end):
    has_orders = _table_exists(cur, "orders")
    has_order_items = _table_exists(cur, "order_items")
    if not has_orders:
        return {"total_orders": 0, "total_revenue": 0, "last_order_date": None}

    if has_order_items:
        oi_order_col = _first_existing_column(cur, "order_items", ["order_id"])
        oi_product_col = _first_existing_column(cur, "order_items", ["product_id", "prod_id"])
        item_total_col = _first_existing_column(cur, "order_items", ["subtotal", "amount", "total_amount", "line_total"])
        item_price_col = _first_existing_column(cur, "order_items", ["price", "unit_price", "product_price"])
        qty_col = _first_existing_column(cur, "order_items", ["quantity", "qty"])
        if oi_order_col and oi_product_col:
            revenue_expr = "0"
            if item_total_col:
                revenue_expr = f"COALESCE(SUM(oi.`{item_total_col}`), 0)"
            elif item_price_col and qty_col:
                revenue_expr = f"COALESCE(SUM(COALESCE(oi.`{item_price_col}`,0) * COALESCE(oi.`{qty_col}`,0)), 0)"
            cur.execute(
                f"""
                SELECT COUNT(DISTINCT o.order_id) AS total_orders,
                       {revenue_expr} AS total_revenue,
                       MAX(o.order_date) AS last_order_date
                FROM orders o
                LEFT JOIN order_items oi ON oi.`{oi_order_col}` = o.order_id
                WHERE oi.`{oi_product_col}` = %s
                  AND o.order_date BETWEEN %s AND %s
                  AND o.payment_status = 'Paid'
                """,
                (product_id, start, end),
            )
            row = cur.fetchone() or {}
            return {
                "total_orders": _safe_int(row.get("total_orders")),
                "total_revenue": _num(row.get("total_revenue")),
                "last_order_date": row.get("last_order_date"),
            }

    order_product_col = _first_existing_column(cur, "orders", ["product_id", "prod_id"])
    if order_product_col:
        cur.execute(
            f"""
            SELECT COUNT(*) AS total_orders,
                   COALESCE(SUM(total_amount), 0) AS total_revenue,
                   MAX(order_date) AS last_order_date
            FROM orders
            WHERE `{order_product_col}` = %s
              AND order_date BETWEEN %s AND %s
              AND payment_status = 'Paid'
            """,
            (product_id, start, end),
        )
        row = cur.fetchone() or {}
        return {
            "total_orders": _safe_int(row.get("total_orders")),
            "total_revenue": _num(row.get("total_revenue")),
            "last_order_date": row.get("last_order_date"),
        }

    return {"total_orders": 0, "total_revenue": 0, "last_order_date": None}


@reports_bp.route("/api/admin/reports/summary", methods=["GET"])
@jwt_required()
def reports_summary():
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    rng, start, end = _resolve_report_dates()

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)

    cur.execute("SELECT COUNT(*) AS total_users FROM user")
    total_users = _safe_int(cur.fetchone()["total_users"])

    cur.execute("SELECT COUNT(*) AS total_sellers FROM seller")
    total_sellers = _safe_int(cur.fetchone()["total_sellers"])

    cur.execute("SELECT COUNT(*) AS total_products FROM product")
    total_products = _safe_int(cur.fetchone()["total_products"])

    total_delivery_staff = 0
    if _table_exists(cur, "delivery_staff"):
        cur.execute("SELECT COUNT(*) AS total_delivery_staff FROM delivery_staff")
        total_delivery_staff = _safe_int((cur.fetchone() or {}).get("total_delivery_staff"))

    cur.execute(
        """
        SELECT COUNT(*) AS total_orders,
               COALESCE(SUM(CASE WHEN payment_status = 'Paid' THEN total_amount ELSE 0 END), 0) AS revenue
        FROM orders
        WHERE order_date BETWEEN %s AND %s
        """,
        (start, end),
    )
    row = cur.fetchone() or {}
    total_orders = _safe_int(row.get("total_orders"))
    revenue = _num(row.get("revenue"))

    cur.execute(
        """
        SELECT order_status, COUNT(*) AS cnt
        FROM orders
        WHERE order_date BETWEEN %s AND %s
        GROUP BY order_status
        """,
        (start, end),
    )
    order_status_counts = _status_count_map(cur.fetchall(), "order_status")

    cur.execute(
        """
        SELECT payment_status, COUNT(*) AS cnt
        FROM orders
        WHERE order_date BETWEEN %s AND %s
        GROUP BY payment_status
        """,
        (start, end),
    )
    payment_status_counts = _status_count_map(cur.fetchall(), "payment_status")

    cur.execute(
        """
        SELECT DATE(order_date) AS day,
               COALESCE(SUM(CASE WHEN payment_status = 'Paid' THEN total_amount ELSE 0 END), 0) AS total
        FROM orders
        WHERE order_date BETWEEN %s AND %s
        GROUP BY DATE(order_date)
        ORDER BY day
        """,
        (start, end),
    )
    revenue_by_day = [{"day": str(r["day"]), "total": _num(r.get("total"))} for r in cur.fetchall()]

    cur.close()
    conn.close()

    return jsonify({
        "range": rng,
        "start": start.isoformat(),
        "end": end.isoformat(),
        "cards": {
            "total_users": total_users,
            "total_sellers": total_sellers,
            "total_products": total_products,
            "total_delivery_staff": total_delivery_staff,
            "total_orders": total_orders,
            "revenue": revenue,
        },
        "order_status_counts": order_status_counts,
        "payment_status_counts": payment_status_counts,
        "revenue_by_day": revenue_by_day,
    }), 200


@reports_bp.route("/api/admin/reports/users", methods=["GET"])
@jwt_required()
def reports_users():
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403
    rng, start, end = _resolve_report_dates()
    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)
    cur.execute(
        """
        SELECT u.user_id, u.user_name, u.user_email, u.user_mobile,
               COUNT(o.order_id) AS total_orders,
               COALESCE(SUM(CASE WHEN o.payment_status = 'Paid' THEN o.total_amount ELSE 0 END), 0) AS total_spent,
               MAX(o.order_date) AS last_order_date,
               (
                   SELECT oo.payment_method
                   FROM orders oo
                   WHERE oo.user_id = u.user_id
                     AND oo.order_date BETWEEN %s AND %s
                     AND oo.payment_method IS NOT NULL
                     AND oo.payment_method <> ''
                   GROUP BY oo.payment_method
                   ORDER BY COUNT(*) DESC, oo.payment_method ASC
                   LIMIT 1
               ) AS preferred_payment_method
        FROM user u
        LEFT JOIN orders o ON o.user_id = u.user_id AND o.order_date BETWEEN %s AND %s
        GROUP BY u.user_id, u.user_name, u.user_email, u.user_mobile
        ORDER BY total_orders DESC, total_spent DESC, u.user_name ASC
        """,
        (start, end, start, end),
    )
    rows = cur.fetchall()
    users = [{
        "user_id": r["user_id"],
        "user_name": r.get("user_name"),
        "user_email": r.get("user_email"),
        "user_mobile": r.get("user_mobile"),
        "total_orders": _safe_int(r.get("total_orders")),
        "total_spent": _num(r.get("total_spent")),
        "last_order_date": _to_iso(r.get("last_order_date")),
        "preferred_payment_method": r.get("preferred_payment_method") or "N/A",
    } for r in rows]
    cur.close(); conn.close()
    return jsonify({"users": users}), 200


@reports_bp.route("/api/admin/reports/sellers", methods=["GET"])
@jwt_required()
def reports_sellers():
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403
    rng, start, end = _resolve_report_dates()
    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)
    cur.execute(
        """
        SELECT s.seller_id, s.seller_name, s.seller_email, s.seller_mobile,
               COUNT(o.order_id) AS total_orders,
               COALESCE(SUM(CASE WHEN o.payment_status = 'Paid' THEN o.total_amount ELSE 0 END), 0) AS total_revenue,
               MAX(o.order_date) AS last_order_date,
               (
                   SELECT oo.payment_method
                   FROM orders oo
                   WHERE oo.seller_id = s.seller_id
                     AND oo.order_date BETWEEN %s AND %s
                     AND oo.payment_method IS NOT NULL
                     AND oo.payment_method <> ''
                   GROUP BY oo.payment_method
                   ORDER BY COUNT(*) DESC, oo.payment_method ASC
                   LIMIT 1
               ) AS preferred_payment_method
        FROM seller s
        LEFT JOIN orders o ON o.seller_id = s.seller_id AND o.order_date BETWEEN %s AND %s
        GROUP BY s.seller_id, s.seller_name, s.seller_email, s.seller_mobile
        ORDER BY total_orders DESC, total_revenue DESC, s.seller_name ASC
        """,
        (start, end, start, end),
    )
    rows = cur.fetchall()
    sellers = [{
        "seller_id": r["seller_id"],
        "seller_name": r.get("seller_name"),
        "seller_email": r.get("seller_email"),
        "seller_mobile": r.get("seller_mobile"),
        "total_products": _seller_product_count(cur, r.get("seller_id")),
        "total_orders": _safe_int(r.get("total_orders")),
        "total_revenue": _num(r.get("total_revenue")),
        "last_order_date": _to_iso(r.get("last_order_date")),
        "preferred_payment_method": r.get("preferred_payment_method") or "N/A",
    } for r in rows]
    cur.close(); conn.close()
    return jsonify({"sellers": sellers}), 200


@reports_bp.route("/api/admin/reports/products", methods=["GET"])
@jwt_required()
def reports_products():
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)

    id_col = _product_id_column(cur)
    if not id_col:
        cur.close(); conn.close()
        return jsonify({"products": [], "total_products": 0, "total_value": 0}), 200

    name_col = _first_existing_column(cur, "product", ["prod_name", "product_name", "name", "title", "product_title"])
    price_col = _first_existing_column(cur, "product", ["prod_price", "price"])
    status_col = _first_existing_column(cur, "product", ["prod_status", "status"])
    stock_col = _first_existing_column(cur, "product", ["stock_quantity", "stock_qty", "stock", "quantity"])
    ps_product_col, ps_seller_col = _product_seller_columns(cur)

    select_parts = [f"p.`{id_col}` AS product_id"]
    select_parts.append(f"p.`{name_col}` AS product_name" if name_col else "'' AS product_name")
    select_parts.append(f"p.`{price_col}` AS product_price" if price_col else "0 AS product_price")
    select_parts.append(f"p.`{status_col}` AS product_status" if status_col else "'' AS product_status")
    select_parts.append(f"p.`{stock_col}` AS stock_value" if stock_col else "0 AS stock_value")
    select_parts.append("ps_map.seller_id AS seller_id")

    if ps_product_col and ps_seller_col:
        cur.execute(
            f"""
            SELECT {', '.join(select_parts)}
            FROM product p
            LEFT JOIN (
                SELECT `{ps_product_col}` AS product_id, MIN(`{ps_seller_col}`) AS seller_id
                FROM product_seller
                GROUP BY `{ps_product_col}`
            ) ps_map ON ps_map.product_id = p.`{id_col}`
            ORDER BY p.`{id_col}` DESC
            """
        )
    else:
        cur.execute(f"SELECT {', '.join(select_parts)} FROM product p ORDER BY p.`{id_col}` DESC")
    rows = cur.fetchall()
    rating_map = _get_product_rating_summary(cur)

    products = []
    total_value = 0
    total_rating = 0
    rated_products = 0
    total_reviews = 0
    for r in rows:
        price = _num(r.get("product_price"))
        total_value += price
        stock_value = _safe_int(r.get("stock_value")) if r.get("stock_value") is not None else 0
        product_id = r.get("product_id")
        rating_summary = rating_map.get(int(product_id), {"avg_rating": 0.0, "review_count": 0}) if product_id is not None else {"avg_rating": 0.0, "review_count": 0}
        avg_rating = _num(rating_summary.get("avg_rating"))
        review_count = _safe_int(rating_summary.get("review_count"))
        if review_count > 0:
            total_rating += avg_rating
            rated_products += 1
            total_reviews += review_count
        products.append({
            "product_id": product_id,
            "product_name": r.get("product_name") or "Unnamed Product",
            "seller_id": r.get("seller_id"),
            "price": price,
            "status": r.get("product_status") or "",
            "stock": stock_value,
            "stock_quantity": stock_value,
            "stock_status": "Available" if stock_value > 0 else "Out of Stock",
            "avg_rating": avg_rating,
            "review_count": review_count,
        })

    cur.close(); conn.close()
    return jsonify({
        "products": products,
        "total_products": len(products),
        "total_value": total_value,
        "avg_rating": round(total_rating / rated_products, 1) if rated_products > 0 else 0,
        "rated_products": rated_products,
        "total_reviews": total_reviews,
    }), 200


@reports_bp.route("/api/admin/reports/orders", methods=["GET"])
@jwt_required()
def reports_orders():
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    rng, start, end = _resolve_report_dates()
    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)

    payment_status_filter = (request.args.get("payment_status") or "").strip()
    order_status_filter = (request.args.get("order_status") or "").strip()

    query = """
        SELECT order_id, user_id, seller_id, total_amount, order_date, payment_status, order_status
        FROM orders
        WHERE order_date BETWEEN %s AND %s
    """
    params = [start, end]

    if payment_status_filter and payment_status_filter.lower() != "all":
        query += " AND payment_status = %s"
        params.append(payment_status_filter)

    if order_status_filter and order_status_filter.lower() != "all":
        query += " AND order_status = %s"
        params.append(order_status_filter)

    query += " ORDER BY order_date DESC, order_id DESC"
    cur.execute(query, tuple(params))
    rows = cur.fetchall() or []

    orders = []
    grand_total = 0.0
    for row in rows:
        order_id = row.get("order_id")
        product_names = _unique_strings(_order_product_names(cur, order_id)) if order_id is not None else []
        amount = _num(row.get("total_amount"))
        grand_total += amount
        orders.append({
            "order_id": order_id,
            "order_ids": [int(order_id)] if order_id is not None else [],
            "prod_name": ", ".join(product_names) if product_names else "No Product",
            "product_names": product_names,
            "user_id": row.get("user_id"),
            "seller_id": row.get("seller_id"),
            "payment_status": row.get("payment_status") or "",
            "order_status": row.get("order_status") or "",
            "order_statuses": [row.get("order_status")] if row.get("order_status") else [],
            "amount": amount,
            "order_date": _to_iso(row.get("order_date")),
            "order_day": row.get("order_date").date().isoformat() if row.get("order_date") else "",
            "qty": None,
            "item_price": None,
        })

    cur.close(); conn.close()
    return jsonify({
        "range": rng,
        "start": start.isoformat(),
        "end": end.isoformat(),
        "payment_status_filter": payment_status_filter or "All",
        "order_status_filter": order_status_filter or "All",
        "orders": orders,
        "grand_total": grand_total,
    }), 200


@reports_bp.route("/api/admin/reports/user/<int:user_id>", methods=["GET"])
@jwt_required()
def report_single_user(user_id):
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403
    rng, start, end = _resolve_report_dates()
    conn = get_db_connection(); cur = conn.cursor(dictionary=True)
    user = _fetch_user_profile(cur, user_id)
    if not user:
        cur.close(); conn.close(); return jsonify({"message": "User not found"}), 404
    cur.execute(
        """
        SELECT COUNT(*) AS total_orders,
               COALESCE(SUM(CASE WHEN payment_status = 'Paid' THEN total_amount ELSE 0 END), 0) AS total_spent,
               COALESCE(AVG(total_amount), 0) AS avg_order_value,
               SUM(CASE WHEN payment_status = 'Paid' THEN 1 ELSE 0 END) AS paid_orders,
               SUM(CASE WHEN payment_status = 'Pending' THEN 1 ELSE 0 END) AS pending_payments,
               SUM(CASE WHEN payment_status = 'Failed' THEN 1 ELSE 0 END) AS failed_payments,
               MAX(order_date) AS last_order_date
        FROM orders
        WHERE user_id = %s AND order_date BETWEEN %s AND %s
        """,
        (user_id, start, end),
    )
    stats = cur.fetchone() or {}
    cur.execute(
        """
        SELECT payment_method, COUNT(*) AS cnt
        FROM orders
        WHERE user_id = %s AND order_date BETWEEN %s AND %s AND payment_method IS NOT NULL AND payment_method <> ''
        GROUP BY payment_method
        ORDER BY cnt DESC, payment_method ASC
        """,
        (user_id, start, end),
    )
    pm_rows = cur.fetchall()
    payment_method_counts = {r["payment_method"]: _safe_int(r["cnt"]) for r in pm_rows}
    preferred_payment_method = pm_rows[0]["payment_method"] if pm_rows else "N/A"
    cur.execute(
        """
        SELECT order_status, COUNT(*) AS cnt
        FROM orders
        WHERE user_id = %s AND order_date BETWEEN %s AND %s
        GROUP BY order_status
        """,
        (user_id, start, end),
    )
    order_status_counts = _status_count_map(cur.fetchall(), "order_status")
    cur.execute(
        """
        SELECT payment_status, COUNT(*) AS cnt
        FROM orders
        WHERE user_id = %s AND order_date BETWEEN %s AND %s
        GROUP BY payment_status
        """,
        (user_id, start, end),
    )
    payment_status_counts = _status_count_map(cur.fetchall(), "payment_status")
    cur.execute(
        """
        SELECT order_id, order_date, total_amount, order_status, payment_status, payment_method, seller_id
        FROM orders
        WHERE user_id = %s AND order_date BETWEEN %s AND %s
        ORDER BY order_date DESC
        LIMIT 10
        """,
        (user_id, start, end),
    )
    recent_orders = [{
        "order_id": r["order_id"],
        "order_date": _to_iso(r.get("order_date")),
        "total_amount": _num(r.get("total_amount")),
        "order_status": r.get("order_status") or "",
        "payment_status": r.get("payment_status") or "",
        "payment_method": r.get("payment_method") or "",
        "seller_id": r.get("seller_id"),
    } for r in cur.fetchall()]
    cur.close(); conn.close()
    return jsonify({
        "type": "user",
        "range": rng,
        "profile": {
            "id": user["user_id"],
            "name": user.get("user_name"),
            "email": user.get("user_email"),
            "mobile": user.get("user_mobile"),
            "registration_at": _to_iso(user.get("registration_at")),
        },
        "stats": {
            "total_orders": _safe_int(stats.get("total_orders")),
            "total_spent": _num(stats.get("total_spent")),
            "avg_order_value": _num(stats.get("avg_order_value")),
            "paid_orders": _safe_int(stats.get("paid_orders")),
            "pending_payments": _safe_int(stats.get("pending_payments")),
            "failed_payments": _safe_int(stats.get("failed_payments")),
            "last_order_date": _to_iso(stats.get("last_order_date")),
            "preferred_payment_method": preferred_payment_method,
        },
        "order_status_counts": order_status_counts,
        "payment_status_counts": payment_status_counts,
        "payment_method_counts": payment_method_counts,
        "recent_orders": recent_orders,
    }), 200


@reports_bp.route("/api/admin/reports/seller/<int:seller_id>", methods=["GET"])
@jwt_required()
def report_single_seller(seller_id):
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403
    rng, start, end = _resolve_report_dates()
    conn = get_db_connection(); cur = conn.cursor(dictionary=True)
    seller = _fetch_seller_profile(cur, seller_id)
    if not seller:
        cur.close(); conn.close(); return jsonify({"message": "Seller not found"}), 404
    product_row = {"total_products": _seller_product_count(cur, seller_id)}
    cur.execute(
        """
        SELECT COUNT(*) AS total_orders,
               COALESCE(SUM(CASE WHEN payment_status = 'Paid' THEN total_amount ELSE 0 END), 0) AS total_revenue,
               COALESCE(AVG(total_amount), 0) AS avg_order_value,
               SUM(CASE WHEN payment_status = 'Paid' THEN 1 ELSE 0 END) AS paid_orders,
               SUM(CASE WHEN payment_status = 'Pending' THEN 1 ELSE 0 END) AS pending_payments,
               SUM(CASE WHEN payment_status = 'Failed' THEN 1 ELSE 0 END) AS failed_payments,
               MAX(order_date) AS last_order_date
        FROM orders
        WHERE seller_id = %s AND order_date BETWEEN %s AND %s
        """,
        (seller_id, start, end),
    )
    stats = cur.fetchone() or {}
    cur.execute(
        """
        SELECT payment_method, COUNT(*) AS cnt
        FROM orders
        WHERE seller_id = %s AND order_date BETWEEN %s AND %s AND payment_method IS NOT NULL AND payment_method <> ''
        GROUP BY payment_method
        ORDER BY cnt DESC, payment_method ASC
        """,
        (seller_id, start, end),
    )
    pm_rows = cur.fetchall()
    payment_method_counts = {r["payment_method"]: _safe_int(r["cnt"]) for r in pm_rows}
    preferred_payment_method = pm_rows[0]["payment_method"] if pm_rows else "N/A"
    cur.execute(
        """
        SELECT order_status, COUNT(*) AS cnt
        FROM orders
        WHERE seller_id = %s AND order_date BETWEEN %s AND %s
        GROUP BY order_status
        """,
        (seller_id, start, end),
    )
    order_status_counts = _status_count_map(cur.fetchall(), "order_status")
    cur.execute(
        """
        SELECT payment_status, COUNT(*) AS cnt
        FROM orders
        WHERE seller_id = %s AND order_date BETWEEN %s AND %s
        GROUP BY payment_status
        """,
        (seller_id, start, end),
    )
    payment_status_counts = _status_count_map(cur.fetchall(), "payment_status")
    cur.execute(
        """
        SELECT order_id, order_date, total_amount, order_status, payment_status, payment_method, user_id
        FROM orders
        WHERE seller_id = %s AND order_date BETWEEN %s AND %s
        ORDER BY order_date DESC
        LIMIT 10
        """,
        (seller_id, start, end),
    )
    recent_orders = [{
        "order_id": r["order_id"],
        "order_date": _to_iso(r.get("order_date")),
        "total_amount": _num(r.get("total_amount")),
        "order_status": r.get("order_status") or "",
        "payment_status": r.get("payment_status") or "",
        "payment_method": r.get("payment_method") or "",
        "user_id": r.get("user_id"),
    } for r in cur.fetchall()]
    cur.close(); conn.close()
    return jsonify({
        "type": "seller",
        "range": rng,
        "profile": {
            "id": seller["seller_id"],
            "name": seller.get("seller_name"),
            "email": seller.get("seller_email"),
            "mobile": seller.get("seller_mobile"),
            "registration_at": _to_iso(seller.get("registration_at")),
        },
        "stats": {
            "total_products": _safe_int(product_row.get("total_products")),
            "total_orders": _safe_int(stats.get("total_orders")),
            "total_revenue": _num(stats.get("total_revenue")),
            "avg_order_value": _num(stats.get("avg_order_value")),
            "paid_orders": _safe_int(stats.get("paid_orders")),
            "pending_payments": _safe_int(stats.get("pending_payments")),
            "failed_payments": _safe_int(stats.get("failed_payments")),
            "last_order_date": _to_iso(stats.get("last_order_date")),
            "preferred_payment_method": preferred_payment_method,
        },
        "order_status_counts": order_status_counts,
        "payment_status_counts": payment_status_counts,
        "payment_method_counts": payment_method_counts,
        "recent_orders": recent_orders,
    }), 200


@reports_bp.route("/api/admin/reports/product/<int:product_id>", methods=["GET"])
@jwt_required()
def report_single_product(product_id):
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    rng, start, end = _resolve_report_dates()

    conn = get_db_connection(); cur = conn.cursor(dictionary=True)
    row = _get_product_base_row(cur, product_id)
    if not row:
        cur.close(); conn.close(); return jsonify({"message": "Product not found"}), 404

    stats = _get_product_order_stats(cur, product_id, start, end)
    seller_id = _single_product_seller_id(cur, row.get("product_id") or row.get("prod_id"))
    cur.close(); conn.close()

    return jsonify({
        "type": "product",
        "range": rng,
        "profile": {
            "id": row.get("product_id") or row.get("prod_id"),
            "name": _product_name_value(row) or "Unnamed Product",
            "description": row.get("description"),
            "price": _num(_product_price_value(row)),
            "stock": _safe_int(_product_stock_value(row)) if _product_stock_value(row) is not None else 0,
            "quantity": row.get("quantity"),
            "unit_type": row.get("unit_type"),
            "brand": row.get("brand"),
            "category_id": row.get("category_id"),
            "seller_id": seller_id,
            "product_image": _product_image_value(row),
            "status": _product_status_value(row),
            "avg_rating": _num(row.get("avg_rating")),
            "review_count": _safe_int(row.get("review_count")),
        },
        "stats": {
            "total_orders": stats["total_orders"],
            "total_revenue": stats["total_revenue"],
            "last_order_date": _to_iso(stats["last_order_date"]),
            "avg_rating": _num(row.get("avg_rating")),
            "review_count": _safe_int(row.get("review_count")),
        },
    }), 200


@reports_bp.route("/api/admin/reports/order/<int:order_id>", methods=["GET"])
@jwt_required()
def report_single_order(order_id):
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403
    conn = get_db_connection(); cur = conn.cursor(dictionary=True)
    cur.execute(
        """
        SELECT o.order_id, o.user_id, o.seller_id, o.total_amount, o.order_status, o.payment_status,
               o.payment_method, o.order_date, u.user_name, u.user_email, u.user_mobile,
               s.seller_name, s.seller_email, s.seller_mobile
        FROM orders o
        LEFT JOIN user u ON u.user_id = o.user_id
        LEFT JOIN seller s ON s.seller_id = o.seller_id
        WHERE o.order_id = %s LIMIT 1
        """,
        (order_id,),
    )
    order = cur.fetchone()
    if not order:
        cur.close(); conn.close(); return jsonify({"message": "Order not found"}), 404
    products = _get_products_for_order(cur, order_id)
    product_names = _order_product_names(cur, order_id)
    cur.close(); conn.close()
    return jsonify({
        "type": "order",
        "profile": {
            "order_id": order["order_id"],
            "order_date": _to_iso(order.get("order_date")),
            "user_id": order.get("user_id"),
            "user_name": order.get("user_name"),
            "user_email": order.get("user_email"),
            "user_mobile": order.get("user_mobile"),
            "seller_id": order.get("seller_id"),
            "seller_name": order.get("seller_name"),
            "seller_email": order.get("seller_email"),
            "seller_mobile": order.get("seller_mobile"),
            "prod_name": ", ".join(product_names) if product_names else "No Product",
        },
        "stats": {
            "total_amount": _num(order.get("total_amount")),
            "order_status": order.get("order_status") or "",
            "payment_status": order.get("payment_status") or "",
            "payment_method": order.get("payment_method") or "",
        },
        "products": products,
    }), 200


@reports_bp.route("/api/admin/reports/order/<int:order_id>/products", methods=["GET"])
@jwt_required()
def report_order_products(order_id):
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    order_ids_raw = (request.args.get("order_ids") or "").strip()
    order_ids = []
    if order_ids_raw:
        for part in order_ids_raw.split(','):
            parsed = int(part.strip()) if part.strip().isdigit() else None
            if parsed is not None and parsed not in order_ids:
                order_ids.append(parsed)
    if not order_ids:
        order_ids = [order_id]

    conn = get_db_connection(); cur = conn.cursor(dictionary=True)
    placeholders = ','.join(['%s'] * len(order_ids))
    cur.execute(f"SELECT order_id, total_amount FROM orders WHERE order_id IN ({placeholders}) ORDER BY order_id", tuple(order_ids))
    order_rows = cur.fetchall() or []
    if not order_rows:
        cur.close(); conn.close(); return jsonify({"message": "Order not found"}), 404

    total_amount = sum(_num(row.get("total_amount")) for row in order_rows)
    products = _grouped_products_for_orders(cur, order_ids)
    cur.close(); conn.close()
    return jsonify({
        "order_id": order_id,
        "order_ids": order_ids,
        "total_amount": total_amount,
        "products": products,
    }), 200


@reports_bp.route("/api/admin/reports/delivery-staff", methods=["GET"])
@jwt_required()
def admin_reports_delivery_staff():
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)
    try:
        cur.execute(
            """
            SELECT ds.delivery_staff_id, ds.delivery_staff_name, ds.d_s_email, ds.d_s_mobile,
                   ds.vehicle_type, ds.d_s_status, ds.joining_date,
                   COUNT(o.order_id) AS total_orders,
                   SUM(CASE WHEN LOWER(COALESCE(o.delivery_status, ''))='delivered' THEN 1 ELSE 0 END) AS delivered_orders
            FROM delivery_staff ds
            LEFT JOIN orders o ON o.delivery_staff_id = ds.delivery_staff_id
            GROUP BY ds.delivery_staff_id, ds.delivery_staff_name, ds.d_s_email, ds.d_s_mobile,
                     ds.vehicle_type, ds.d_s_status, ds.joining_date
            ORDER BY ds.delivery_staff_id DESC
            """
        )
        rows = cur.fetchall() or []
        for row in rows:
            row['total_orders'] = int(row.get('total_orders') or 0)
            row['delivered_orders'] = int(row.get('delivered_orders') or 0)
            row['d_s_mobile'] = '' if row.get('d_s_mobile') is None else str(row['d_s_mobile'])
        return jsonify({"delivery_staff": rows}), 200
    finally:
        cur.close()
        conn.close()


@reports_bp.route("/api/admin/reports/delivery-staff/<int:staff_id>", methods=["GET"])
@jwt_required()
def admin_reports_delivery_staff_detail(staff_id):
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)
    try:
        cur.execute(
            """
            SELECT delivery_staff_id, delivery_staff_name, d_s_email, d_s_mobile, d_s_address,
                   d_s_pincode, vehicle_type, staff_licence_no, d_s_status, joining_date
            FROM delivery_staff
            WHERE delivery_staff_id=%s
            LIMIT 1
            """,
            (staff_id,),
        )
        profile = cur.fetchone()
        if not profile:
            return jsonify({"error": "Delivery staff not found"}), 404

        cur.execute("SELECT COUNT(*) AS total_orders, SUM(CASE WHEN LOWER(COALESCE(delivery_status,''))='delivered' THEN 1 ELSE 0 END) AS delivered_orders FROM orders WHERE delivery_staff_id=%s", (staff_id,))
        stats = cur.fetchone() or {}
        cur.execute("SELECT order_id, order_date, total_amount, order_status, payment_status, delivery_status FROM orders WHERE delivery_staff_id=%s ORDER BY order_id DESC LIMIT 10", (staff_id,))
        recent_orders = cur.fetchall() or []
        return jsonify({
            "profile": profile,
            "stats": {
                "total_orders": int(stats.get('total_orders') or 0),
                "delivered_orders": int(stats.get('delivered_orders') or 0),
            },
            "recent_orders": recent_orders,
        }), 200
    finally:
        cur.close()
        conn.close()
