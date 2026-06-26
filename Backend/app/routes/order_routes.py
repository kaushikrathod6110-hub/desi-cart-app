
from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required, get_jwt, get_jwt_identity
from db import get_db_connection
from decimal import Decimal
from datetime import datetime, date

order_bp = Blueprint("order_bp", __name__)

USER_CANCEL_WINDOW_SECONDS = 5 * 60

def _parse_order_datetime(value):
    if isinstance(value, datetime):
        return value
    try:
        return datetime.fromisoformat(str(value)) if value else None
    except Exception:
        return None

def _cancel_window_meta(order_row):
    order_dt = _parse_order_datetime(order_row.get("order_date"))
    if order_dt is None:
        return {
            "can_cancel": False,
            "cancel_window_seconds": USER_CANCEL_WINDOW_SECONDS,
            "cancel_window_remaining_seconds": 0,
            "cancel_window_expires_at": None,
        }
    now = datetime.now(order_dt.tzinfo) if order_dt.tzinfo else datetime.now()
    expires_at = order_dt.timestamp() + USER_CANCEL_WINDOW_SECONDS
    remaining = max(0, int(expires_at - now.timestamp()))
    current_status = str(order_row.get("order_status") or "").strip().lower()
    delivery_status = str(order_row.get("delivery_status") or "").strip().lower()
    can_cancel = remaining > 0 and current_status in ["pending", "confirmed", "packed"] and current_status not in ["cancelled", "delivered"] and delivery_status not in ["cancelled", "delivered", "out for delivery"]
    return {
        "can_cancel": can_cancel,
        "cancel_window_seconds": USER_CANCEL_WINDOW_SECONDS,
        "cancel_window_remaining_seconds": remaining,
        "cancel_window_expires_at": datetime.fromtimestamp(expires_at).isoformat(),
    }


def _is_admin():
    claims = get_jwt()
    return claims.get("role") == "admin"


def _current_role():
    return str(get_jwt().get("role", "")).lower()


def _current_identity_int():
    try:
        return int(get_jwt_identity())
    except Exception:
        return None


def _can_access_order_row(order_row):
    role = _current_role()
    identity = _current_identity_int()

    if role == "admin":
        return True
    if role == "user":
        return identity is not None and identity == int(order_row.get("user_id") or 0)
    if role == "seller":
        return identity is not None and identity == int(order_row.get("seller_id") or 0)
    if role == "delivery_staff":
        return identity is not None and identity == int(order_row.get("delivery_staff_id") or 0)
    return False


def _to_json_safe(val):
    if isinstance(val, Decimal):
        return float(val)
    if isinstance(val, (datetime, date)):
        return val.isoformat()
    return val


def _serialize_row(row: dict):
    if not isinstance(row, dict):
        return row

    out = {}
    for k, v in row.items():
        out[k] = _to_json_safe(v)
    return out


def _num(v):
    if v is None:
        return 0
    if isinstance(v, Decimal):
        return float(v)
    return float(v)


def _safe_int(v):
    return int(v or 0)


def _build_upload_url(path_or_name):
    if not path_or_name:
        return None

    clean = str(path_or_name).replace("\\", "/").strip()
    if not clean:
        return None

    if clean.startswith("http://") or clean.startswith("https://"):
        return clean

    base = request.host_url.rstrip("/")

    if clean.startswith("uploads/"):
        clean = clean[len("uploads/"):]

    return f"{base}/uploads/{clean}"


def _product_image_url_from_row(row):
    raw = (
        row.get("prod_image")
        or row.get("product_image")
        or row.get("image")
        or row.get("product_img")
        or ""
    )
    return _build_upload_url(raw)


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

        data = {
            "order_id": order_id,
            "delivery_staff_id": staff_id if staff_id is not None else order_row.get("delivery_staff_id"),
            "delivery_date": delivery_date if delivery_date is not None else (order_row.get("order_date") or datetime.now()),
            "delivery_address": order_row.get("delivery_address"),
            "delivery_pincode": order_row.get("pincode"),
            "delivery_status": status or order_row.get("delivery_status") or "Unassigned",
            "notes": order_row.get("notes"),
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


def _existing_columns(cur, table_name, candidates):
    found = []
    for column_name in candidates:
        if _column_exists(cur, table_name, column_name):
            found.append(column_name)
    return found


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


def _decrease_stock_for_order_item(conn, meta_cur, prod_id, seller_id, qty):
    product_id_col = _product_id_column(meta_cur)
    if not product_id_col:
        raise ValueError("Product table is not compatible")

    ps_product_col, ps_seller_col = _product_seller_columns(meta_cur)
    ps_stock_col = _first_existing_column(meta_cur, "product_seller", ["stock_qty"]) if _table_exists(meta_cur, "product_seller") else None
    product_stock_col = _first_existing_column(meta_cur, "product", ["stock", "stock_quantity"])
    product_status_col = _first_existing_column(meta_cur, "product", ["stock_status"])
    ps_status_col = _first_existing_column(meta_cur, "product_seller", ["ps_status"]) if _table_exists(meta_cur, "product_seller") else None

    qty = int(qty or 0)
    if qty <= 0:
        raise ValueError("Invalid order quantity")

    product_row = _get_product_base_row(meta_cur, prod_id)
    if not product_row:
        raise ValueError(f"Product {prod_id} not found")

    mapping_row = None
    final_seller_id = seller_id
    if ps_product_col and ps_seller_col and ps_stock_col:
        if final_seller_id is None:
            final_seller_id = _single_product_seller_id(meta_cur, prod_id)
        if final_seller_id is not None:
            select_sql = f"SELECT `{ps_stock_col}` AS stock_qty FROM product_seller WHERE `{ps_product_col}` = %s AND `{ps_seller_col}` = %s"
            if ps_status_col:
                select_sql += f" AND `{ps_status_col}` = 'Active'"
            select_sql += " LIMIT 1"
            meta_cur.execute(select_sql, (prod_id, final_seller_id))
            mapping_row = meta_cur.fetchone()

    available_stock = None
    if mapping_row and mapping_row.get("stock_qty") is not None:
        available_stock = int(float(mapping_row.get("stock_qty") or 0))
    elif product_stock_col:
        available_stock = int(float(product_row.get(product_stock_col) or 0))

    if available_stock is None:
        raise ValueError(f"Stock not available for product {prod_id}")
    if qty > available_stock:
        raise ValueError(f"Only {available_stock} item(s) available for product {prod_id}")

    remaining_stock = available_stock - qty
    new_stock_status = "Out of Stock" if remaining_stock <= 0 else "Available"

    write_cur = conn.cursor()
    try:
        if mapping_row and final_seller_id is not None:
            update_sql = f"UPDATE product_seller SET `{ps_stock_col}` = %s"
            values = [remaining_stock]
            if ps_status_col:
                update_sql += f", `{ps_status_col}` = %s"
                values.append('Inactive' if remaining_stock <= 0 else 'Active')
            update_sql += f" WHERE `{ps_product_col}` = %s AND `{ps_seller_col}` = %s"
            values.extend([prod_id, final_seller_id])
            write_cur.execute(update_sql, tuple(values))

        if product_stock_col:
            product_update_sql = f"UPDATE product SET `{product_stock_col}` = %s"
            product_values = [remaining_stock]
            if product_status_col:
                product_update_sql += f", `{product_status_col}` = %s"
                product_values.append(new_stock_status)
            product_update_sql += f" WHERE `{product_id_col}` = %s"
            product_values.append(prod_id)
            write_cur.execute(product_update_sql, tuple(product_values))
    finally:
        write_cur.close()



def _increase_stock(write_cur, prod_id, seller_id, quantity):
    quantity = int(quantity or 0)
    if quantity <= 0:
        return

    # Restore seller-level stock if seller_id is available
    if seller_id and _table_exists(write_cur, "product_seller"):
        try:
            write_cur.execute(
                """
                UPDATE product_seller
                SET stock_qty = stock_qty + %s,
                    ps_status = 'Active'
                WHERE prod_id = %s AND seller_id = %s
                """,
                (quantity, prod_id, seller_id),
            )
        except Exception:
            write_cur.execute(
                """
                UPDATE product_seller
                SET stock_qty = stock_qty + %s
                WHERE prod_id = %s AND seller_id = %s
                """,
                (quantity, prod_id, seller_id),
            )

    # Restore product-level stock
    try:
        write_cur.execute(
            """
            UPDATE product
            SET stock_quantity = stock_quantity + %s,
                stock_status = 'Available'
            WHERE prod_id = %s
            """,
            (quantity, prod_id),
        )
    except Exception:
        write_cur.execute(
            """
            UPDATE product
            SET stock_quantity = stock_quantity + %s
            WHERE prod_id = %s
            """,
            (quantity, prod_id),
        )

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


def _product_stock_value(row):
    if row.get("stock") is not None:
        return row.get("stock")
    return row.get("stock_quantity")



def _get_product_base_row(cur, product_id):
    id_col = _product_id_column(cur)
    if not id_col:
        return None

    product_columns = _existing_columns(
        cur,
        "product",
        [
            "product_id", "prod_id", "prod_name", "product_name", "name", "description",
            "prod_price", "price", "stock", "stock_quantity", "unit_type", "brand",
            "category_id", "seller_id", "prod_image", "product_image", "prod_status", "status",
        ],
    )
    if not product_columns:
        return None

    select_parts = [f"`{col}` AS `{col}`" for col in product_columns]
    cur.execute(
        f"SELECT {', '.join(select_parts)} FROM product WHERE `{id_col}` = %s LIMIT 1",
        (product_id,),
    )
    return cur.fetchone()


def _order_product_name_column(cur):
    return _first_existing_column(cur, "orders", ["product_name", "prod_name", "name", "title", "product_title"])


def _order_product_id_column(cur):
    return _first_existing_column(cur, "orders", ["product_id", "prod_id"])


def _seller_product_rows(cur, seller_id):
    rows_by_id = {}
    if seller_id is None or not _table_exists(cur, "product"):
        return []

    product_id_col = _product_id_column(cur)
    product_name_col = _first_existing_column(cur, "product", ["prod_name", "product_name", "name", "title", "product_title"])
    price_col = _first_existing_column(cur, "product", ["prod_price", "price"])
    stock_col = _first_existing_column(cur, "product", ["stock", "stock_quantity"])
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


def _infer_products_from_order(cur, order_id):
    if not _table_exists(cur, "orders"):
        return []

    order_product_col = _order_product_id_column(cur)
    order_name_col = _order_product_name_column(cur)
    seller_col = _first_existing_column(cur, "orders", ["seller_id"])

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
                "stock_quantity": base.get("stock_quantity"),
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
            "stock_quantity": None,
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

    seller_products = _seller_product_rows(cur, order_row.get("seller_id"))
    if len(seller_products) == 1:
        row = seller_products[0]
        price_val = row.get("product_price") if row.get("product_price") is not None else order_row.get("total_amount")
        stock_val = row.get("stock_value")
        products.append({
            "product_id": row.get("product_id"),
            "product_name": (row.get("product_name") or "").strip(),
            "description": None,
            "price": _num(price_val) if price_val is not None else 0,
            "stock": _safe_int(stock_val) if stock_val is not None else 0,
            "stock_quantity": None,
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


def _order_item_name_column(cur):
    return _first_existing_column(
        cur,
        "order_items",
        ["product_name", "prod_name", "name", "item_name", "title", "product_title"],
    )


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
                           {f'oi.`{oi_name_col}` AS order_item_name' if oi_name_col else 'NULL AS order_item_name'}
                    FROM order_items oi
                    LEFT JOIN product p ON p.`{product_id_col}` = oi.`{oi_product_col}`
                    WHERE oi.`{oi_order_col}` = %s
                    ORDER BY oi.`{oi_product_col}`
                """
                cur.execute(select_sql, (order_id,))
            else:
                select_sql = f"""
                    SELECT {f'oi.`{oi_name_col}` AS order_item_name' if oi_name_col else 'NULL AS order_item_name'}
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


def _get_products_for_order(cur, order_id):
    products = []
    has_orders = _table_exists(cur, "orders")
    has_product = _table_exists(cur, "product")
    has_order_items = _table_exists(cur, "order_items")

    if has_order_items and has_product:
        oi_order_col = _first_existing_column(cur, "order_items", ["order_id"])
        oi_product_col = _first_existing_column(cur, "order_items", ["product_id", "prod_id"])
        qty_col = _first_existing_column(cur, "order_items", ["stock_quantity", "qty"])
        item_price_col = _first_existing_column(cur, "order_items", ["price", "unit_price", "product_price"])
        item_total_col = _first_existing_column(cur, "order_items", ["subtotal", "amount", "total_amount", "line_total"])
        oi_name_col = _order_item_name_column(cur)

        product_columns = _existing_columns(
            cur,
            "product",
            [
                "product_id", "prod_id", "prod_name", "product_name", "name", "description",
                "prod_price", "price", "stock", "stock_quantity", "unit_type", "brand",
                "category_id", "seller_id", "prod_image", "product_image", "prod_status", "status",
            ],
        )

        if oi_order_col and oi_product_col:
            product_id_col = _product_id_column(cur)
            select_parts = []
            if product_columns and product_id_col:
                select_parts.extend([f"p.`{col}` AS `{col}`" for col in product_columns])
            if oi_name_col:
                select_parts.append(f"oi.`{oi_name_col}` AS `order_item_name`")
            if qty_col:
                select_parts.append(f"oi.`{qty_col}` AS `ordered_qty`")
            if item_price_col:
                select_parts.append(f"oi.`{item_price_col}` AS `ordered_price`")
            if item_total_col:
                select_parts.append(f"oi.`{item_total_col}` AS `ordered_total`")
            if not select_parts:
                select_parts.append("oi.*")

            join_sql = f"LEFT JOIN product p ON p.`{product_id_col}` = oi.`{oi_product_col}`" if (product_columns and product_id_col) else ""
            order_sql = f"ORDER BY oi.`{oi_product_col}`"
            cur.execute(
                f"""
                SELECT {', '.join(select_parts)}
                FROM order_items oi
                {join_sql}
                WHERE oi.`{oi_order_col}` = %s
                {order_sql}
                """,
                (order_id,),
            )
            rows = cur.fetchall()

            for row in rows:
                price_val = _product_price_value(row)
                stock_val = _product_stock_value(row)
                ordered_qty = row.get("ordered_qty") if "ordered_qty" in row else row.get("stock_quantity")
                ordered_price = row.get("ordered_price")
                ordered_total = row.get("ordered_total")
                if ordered_total is None and ordered_price is not None and ordered_qty is not None:
                    ordered_total = _num(ordered_price) * _safe_int(ordered_qty)

                products.append({
                    "product_id": row.get("product_id") if row.get("product_id") is not None else row.get("prod_id"),
                    "product_name": (_product_name_value(row) or row.get("order_item_name") or "").strip(),
                    "description": row.get("description"),
                    "price": _num(price_val) if price_val is not None else 0,
                    "stock": _safe_int(stock_val) if stock_val is not None else 0,
                    "stock_quantity": row.get("stock_quantity"),
                    "unit_type": row.get("unit_type"),
                    "brand": row.get("brand"),
                    "category_id": row.get("category_id"),
                    "seller_id": row.get("seller_id"),
                    "product_image": _product_image_value(row),
                    "status": _product_status_value(row),
                    "ordered_qty": _safe_int(ordered_qty) if ordered_qty is not None else None,
                    "ordered_price": _num(ordered_price) if ordered_price is not None else None,
                    "ordered_total": _num(ordered_total) if ordered_total is not None else None,
                })
            if products:
                return products

    if has_orders and has_product:
        order_product_col = _first_existing_column(cur, "orders", ["product_id", "prod_id"])
        product_id_col = _product_id_column(cur)
        if order_product_col and product_id_col:
            product_columns = _existing_columns(
                cur,
                "product",
                [
                    "product_id", "prod_id", "prod_name", "product_name", "name", "description",
                    "prod_price", "price", "stock", "stock_quantity", "unit_type", "brand",
                    "category_id", "seller_id", "prod_image", "product_image", "prod_status", "status",
                ],
            )
            if product_columns:
                select_parts = [f"p.`{col}` AS `{col}`" for col in product_columns]
                cur.execute(
                    f"""
                    SELECT {', '.join(select_parts)}
                    FROM orders o
                    LEFT JOIN product p ON p.`{product_id_col}` = o.`{order_product_col}`
                    WHERE o.order_id = %s
                    LIMIT 1
                    """,
                    (order_id,),
                )
                row = cur.fetchone()
                if row:
                    price_val = _product_price_value(row)
                    stock_val = _product_stock_value(row)
                    products.append({
                        "product_id": row.get("product_id") if row.get("product_id") is not None else row.get("prod_id"),
                        "product_name": _product_name_value(row),
                        "description": row.get("description"),
                        "price": _num(price_val) if price_val is not None else 0,
                        "stock": _safe_int(stock_val) if stock_val is not None else 0,
                        "stock_quantity": row.get("stock_quantity"),
                        "unit_type": row.get("unit_type"),
                        "brand": row.get("brand"),
                        "category_id": row.get("category_id"),
                        "seller_id": row.get("seller_id"),
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
        order_name_col = _first_existing_column(cur, "orders", ["product_name", "prod_name", "name", "title", "product_title"])
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
                    "stock_quantity": None,
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


def _fetch_single_order(cur, order_id):
    row = None
    try:
        cur.execute(
            """
            SELECT
                o.*,
                s.seller_name,
                u.user_name,
                d.delivery_staff_name,
                d.d_s_mobile,
                d.vehicle_type
            FROM orders o
            LEFT JOIN seller s ON s.seller_id = o.seller_id
            LEFT JOIN user u ON u.user_id = o.user_id
            LEFT JOIN delivery_staff d ON d.delivery_staff_id = o.delivery_staff_id
            WHERE o.order_id = %s
            LIMIT 1
            """,
            (order_id,),
        )
        row = cur.fetchone()
    except Exception:
        try:
            cur.execute(
                """
                SELECT
                    o.*,
                    s.seller_name,
                    u.user_name
                FROM orders o
                LEFT JOIN seller s ON s.seller_id = o.seller_id
                LEFT JOIN user u ON u.user_id = o.user_id
                WHERE o.order_id = %s
                LIMIT 1
                """,
                (order_id,),
            )
            row = cur.fetchone()
        except Exception:
            cur.execute("SELECT * FROM orders WHERE order_id=%s LIMIT 1", (order_id,))
            row = cur.fetchone()

    if not row:
        return None

    row = _serialize_row(row)
    if not row.get("order_status"):
        row["order_status"] = "Pending"
    if not row.get("payment_status"):
        row["payment_status"] = "Pending"
    if "seller_name" not in row or row.get("seller_name") in [None, ""]:
        row["seller_name"] = "—"
    if "user_name" not in row or row.get("user_name") in [None, ""]:
        row["user_name"] = "—"
    if "delivery_staff_name" not in row or row.get("delivery_staff_name") in [None, ""]:
        row["delivery_staff_name"] = "—"

    names = _order_product_names(cur, order_id)
    row["product_names"] = names
    row["product_name"] = ", ".join(names) if names else "No Product"
    row["products"] = _get_products_for_order(cur, order_id)
    return row


def _normalize_user_order_filter(filter_value):
    value = str(filter_value or "all").strip().lower()
    mapping = {
        "all": "all",
        "pending": "pending",
        "confirmed": "confirmed",
        "packed": "packed",
        "outfordelivery": "out_for_delivery",
        "out_for_delivery": "out_for_delivery",
        "out for delivery": "out_for_delivery",
        "delivered": "delivered",
        "cancelled": "cancelled",
        "canceled": "cancelled",
        "paid": "paid",
        "failed": "failed",
    }
    return mapping.get(value, "all")


def _format_user_order_card(order_row):
    order_row = _serialize_row(order_row or {})
    order_id = order_row.get("order_id")
    product_names = order_row.get("product_names") or []
    primary_product = product_names[0] if product_names else "No Product"
    extra_count = max(len(product_names) - 1, 0)

    order_date_raw = order_row.get("order_date")
    date_label = ""
    time_label = ""
    if isinstance(order_date_raw, str):
        try:
            parsed_dt = datetime.fromisoformat(order_date_raw.replace("Z", "+00:00")) if "T" in order_date_raw else datetime.strptime(order_date_raw, "%Y-%m-%d %H:%M:%S")
            date_label = parsed_dt.strftime("%d %b %Y")
            time_label = parsed_dt.strftime("%I:%M %p")
        except Exception:
            date_label = str(order_date_raw)
    elif isinstance(order_date_raw, datetime):
        date_label = order_date_raw.strftime("%d %b %Y")
        time_label = order_date_raw.strftime("%I:%M %p")

    return {
        "order_id": order_id,
        "orderId": f"#ORD{order_id}" if order_id is not None else "",
        "cart_id": order_row.get("cart_id"),
        "seller_id": order_row.get("seller_id"),
        "seller_name": order_row.get("seller_name") or "",
        "delivery_staff_id": order_row.get("delivery_staff_id"),
        "delivery_staff_name": order_row.get("delivery_staff_name") or "",
        "order_date": order_row.get("order_date"),
        "date": date_label,
        "time": time_label,
        "total_amount": _num(order_row.get("total_amount")),
        "amount": _num(order_row.get("total_amount")),
        "payment_method": order_row.get("payment_method") or "",
        "payment_status": order_row.get("payment_status") or "",
        "payment": order_row.get("payment_status") or "",
        "order_status": order_row.get("order_status") or "",
        "status": order_row.get("order_status") or "",
        "delivery_status": order_row.get("delivery_status") or "",
        "delivery_address": order_row.get("delivery_address") or "",
        "pincode": "" if order_row.get("pincode") is None else str(order_row.get("pincode")),
        "notes": order_row.get("notes") or "",
        "product_name": primary_product,
        "product_names": product_names,
        "items_count": len(product_names),
        "extra_items_count": extra_count,
    }


# ------------------- STATS -------------------
@order_bp.route("/api/admin/orders/stats", methods=["GET"])
@jwt_required()
def orders_stats():
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)

    cur.execute("""
        SELECT
            COUNT(*) AS total,

            SUM(order_status='Pending') AS pending,
            SUM(order_status='Confirmed') AS confirmed,
            SUM(order_status='Packed') AS packed,
            SUM(order_status='OutForDelivery') AS out_for_delivery,

            SUM(payment_status='Paid') AS paid,
            SUM(payment_status='Pending') AS pay_pending,
            SUM(payment_status='Failed') AS failed
        FROM orders
    """)

    stats = cur.fetchone() or {}

    cur.close()
    conn.close()

    keys = [
        "total",
        "pending",
        "confirmed",
        "packed",
        "out_for_delivery",
        "paid",
        "pay_pending",
        "failed",
    ]
    for k in keys:
        stats[k] = int(stats.get(k) or 0)

    return jsonify(stats), 200


# ------------------- LIST ALL ORDERS -------------------
@order_bp.route("/api/admin/orders", methods=["GET"])
@jwt_required()
def get_all_orders():
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    filter_type = (request.args.get("filter") or "").strip().lower()

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)

    rows = []
    conditions = []
    params = []

    if filter_type == "today":
        conditions.append("DATE(o.order_date) = CURDATE()")
    elif filter_type == "today_revenue":
        conditions.append("DATE(o.order_date) = CURDATE()")
        conditions.append("LOWER(COALESCE(o.payment_status, '')) = 'paid'")

    where_sql = f" WHERE {' AND '.join(conditions)}" if conditions else ""

    try:
        cur.execute(f"""
            SELECT
                o.*,
                s.seller_name,
                u.user_name,
                d.delivery_staff_name,
                d.d_s_mobile,
                d.vehicle_type
            FROM orders o
            LEFT JOIN seller s ON s.seller_id = o.seller_id
            LEFT JOIN user u ON u.user_id = o.user_id
            LEFT JOIN delivery_staff d ON d.delivery_staff_id = o.delivery_staff_id
            {where_sql}
            ORDER BY o.order_id DESC
        """, tuple(params))
        rows = cur.fetchall()

    except Exception:
        try:
            cur.execute(f"""
                SELECT
                    o.*,
                    s.seller_name,
                    u.user_name
                FROM orders o
                LEFT JOIN seller s ON s.seller_id = o.seller_id
                LEFT JOIN user u ON u.user_id = o.user_id
                {where_sql}
                ORDER BY o.order_id DESC
            """, tuple(params))
            rows = cur.fetchall()

        except Exception:
            simple_where = ""
            if filter_type == "today":
                simple_where = " WHERE DATE(order_date) = CURDATE()"
            elif filter_type == "today_revenue":
                simple_where = " WHERE DATE(order_date) = CURDATE() AND LOWER(COALESCE(payment_status, '')) = 'paid'"
            cur.execute(f"SELECT * FROM orders{simple_where} ORDER BY order_id DESC")
            rows = cur.fetchall()

    data = []
    for r in rows:
        r = _serialize_row(r)

        if not r.get("order_status"):
            r["order_status"] = "Pending"

        if not r.get("payment_status"):
            r["payment_status"] = "Pending"

        if "seller_name" not in r or r.get("seller_name") in [None, ""]:
            r["seller_name"] = "—"

        if "user_name" not in r or r.get("user_name") in [None, ""]:
            r["user_name"] = "—"

        if "delivery_staff_name" not in r or r.get("delivery_staff_name") in [None, ""]:
            r["delivery_staff_name"] = "—"

        names = _order_product_names(cur, r.get("order_id")) if r.get("order_id") is not None else []
        r["product_names"] = names
        r["product_name"] = ", ".join(names) if names else "No Product"

        data.append(r)

    cur.close()
    conn.close()

    return jsonify(data), 200



# ------------------- USER MY ORDERS -------------------
@order_bp.route("/api/user/orders", methods=["GET"])
@jwt_required()
def get_user_orders():
    if _current_role() != "user":
        return jsonify({"message": "Access denied. User only."}), 403

    user_id = _current_identity_int()
    if user_id is None:
        return jsonify({"message": "Invalid user identity."}), 401

    filter_type = _normalize_user_order_filter(request.args.get("filter", "all"))

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)

    base_query = """
        SELECT
            o.*,
            s.seller_name,
            s.shop_name,
            s.shop_address,
            s.seller_mobile,
            s.seller_email,
            s.store_logo,
            d.delivery_staff_name
        FROM orders o
        LEFT JOIN seller s ON s.seller_id = o.seller_id
        LEFT JOIN delivery_staff d ON d.delivery_staff_id = o.delivery_staff_id
        WHERE o.user_id = %s
    """
    params = [user_id]

    if filter_type == "pending":
        base_query += " AND LOWER(COALESCE(o.order_status, '')) = 'pending'"
    elif filter_type == "confirmed":
        base_query += " AND LOWER(COALESCE(o.order_status, '')) = 'confirmed'"
    elif filter_type == "packed":
        base_query += " AND LOWER(COALESCE(o.order_status, '')) = 'packed'"
    elif filter_type == "out_for_delivery":
        base_query += """
            AND (
                LOWER(REPLACE(COALESCE(o.order_status, ''), ' ', '')) = 'outfordelivery'
                OR LOWER(REPLACE(COALESCE(o.delivery_status, ''), ' ', '')) = 'outfordelivery'
            )
        """
    elif filter_type == "delivered":
        base_query += """
            AND (
                LOWER(COALESCE(o.order_status, '')) = 'delivered'
                OR LOWER(COALESCE(o.delivery_status, '')) = 'delivered'
            )
        """
    elif filter_type == "cancelled":
        base_query += " AND LOWER(COALESCE(o.order_status, '')) = 'cancelled'"
    elif filter_type == "paid":
        base_query += " AND LOWER(COALESCE(o.payment_status, '')) = 'paid'"
    elif filter_type == "failed":
        base_query += " AND LOWER(COALESCE(o.payment_status, '')) = 'failed'"

    base_query += " ORDER BY o.order_id DESC"

    cur.execute(base_query, tuple(params))
    rows = cur.fetchall() or []

    orders = []
    for row in rows:
        serialized = _serialize_row(row)
        order_id = serialized.get("order_id")

        products = _get_products_for_order(cur, order_id) if order_id is not None else []

        for product in products:
            product["prod_image_url"] = _product_image_url_from_row(product)
            product["prod_name"] = product.get("product_name") or "Order Item"
            product["quantity"] = product.get("ordered_qty") if product.get("ordered_qty") is not None else 1
            product["price"] = product.get("ordered_price") if product.get("ordered_price") is not None else product.get("price")

        first_item = products[0] if products else {}

        serialized["products"] = products
        serialized["product_names"] = [p.get("prod_name") for p in products if p.get("prod_name")]
        serialized["product_name"] = first_item.get("prod_name") or "Order Item"
        serialized["first_item_name"] = first_item.get("prod_name") or "Order Item"
        serialized["first_item_image"] = first_item.get("prod_image_url") or ""
        serialized["item_count"] = len(products) if products else 1
        serialized["shop_name"] = serialized.get("shop_name") or serialized.get("seller_name") or ""
        serialized["store_logo_url"] = _build_upload_url(serialized.get("store_logo"))

        cancel_meta = _cancel_window_meta(serialized)
        orders.append({
            "order_id": serialized.get("order_id"),
            "orderId": f"#ORD{serialized.get('order_id')}",
            "order_date": serialized.get("order_date"),
            "total_amount": _num(serialized.get("total_amount")),
            "payment_method": serialized.get("payment_method") or "",
            "payment_status": serialized.get("payment_status") or "",
            "order_status": serialized.get("order_status") or "",
            "delivery_status": serialized.get("delivery_status") or "",
            "delivery_address": serialized.get("delivery_address") or "",
            "pincode": "" if serialized.get("pincode") is None else str(serialized.get("pincode")),
            "seller_id": serialized.get("seller_id"),
            "seller_name": serialized.get("seller_name") or "",
            "shop_name": serialized.get("shop_name") or "",
            "shop_address": serialized.get("shop_address") or "",
            "seller_mobile": "" if serialized.get("seller_mobile") is None else str(serialized.get("seller_mobile")),
            "seller_email": serialized.get("seller_email") or "",
            "store_logo_url": serialized.get("store_logo_url") or "",
            "first_item_name": serialized.get("first_item_name") or "Order Item",
            "first_item_image": serialized.get("first_item_image") or "",
            "item_count": serialized.get("item_count") or 1,
            "can_cancel": cancel_meta["can_cancel"],
            "cancel_window_seconds": cancel_meta["cancel_window_seconds"],
            "cancel_window_remaining_seconds": cancel_meta["cancel_window_remaining_seconds"],
            "cancel_window_expires_at": cancel_meta["cancel_window_expires_at"],
        })

    cur.close()
    conn.close()

    return jsonify({
        "success": True,
        "filter": filter_type,
        "count": len(orders),
        "orders": orders,
        "message": "Orders fetched successfully" if orders else "No orders found for this filter",
    }), 200


# ------------------- USER ORDER DETAILS -------------------
@order_bp.route("/api/user/orders/<int:order_id>", methods=["GET"])
@jwt_required()
def get_user_order_details(order_id):
    if _current_role() != "user":
        return jsonify({"message": "Access denied. User only."}), 403

    user_id = _current_identity_int()
    if user_id is None:
        return jsonify({"message": "Invalid user identity."}), 401

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)

    row = _fetch_single_order(cur, order_id)
    if not row:
        cur.close()
        conn.close()
        return jsonify({"success": False, "message": "Order not found"}), 404

    if int(row.get("user_id") or 0) != user_id:
        cur.close()
        conn.close()
        return jsonify({"success": False, "message": "Access denied."}), 403

    products = row.get("products") or _get_products_for_order(cur, order_id)

    items = []
    for product in products:
        items.append({
            "prod_id": product.get("product_id"),
            "prod_name": product.get("product_name") or "Order Item",
            "quantity": product.get("ordered_qty") if product.get("ordered_qty") is not None else 1,
            "price": product.get("ordered_price") if product.get("ordered_price") is not None else product.get("price") or 0,
            "total": product.get("ordered_total") if product.get("ordered_total") is not None else product.get("price") or 0,
            "description": product.get("description") or "",
            "brand": product.get("brand") or "",
            "unit_type": product.get("unit_type") or "",
            "prod_image_url": _product_image_url_from_row(product) or "",
        })

    cancel_meta = _cancel_window_meta(row)
    detail = {
        "order_id": row.get("order_id"),
        "order_date": row.get("order_date"),
        "total_amount": _num(row.get("total_amount")),
        "payment_method": row.get("payment_method") or "",
        "payment_status": row.get("payment_status") or "",
        "order_status": row.get("order_status") or "",
        "delivery_status": row.get("delivery_status") or "",
        "delivery_address": row.get("delivery_address") or "",
        "pincode": "" if row.get("pincode") is None else str(row.get("pincode")),
        "notes": row.get("notes") or "",
        "seller_id": row.get("seller_id"),
        "seller_name": row.get("seller_name") or "",
        "shop_name": row.get("shop_name") or row.get("seller_name") or "",
        "shop_address": row.get("shop_address") or "",
        "seller_mobile": "" if row.get("seller_mobile") is None else str(row.get("seller_mobile")),
        "seller_email": row.get("seller_email") or "",
        "store_logo_url": _build_upload_url(row.get("store_logo")) or "",
        "seller_email": row.get("seller_email") or "",
        "delivery_staff_id": row.get("delivery_staff_id"),
        "delivery_staff_name": row.get("delivery_staff_name") or "",
        "delivery_staff_mobile": "" if row.get("d_s_mobile") is None else str(row.get("d_s_mobile")),
        "vehicle_type": row.get("vehicle_type") or "",
        "items": items,
        "can_cancel": cancel_meta["can_cancel"],
        "cancel_window_seconds": cancel_meta["cancel_window_seconds"],
        "cancel_window_remaining_seconds": cancel_meta["cancel_window_remaining_seconds"],
        "cancel_window_expires_at": cancel_meta["cancel_window_expires_at"],
    }

    cur.close()
    conn.close()

    return jsonify({
        "success": True,
        "order": detail,
        "message": "Order details fetched successfully",
    }), 200


@order_bp.route("/api/user/orders/<int:order_id>/cancel", methods=["PUT"])
@jwt_required()
def cancel_user_order(order_id):
    if _current_role() != "user":
        return jsonify({"success": False, "message": "Access denied. User only."}), 403

    user_id = _current_identity_int()
    if user_id is None:
        return jsonify({"success": False, "message": "Invalid user identity."}), 401

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)

    row = _fetch_single_order(cur, order_id)
    if not row:
        cur.close()
        conn.close()
        return jsonify({"success": False, "message": "Order not found"}), 404

    if int(row.get("user_id") or 0) != user_id:
        cur.close()
        conn.close()
        return jsonify({"success": False, "message": "Access denied."}), 403

    current_status = str(row.get("order_status") or "").strip()
    cancel_meta = _cancel_window_meta(row)

    if current_status in ["Cancelled", "Delivered", "OutForDelivery"]:
        cur.close()
        conn.close()
        return jsonify({
            "success": False,
            "message": f"Order cannot be cancelled when status is {current_status}"
        }), 400

    if current_status not in ["Pending", "Confirmed", "Packed"]:
        cur.close()
        conn.close()
        return jsonify({
            "success": False,
            "message": "Only Pending, Confirmed or Packed orders can be cancelled"
        }), 400

    if not cancel_meta["can_cancel"]:
        cur.close()
        conn.close()
        return jsonify({
            "success": False,
            "message": "Order can only be cancelled within 5 minutes of placing it."
        }), 400

    try:
        write_cur = conn.cursor()

        items_cur = conn.cursor(dictionary=True)
        has_order_item_seller_id = _column_exists(items_cur, "order_items", "seller_id")

        if has_order_item_seller_id:
            items_cur.execute(
                """
                SELECT prod_id, seller_id, quantity
                FROM order_items
                WHERE order_id = %s
                """,
                (order_id,),
            )
        else:
            items_cur.execute(
                """
                SELECT prod_id, NULL AS seller_id, quantity
                FROM order_items
                WHERE order_id = %s
                """,
                (order_id,),
            )

        order_items_rows = items_cur.fetchall() or []
        items_cur.close()

        for item in order_items_rows:
            prod_id = int(item.get("prod_id") or 0)
            qty = int(float(item.get("quantity") or 0))
            seller_id = int(item.get("seller_id") or 0) if item.get("seller_id") is not None else 0

            if prod_id > 0 and qty > 0:
                _increase_stock(write_cur, prod_id, seller_id, qty)

        write_cur.execute(
            """
            UPDATE orders
            SET order_status = 'Cancelled',
                delivery_status = 'Cancelled',
                notes = %s
            WHERE order_id = %s AND user_id = %s
            """,
            ("Cancelled by user", order_id, user_id),
        )

        conn.commit()
        write_cur.close()
        cur.close()
        conn.close()

        return jsonify({
            "success": True,
            "message": "Order cancelled successfully"
        }), 200

    except Exception as e:
        conn.rollback()
        cur.close()
        conn.close()
        return jsonify({
            "success": False,
            "message": f"Cancel failed: {str(e)}"
        }), 500

@order_bp.route("/api/orders/<int:order_id>", methods=["GET"])
@jwt_required()
def get_single_order(order_id):
    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)

    row = _fetch_single_order(cur, order_id)

    cur.close()
    conn.close()

    if not row:
        return jsonify({"error": "Order not found"}), 404

    if not _can_access_order_row(row):
        return jsonify({"message": "Access denied."}), 403

    return jsonify(row), 200


@order_bp.route("/api/admin/orders/<int:order_id>", methods=["GET"])
@jwt_required()
def get_single_admin_order(order_id):
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403
    return get_single_order(order_id)


# ------------------- GET ORDER PRODUCTS -------------------
@order_bp.route("/api/orders/<int:order_id>/products", methods=["GET"])
@jwt_required()
def get_order_products(order_id):
    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)

    row = _fetch_single_order(cur, order_id)
    if not row:
        cur.close()
        conn.close()
        return jsonify({"error": "Order not found"}), 404

    if not _can_access_order_row(row):
        cur.close()
        conn.close()
        return jsonify({"message": "Access denied."}), 403

    products = row.get("products") or _get_products_for_order(cur, order_id)

    cur.close()
    conn.close()

    return jsonify({
        "order_id": order_id,
        "products": products,
        "product_names": [p.get("product_name") for p in products if p.get("product_name")],
    }), 200


@order_bp.route("/api/admin/orders/<int:order_id>/products", methods=["GET"])
@jwt_required()
def get_admin_order_products(order_id):
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403
    return get_order_products(order_id)


# ------------------- MANUAL ADD/UPDATE ORDER PRODUCTS -------------------
@order_bp.route("/api/admin/orders/<int:order_id>/products", methods=["POST"])
@jwt_required()
def add_or_replace_order_products(order_id):
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    body = request.get_json(silent=True) or {}
    items = body.get("items")

    if not isinstance(items, list) or len(items) == 0:
        return jsonify({"error": "items list is required"}), 400

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)

    cur.execute("SELECT order_id FROM orders WHERE order_id=%s LIMIT 1", (order_id,))
    order_row = cur.fetchone()
    if not order_row:
        cur.close()
        conn.close()
        return jsonify({"error": "Order not found"}), 404

    if not _table_exists(cur, "order_items"):
        cur.close()
        conn.close()
        return jsonify({"error": "order_items table not found"}), 500

    oi_order_col = _first_existing_column(cur, "order_items", ["order_id"])
    oi_product_col = _first_existing_column(cur, "order_items", ["product_id", "prod_id"])
    qty_col = _first_existing_column(cur, "order_items", ["stock_quantity", "qty"])
    price_col = _first_existing_column(cur, "order_items", ["price", "unit_price", "product_price"])
    total_col = _first_existing_column(cur, "order_items", ["subtotal", "amount", "total_amount", "line_total"])
    name_col = _order_item_name_column(cur)

    if not oi_order_col or not oi_product_col:
        cur.close()
        conn.close()
        return jsonify({"error": "order_items table columns are not compatible"}), 500

    cur = conn.cursor()
    cur.execute(f"DELETE FROM order_items WHERE `{oi_order_col}`=%s", (order_id,))

    product_id_col = _product_id_column(conn.cursor(dictionary=True)) if False else None
    # product_id_col variable kept unused intentionally out of insert path.

    for item in items:
        if not isinstance(item, dict):
            conn.rollback()
            cur.close()
            conn.close()
            return jsonify({"error": "Each item must be an object"}), 400

        prod_id = item.get("prod_id")
        stock_quantity = item.get("stock_quantity", 1)
        price = item.get("price", 0)
        product_name = item.get("product_name")

        try:
            prod_id = int(prod_id)
            stock_quantity = int(stock_quantity)
            price = float(price)
        except Exception:
            conn.rollback()
            cur.close()
            conn.close()
            return jsonify({"error": "prod_id, stock_quantity and price must be numeric"}), 400

        if stock_quantity <= 0:
            stock_quantity = 1

        insert_cols = [oi_order_col, oi_product_col]
        insert_vals = [order_id, prod_id]

        if qty_col:
            insert_cols.append(qty_col)
            insert_vals.append(stock_quantity)
        if price_col:
            insert_cols.append(price_col)
            insert_vals.append(price)
        if total_col:
            insert_cols.append(total_col)
            insert_vals.append(price * stock_quantity)
        if name_col and product_name:
            insert_cols.append(name_col)
            insert_vals.append(str(product_name).strip())

        cols_sql = ", ".join([f"`{c}`" for c in insert_cols])
        marks_sql = ", ".join(["%s"] * len(insert_cols))
        cur.execute(f"INSERT INTO order_items ({cols_sql}) VALUES ({marks_sql})", tuple(insert_vals))

    conn.commit()
    cur.close()

    read_cur = conn.cursor(dictionary=True)
    updated = _fetch_single_order(read_cur, order_id)
    read_cur.close()
    conn.close()

    return jsonify({
        "message": "Order products saved successfully",
        "order": updated,
    }), 200




# ------------------- CREATE ORDER WITH AUTO ORDER_ITEMS -------------------
@order_bp.route("/api/admin/orders/create", methods=["POST"])
@jwt_required()
def create_admin_order():
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    body = request.get_json(silent=True) or {}
    items = body.get("items")

    if not isinstance(items, list) or len(items) == 0:
        return jsonify({"error": "items list is required"}), 400

    conn = get_db_connection()
    meta_cur = conn.cursor(dictionary=True)

    if not _table_exists(meta_cur, "orders"):
        meta_cur.close()
        conn.close()
        return jsonify({"error": "orders table not found"}), 500

    if not _table_exists(meta_cur, "order_items"):
        meta_cur.close()
        conn.close()
        return jsonify({"error": "order_items table not found"}), 500

    order_columns = _existing_columns(
        meta_cur,
        "orders",
        [
            "seller_id", "cart_id", "user_id", "delivery_staff_id", "order_date", "total_amount",
            "payment_method", "payment_status", "order_status", "delivery_address", "pincode",
            "notes", "delivery_status", "assigned_at", "picked_at", "out_for_delivery_at", "delivered_at",
        ],
    )

    oi_order_col = _first_existing_column(meta_cur, "order_items", ["order_id"])
    oi_product_col = _first_existing_column(meta_cur, "order_items", ["product_id", "prod_id"])
    qty_col = _first_existing_column(meta_cur, "order_items", ["stock_quantity", "qty"])
    price_col = _first_existing_column(meta_cur, "order_items", ["price", "unit_price", "product_price"])
    total_col = _first_existing_column(meta_cur, "order_items", ["subtotal", "amount", "total_amount", "line_total"])
    name_col = _order_item_name_column(meta_cur)
    product_id_col = _product_id_column(meta_cur)

    if not oi_order_col or not oi_product_col:
        meta_cur.close()
        conn.close()
        return jsonify({"error": "order_items table columns are not compatible"}), 500

    resolved_items = []
    computed_total = 0.0
    inferred_seller_ids = set()
    item_seller_ids = []

    for idx, item in enumerate(items, start=1):
        if not isinstance(item, dict):
            meta_cur.close()
            conn.close()
            return jsonify({"error": f"Item {idx} must be an object"}), 400

        prod_id = item.get("prod_id", item.get("product_id"))
        stock_quantity = item.get("stock_quantity", item.get("qty", 1))
        price = item.get("price", item.get("unit_price", item.get("product_price", 0)))
        product_name = str(item.get("product_name") or item.get("prod_name") or item.get("name") or "").strip()

        try:
            prod_id = int(prod_id)
            stock_quantity = int(stock_quantity)
            price = float(price)
        except Exception:
            meta_cur.close()
            conn.close()
            return jsonify({"error": f"Item {idx}: prod_id, stock_quantity and price must be numeric"}), 400

        if stock_quantity <= 0:
            stock_quantity = 1

        product_row = None
        if product_id_col and _table_exists(meta_cur, "product"):
            product_row = _get_product_base_row(meta_cur, prod_id)
        item_seller_id = None
        if product_row:
            if not product_name:
                product_name = _product_name_value(product_row)
            if (price is None or price <= 0) and _product_price_value(product_row) is not None:
                price = _num(_product_price_value(product_row))
            seller_ids_for_product = _product_seller_ids(meta_cur, prod_id)
            for seller_id_from_product in seller_ids_for_product:
                inferred_seller_ids.add(int(seller_id_from_product))
            if len(seller_ids_for_product) == 1:
                item_seller_id = int(seller_ids_for_product[0])

        item_seller_ids.append(item_seller_id)
        computed_total += float(price) * int(stock_quantity)
        resolved_items.append({
            "prod_id": prod_id,
            "stock_quantity": stock_quantity,
            "price": float(price),
            "product_name": product_name,
        })

    seller_id = body.get("seller_id")
    user_id = body.get("user_id")
    cart_id = body.get("cart_id")
    delivery_staff_id = body.get("delivery_staff_id")
    if delivery_staff_id in ("", "null"):
        delivery_staff_id = None
    payment_method = str(body.get("payment_method") or "Online").strip() or "Online"
    payment_status = str(body.get("payment_status") or "Paid").strip() or "Paid"
    order_status = str(body.get("order_status") or "Pending").strip() or "Pending"
    delivery_status = str(body.get("delivery_status") or ("Assigned" if delivery_staff_id is not None else "Unassigned")).strip() or ("Assigned" if delivery_staff_id is not None else "Unassigned")
    delivery_address = body.get("delivery_address")
    pincode = body.get("pincode")
    notes = body.get("notes")
    total_amount = body.get("total_amount")

    if seller_id is None and len(inferred_seller_ids) == 1:
        seller_id = next(iter(inferred_seller_ids))

    if seller_id is None and "seller_id" in order_columns:
        meta_cur.close()
        conn.close()
        return jsonify({"error": "seller_id is required"}), 400

    if user_id is None and "user_id" in order_columns:
        meta_cur.close()
        conn.close()
        return jsonify({"error": "user_id is required"}), 400

    if total_amount is None:
        total_amount = computed_total
    else:
        try:
            total_amount = float(total_amount)
        except Exception:
            total_amount = computed_total

    order_insert_cols = []
    order_insert_vals = []

    def add_order_value(col, value):
        if col in order_columns:
            order_insert_cols.append(col)
            order_insert_vals.append(value)

    add_order_value("seller_id", seller_id)
    add_order_value("cart_id", cart_id)
    add_order_value("user_id", user_id)
    add_order_value("delivery_staff_id", delivery_staff_id)
    add_order_value("order_date", datetime.now())
    add_order_value("total_amount", total_amount)
    add_order_value("payment_method", payment_method)
    add_order_value("payment_status", payment_status)
    add_order_value("order_status", order_status)
    add_order_value("delivery_address", delivery_address)
    add_order_value("pincode", pincode)
    add_order_value("notes", notes)
    add_order_value("delivery_status", delivery_status)
    if delivery_staff_id is not None:
        add_order_value("assigned_at", datetime.now())

    cur = conn.cursor()

    try:
        cols_sql = ", ".join([f"`{c}`" for c in order_insert_cols])
        marks_sql = ", ".join(["%s"] * len(order_insert_cols))
        cur.execute(f"INSERT INTO orders ({cols_sql}) VALUES ({marks_sql})", tuple(order_insert_vals))
        order_id = cur.lastrowid
        _sync_delivery_table(
            conn,
            order_id,
            status=delivery_status,
            staff_id=delivery_staff_id,
            delivery_date=datetime.now(),
        )

        for idx, item in enumerate(resolved_items):
            per_item_seller_id = seller_id
            if per_item_seller_id is None and idx < len(item_seller_ids):
                per_item_seller_id = item_seller_ids[idx]
            _decrease_stock_for_order_item(
                conn,
                meta_cur,
                item["prod_id"],
                per_item_seller_id,
                item["stock_quantity"],
            )

        for item in resolved_items:
            insert_cols = [oi_order_col, oi_product_col]
            insert_vals = [order_id, item["prod_id"]]

            if qty_col:
                insert_cols.append(qty_col)
                insert_vals.append(item["stock_quantity"])
            if price_col:
                insert_cols.append(price_col)
                insert_vals.append(item["price"])
            if total_col:
                insert_cols.append(total_col)
                insert_vals.append(item["price"] * item["stock_quantity"])
            if name_col and item["product_name"]:
                insert_cols.append(name_col)
                insert_vals.append(item["product_name"])

            cols_sql = ", ".join([f"`{c}`" for c in insert_cols])
            marks_sql = ", ".join(["%s"] * len(insert_cols))
            cur.execute(f"INSERT INTO order_items ({cols_sql}) VALUES ({marks_sql})", tuple(insert_vals))

        conn.commit()
    except Exception as e:
        conn.rollback()
        cur.close()
        meta_cur.close()
        conn.close()
        return jsonify({"error": f"Failed to create order: {str(e)}"}), 500

    cur.close()
    meta_cur.close()

    read_cur = conn.cursor(dictionary=True)
    created = _fetch_single_order(read_cur, order_id)
    read_cur.close()
    conn.close()

    return jsonify({
        "message": "Order created successfully",
        "order": created,
    }), 201

# ------------------- UPDATE ORDER STATUS -------------------
@order_bp.route("/api/admin/orders/<int:order_id>/status", methods=["PUT"])
@jwt_required()
def update_order_status(order_id):
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    body = request.get_json(silent=True) or {}
    new_status = str(body.get("order_status", "")).strip()

    allowed = ["Pending", "Confirmed", "Packed", "OutForDelivery"]
    if new_status not in allowed:
        return jsonify({"error": f"Invalid order_status. Allowed: {allowed}"}), 400

    conn = get_db_connection()
    cur = conn.cursor()

    cur.execute(
        "UPDATE orders SET order_status=%s WHERE order_id=%s",
        (new_status, order_id),
    )
    conn.commit()

    affected = cur.rowcount

    cur.close()
    conn.close()

    if affected == 0:
        return jsonify({"error": "Order not found"}), 404

    return jsonify({
        "message": "Order status updated",
        "order_id": order_id,
        "order_status": new_status
    }), 200


# ------------------- UPDATE PAYMENT STATUS -------------------
@order_bp.route("/api/admin/orders/<int:order_id>/payment-status", methods=["PUT"])
@jwt_required()
def update_payment_status(order_id):
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    body = request.get_json(silent=True) or {}
    new_status = str(body.get("payment_status", "")).strip()

    allowed = ["Paid", "Pending", "Failed"]
    if new_status not in allowed:
        return jsonify({"error": f"Invalid payment_status. Allowed: {allowed}"}), 400

    conn = get_db_connection()
    cur = conn.cursor()

    cur.execute(
        "UPDATE orders SET payment_status=%s WHERE order_id=%s",
        (new_status, order_id),
    )
    conn.commit()

    affected = cur.rowcount

    cur.close()
    conn.close()

    if affected == 0:
        return jsonify({"error": "Order not found"}), 404

    return jsonify({
        "message": "Payment status updated",
        "order_id": order_id,
        "payment_status": new_status
    }), 200


# ------------------- ASSIGN DELIVERY STAFF -------------------
@order_bp.route("/api/admin/orders/<int:order_id>/assign-delivery", methods=["PUT"])
@jwt_required()
def assign_delivery_staff(order_id):
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    body = request.get_json(silent=True) or {}
    staff_id = body.get("delivery_staff_id", None)

    if staff_id is not None:
        try:
            staff_id = int(staff_id)
        except Exception:
            return jsonify({"error": "delivery_staff_id must be int or null"}), 400

    conn = get_db_connection()
    cur = conn.cursor()

    cur.execute(
        "UPDATE orders SET delivery_staff_id=%s WHERE order_id=%s",
        (staff_id, order_id),
    )
    conn.commit()

    affected = cur.rowcount

    cur.close()
    conn.close()

    if affected == 0:
        return jsonify({"error": "Order not found"}), 404

    return jsonify({
        "message": "Delivery staff assigned",
        "order_id": order_id,
        "delivery_staff_id": staff_id
    }), 200
