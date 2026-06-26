from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required, get_jwt, get_jwt_identity
from db import get_db_connection
from datetime import datetime

user_checkout_bp = Blueprint("user_checkout_bp", __name__)

PLATFORM_FEE = 7.0
DELIVERY_STAFF_FEE = 20.0


def _is_user():
    return str(get_jwt().get("role", "")).lower() == "user"


def _identity_int():
    try:
        return int(get_jwt_identity())
    except Exception:
        return None


def _safe_int(value, default=0):
    try:
        return int(value)
    except Exception:
        return default


def _safe_float(value, default=0.0):
    try:
        return float(value)
    except Exception:
        return default


def _safe_nullable_int(value):
    try:
        if value is None or str(value).strip() == "":
            return None
        return int(value)
    except Exception:
        return None


def _upsert_payment_entry(write_cur, order_id, seller_id, delivery_staff_id, payment_method, payment_status, amount, transaction_id=None):
    payment_method = 'Online' if str(payment_method).strip().lower() == 'online' else 'COD'
    normalized_status = str(payment_status or 'Pending').strip().capitalize()
    if normalized_status not in {'Success', 'Pending', 'Failed'}:
        normalized_status = 'Pending'

    seller_id = _safe_int(seller_id, 0)
    delivery_staff_id = _safe_nullable_int(delivery_staff_id)
    final_amount = round(_safe_float(amount, 0.0), 2)
    final_transaction_id = str(transaction_id or '').strip()
    if not final_transaction_id:
        prefix = 'COD' if payment_method == 'COD' else 'ONLINE'
        final_transaction_id = f"{prefix}-{order_id}-{datetime.now().strftime('%Y%m%d%H%M%S')}"

    write_cur.execute(
        "SELECT payment_id FROM payment WHERE order_id = %s LIMIT 1",
        (order_id,),
    )
    existing = write_cur.fetchone()

    if existing:
        write_cur.execute(
            """
            UPDATE payment
            SET seller_id = %s,
                delivery_staff_id = %s,
                payment_method = %s,
                payment_status = %s,
                transaction_id = %s,
                payment_date = %s,
                amount = %s
            WHERE order_id = %s
            """,
            (
                seller_id,
                delivery_staff_id,
                payment_method,
                normalized_status,
                final_transaction_id,
                datetime.now(),
                final_amount,
                order_id,
            ),
        )
    else:
        write_cur.execute(
            """
            INSERT INTO payment (
                order_id,
                seller_id,
                delivery_staff_id,
                payment_method,
                payment_status,
                transaction_id,
                payment_date,
                amount
            )
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            """,
            (
                order_id,
                seller_id,
                delivery_staff_id,
                payment_method,
                normalized_status,
                final_transaction_id,
                datetime.now(),
                final_amount,
            ),
        )


def _column_exists(cur, table_name, column_name):
    cur.execute(f"SHOW COLUMNS FROM `{table_name}` LIKE %s", (column_name,))
    return cur.fetchone() is not None


def _available_stock(cur, prod_id, seller_id):
    if seller_id > 0:
        cur.execute(
            """
            SELECT stock_qty
            FROM product_seller
            WHERE prod_id = %s AND seller_id = %s
            LIMIT 1
            """,
            (prod_id, seller_id),
        )
        seller_row = cur.fetchone()
        if seller_row is not None:
            return _safe_int(seller_row.get("stock_qty"), 0), "product_seller"

    cur.execute(
        """
        SELECT stock_quantity
        FROM product
        WHERE prod_id = %s
        LIMIT 1
        """,
        (prod_id,),
    )
    product_row = cur.fetchone()
    if not product_row:
        return 0, "missing"
    return _safe_int(product_row.get("stock_quantity"), 0), "product"


def _decrease_stock(write_cur, prod_id, seller_id, quantity, source):
    if source == "product_seller" and seller_id > 0:
        write_cur.execute(
            """
            UPDATE product_seller
            SET stock_qty = GREATEST(stock_qty - %s, 0)
            WHERE prod_id = %s AND seller_id = %s
            """,
            (quantity, prod_id, seller_id),
        )

    write_cur.execute(
        """
        UPDATE product
        SET stock_quantity = GREATEST(stock_quantity - %s, 0)
        WHERE prod_id = %s
        """,
        (quantity, prod_id),
    )


def _increase_stock(write_cur, prod_id, seller_id, quantity):
    if seller_id > 0:
        write_cur.execute(
            """
            UPDATE product_seller
            SET stock_qty = stock_qty + %s
            WHERE prod_id = %s AND seller_id = %s
            """,
            (quantity, prod_id, seller_id),
        )

    write_cur.execute(
        """
        UPDATE product
        SET stock_quantity = stock_quantity + %s
        WHERE prod_id = %s
        """,
        (quantity, prod_id),
    )


def _insert_order_item(write_cur, order_id, prod_id, seller_id, quantity, unit_price, has_seller_id_column=False):
    if has_seller_id_column:
        write_cur.execute(
            """
            INSERT INTO order_items (order_id, prod_id, seller_id, quantity, price)
            VALUES (%s, %s, %s, %s, %s)
            """,
            (order_id, prod_id, seller_id, quantity, unit_price),
        )
    else:
        write_cur.execute(
            """
            INSERT INTO order_items (order_id, prod_id, quantity, price)
            VALUES (%s, %s, %s, %s)
            """,
            (order_id, prod_id, quantity, unit_price),
        )


def _normalize_item_signature(items):
    signature = []
    for item in items or []:
        signature.append((
            _safe_int(item.get("prod_id")),
            _safe_int(item.get("seller_id")),
            max(1, _safe_int(item.get("quantity"), 1)),
            round(_safe_float(item.get("unit_price"), 0.0), 2),
        ))
    signature.sort()
    return signature


def _fetch_order_signature(cur, order_id, fallback_seller_id=0):
    has_order_item_seller_id = _column_exists(cur, "order_items", "seller_id")
    if has_order_item_seller_id:
        cur.execute(
            """
            SELECT prod_id, COALESCE(seller_id, %s) AS seller_id, quantity, price AS unit_price
            FROM order_items
            WHERE order_id = %s
            ORDER BY order_item_id ASC
            """,
            (fallback_seller_id, order_id),
        )
    else:
        cur.execute(
            """
            SELECT prod_id, %s AS seller_id, quantity, price AS unit_price
            FROM order_items
            WHERE order_id = %s
            ORDER BY order_item_id ASC
            """,
            (fallback_seller_id, order_id),
        )
    rows = cur.fetchall() or []
    return _normalize_item_signature(rows)


def _find_reusable_pending_online_order(cur, user_id, address, pincode, prepared_items, total_amount):
    requested_signature = _normalize_item_signature(prepared_items)
    rounded_total = round(_safe_float(total_amount, 0.0), 2)

    cur.execute(
        """
        SELECT order_id, seller_id, total_amount, payment_status
        FROM orders
        WHERE user_id = %s
          AND payment_method = 'Online'
          AND order_status = 'Pending'
          AND COALESCE(delivery_status, 'Unassigned') IN ('Unassigned', 'Assigned')
          AND delivery_address = %s
          AND pincode = %s
          AND payment_status IN ('Pending', 'Failed')
        ORDER BY order_id DESC
        LIMIT 10
        """,
        (user_id, address, pincode),
    )
    candidate_orders = cur.fetchall() or []

    for order_row in candidate_orders:
        existing_total = round(_safe_float(order_row.get("total_amount"), 0.0), 2)
        if existing_total != rounded_total:
            continue
        existing_signature = _fetch_order_signature(
            cur,
            _safe_int(order_row.get("order_id")),
            _safe_int(order_row.get("seller_id")),
        )
        if existing_signature == requested_signature:
            return order_row
    return None


@user_checkout_bp.route('/place_order', methods=['POST'])
@jwt_required()
def place_order():
    if not _is_user():
        return jsonify({"status": "error", "message": "Access denied. User only."}), 403

    user_id = _identity_int()
    if user_id is None:
        return jsonify({"status": "error", "message": "Invalid user token"}), 401

    data = request.get_json(silent=True) or {}
    payment_method = str(data.get("payment_method") or "COD").strip()
    address = str(data.get("address") or "").strip()
    pincode = str(data.get("pincode") or "").strip()
    single_item = data.get("single_item")
    requested_payment_status = str(data.get("payment_status") or "").strip().lower()

    if not address or not pincode:
        return jsonify({"status": "error", "message": "Address and pincode are required"}), 400

    conn = None
    cur = None
    try:
        conn = get_db_connection()
        cur = conn.cursor(dictionary=True)
        has_order_item_seller_id = _column_exists(cur, "order_items", "seller_id")

        cart_rows = []
        is_single_item_checkout = isinstance(single_item, dict) and bool(single_item)
        if is_single_item_checkout:
            prod_id = _safe_int(single_item.get("prod_id"))
            seller_id = _safe_int(single_item.get("seller_id"))
            quantity = max(1, _safe_int(single_item.get("quantity"), 1))
            price = _safe_float(single_item.get("prod_price"), 0)
            if prod_id <= 0 or seller_id <= 0 or price <= 0:
                return jsonify({"status": "error", "message": "Invalid single item payload"}), 400

            cart_rows = [{
                "cart_id": None,
                "seller_id": seller_id,
                "prod_id": prod_id,
                "quantity": quantity,
                "price_at_time": price,
                "total_price": round(price * quantity, 2),
            }]
        else:
            cur.execute(
                """
                SELECT cart_id, seller_id, prod_id, quantity, price_at_time, total_price
                FROM cart
                WHERE user_id = %s AND cart_status = 'Active'
                ORDER BY cart_id ASC
                """,
                (user_id,),
            )
            cart_rows = cur.fetchall() or []

        if not cart_rows:
            return jsonify({"status": "error", "message": "No cart items available for checkout"}), 400

        prepared_items = []
        skipped_items = []
        total_amount = 0.0
        for row in cart_rows:
            prod_id = _safe_int(row.get("prod_id"))
            seller_id = _safe_int(row.get("seller_id"))
            cart_id = _safe_int(row.get("cart_id"))
            quantity = max(1, _safe_int(row.get("quantity"), 1))
            unit_price = _safe_float(row.get("price_at_time"), 0)
            available, stock_source = _available_stock(cur, prod_id, seller_id)

            if available < quantity:
                skipped_items.append({
                    "cart_id": cart_id,
                    "seller_id": seller_id,
                    "prod_id": prod_id,
                    "requested_quantity": quantity,
                    "available_quantity": available,
                })
                continue

            row_total = round(unit_price * quantity, 2)
            prepared_items.append({
                "cart_id": cart_id,
                "seller_id": seller_id,
                "prod_id": prod_id,
                "quantity": quantity,
                "unit_price": unit_price,
                "row_total": row_total,
                "stock_source": stock_source,
            })
            total_amount += row_total

        if not prepared_items:
            return jsonify({
                "status": "error",
                "message": "No available cart items found for checkout",
                "skipped_items": skipped_items,
            }), 400


        items_total = round(total_amount, 2)
        platform_fee = 0.0 if not prepared_items else PLATFORM_FEE
        delivery_fee = 0.0 if not prepared_items else DELIVERY_STAFF_FEE
        total_amount = round(items_total + platform_fee + delivery_fee, 2)

        normalized_payment_method = 'Online' if payment_method.lower() == 'online' else 'COD'

        if normalized_payment_method == 'Online':
            existing_order = _find_reusable_pending_online_order(
                cur,
                user_id,
                address,
                pincode,
                prepared_items,
                total_amount,
            )
            if existing_order:
                existing_order_id = _safe_int(existing_order.get("order_id"))
                _upsert_payment_entry(
                    cur,
                    existing_order_id,
                    existing_order.get("seller_id"),
                    None,
                    normalized_payment_method,
                    'Pending',
                    round(total_amount, 2),
                    transaction_id=f"ONLINE-{existing_order_id}-{datetime.now().strftime('%Y%m%d%H%M%S')}",
                )
                conn.commit()
                return jsonify({
                    "status": "success",
                    "message": "Using existing pending order",
                    "order_ids": [existing_order_id],
                    "order_amounts": {str(existing_order_id): round(total_amount, 2)},
                    "reused_existing_order": True,
                    "items_total": round(items_total, 2),
                    "platform_fee": round(platform_fee, 2),
                    "delivery_fee": round(delivery_fee, 2),
                    "grand_total": round(total_amount, 2),
                }), 200

        if is_single_item_checkout:
            single_item_row = prepared_items[0]
            cart_write_cur = conn.cursor(dictionary=True)
            cart_write_cur.execute(
                """
                INSERT INTO cart (user_id, seller_id, prod_id, quantity, price_at_time, total_price, cart_status)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                """,
                (
                    user_id,
                    single_item_row["seller_id"],
                    single_item_row["prod_id"],
                    single_item_row["quantity"],
                    single_item_row["unit_price"],
                    single_item_row["row_total"],
                    'Ordered' if str(payment_method).strip().lower() != 'online' else 'Active',
                ),
            )
            generated_cart_id = cart_write_cur.lastrowid
            cart_write_cur.close()
            prepared_items[0]["cart_id"] = generated_cart_id

        primary_cart_id = prepared_items[0]["cart_id"]
        primary_seller_id = prepared_items[0]["seller_id"]
        normalized_payment_method = 'Online' if payment_method.lower() == 'online' else 'COD'
        if normalized_payment_method == 'Online':
            payment_status = {
                'paid': 'Paid',
                'success': 'Paid',
                'failed': 'Failed',
                'pending': 'Pending',
            }.get(requested_payment_status, 'Pending')
        else:
            payment_status = 'Pending'

        should_lock_stock = normalized_payment_method == 'COD' or payment_status == 'Paid'

        write_cur = conn.cursor(dictionary=True)
        write_cur.execute(
            """
            INSERT INTO orders
            (seller_id, cart_id, user_id, order_date, total_amount, payment_method, payment_status, order_status, delivery_address, pincode)
            VALUES (%s, %s, %s, %s, %s, %s, %s, 'Pending', %s, %s)
            """,
            (
                primary_seller_id,
                primary_cart_id,
                user_id,
                datetime.now(),
                round(total_amount, 2),
                normalized_payment_method,
                payment_status,
                address,
                pincode,
            ),
        )
        new_order_id = write_cur.lastrowid

        for item in prepared_items:
            _insert_order_item(
                write_cur,
                new_order_id,
                item["prod_id"],
                item["seller_id"],
                item["quantity"],
                item["unit_price"],
                has_seller_id_column=has_order_item_seller_id,
            )
            if should_lock_stock:
                _decrease_stock(
                    write_cur,
                    item["prod_id"],
                    item["seller_id"],
                    item["quantity"],
                    item["stock_source"],
                )
                write_cur.execute(
                    "UPDATE cart SET cart_status='Ordered', updated_at=CURRENT_TIMESTAMP WHERE cart_id=%s",
                    (item["cart_id"],),
                )

        initial_payment_status = 'Pending' if normalized_payment_method == 'COD' else (
            'Success' if payment_status == 'Paid' else ('Failed' if payment_status == 'Failed' else 'Pending')
        )
        _upsert_payment_entry(
            write_cur,
            new_order_id,
            primary_seller_id,
            None,
            normalized_payment_method,
            initial_payment_status,
            round(total_amount, 2),
        )

        conn.commit()
        write_cur.close()

        response = {
            "status": "success",
            "message": "Order placed successfully",
            "order_ids": [new_order_id],
            "order_amounts": {str(new_order_id): round(total_amount, 2)},
            "items_total": round(items_total, 2),
            "platform_fee": round(platform_fee, 2),
            "delivery_fee": round(delivery_fee, 2),
            "grand_total": round(total_amount, 2),
        }
        if skipped_items:
            response["message"] = "Order placed for available items only"
            response["skipped_items"] = skipped_items
        return jsonify(response), 200

    except Exception as e:
        if conn:
            conn.rollback()
        return jsonify({"status": "error", "message": str(e)}), 500
    finally:
        if cur:
            cur.close()
        if conn:
            conn.close()


@user_checkout_bp.route('/api/user/orders/<int:order_id>/cancel', methods=['PUT'])
@jwt_required()
def cancel_order(order_id):
    if not _is_user():
        return jsonify({"success": False, "message": "Access denied. User only."}), 403

    user_id = _identity_int()
    if user_id is None:
        return jsonify({"success": False, "message": "Invalid user token"}), 401

    conn = None
    cur = None
    try:
        conn = get_db_connection()
        cur = conn.cursor(dictionary=True)

        cur.execute(
            """
            SELECT order_id, user_id, seller_id, delivery_staff_id, total_amount, order_status, payment_method, payment_status, notes
            FROM orders
            WHERE order_id = %s AND user_id = %s
            LIMIT 1
            """,
            (order_id, user_id),
        )
        order = cur.fetchone()
        if not order:
            return jsonify({"success": False, "message": "Order not found"}), 404

        if str(order.get("order_status") or "").lower() in ["cancelled", "delivered"]:
            return jsonify({"success": False, "message": "This order cannot be cancelled"}), 400

        has_order_item_seller_id = _column_exists(cur, "order_items", "seller_id")
        if has_order_item_seller_id:
            cur.execute(
                """
                SELECT oi.prod_id, oi.quantity, COALESCE(oi.seller_id, o.seller_id) AS seller_id
                FROM order_items oi
                INNER JOIN orders o ON o.order_id = oi.order_id
                WHERE oi.order_id = %s
                """,
                (order_id,),
            )
        else:
            cur.execute(
                """
                SELECT oi.prod_id, oi.quantity, o.seller_id
                FROM order_items oi
                INNER JOIN orders o ON o.order_id = oi.order_id
                WHERE oi.order_id = %s
                """,
                (order_id,),
            )
        items = cur.fetchall() or []

        write_cur = conn.cursor()
        refund_note = "Refund initiated to original payment method" if str(order.get("payment_method") or "").lower() == "online" and str(order.get("payment_status") or "").lower() == "paid" else ""
        notes = str(order.get("notes") or "").strip()
        if refund_note and refund_note.lower() not in notes.lower():
            notes = f"{notes} | {refund_note}".strip(" |")

        write_cur.execute(
            """
            UPDATE orders
            SET order_status = 'Cancelled',
                delivery_status = 'Cancelled',
                notes = %s
            WHERE order_id = %s AND user_id = %s
            """,
            (notes, order_id, user_id),
        )

        cancel_payment_status = 'Failed' if str(order.get('payment_method') or '').lower() == 'online' else 'Pending'
        _upsert_payment_entry(
            write_cur,
            order_id,
            order.get('seller_id'),
            order.get('delivery_staff_id'),
            order.get('payment_method') or 'COD',
            cancel_payment_status,
            order.get('total_amount') or 0,
            transaction_id=f"CANCELLED-{order_id}-{datetime.now().strftime('%Y%m%d%H%M%S')}",
        )

        for item in items:
            prod_id = _safe_int(item.get("prod_id"))
            seller_id = _safe_int(item.get("seller_id"))
            quantity = max(1, _safe_int(item.get("quantity"), 1))
            _increase_stock(write_cur, prod_id, seller_id, quantity)

        conn.commit()
        write_cur.close()

        message = "Order cancelled successfully"
        if refund_note:
            message = "Order cancelled successfully. Refund will be processed to original payment method."

        return jsonify({"success": True, "message": message}), 200

    except Exception as e:
        if conn:
            conn.rollback()
        return jsonify({"success": False, "message": str(e)}), 500
    finally:
        if cur:
            cur.close()
        if conn:
            conn.close()
