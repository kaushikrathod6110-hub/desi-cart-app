from flask import Blueprint, jsonify, request
from db import get_db_connection
import hashlib
import hmac
import os
from datetime import datetime

payment_bp = Blueprint("payment_bp", __name__)



def _razorpay_keys():
    key_id = os.getenv("RAZORPAY_KEY_ID", "")
    secret = os.getenv("RAZORPAY_SECRET", "")
    return key_id, secret



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



def _load_order(cur, order_id):
    cur.execute(
        """
        SELECT
            order_id,
            seller_id,
            delivery_staff_id,
            payment_method,
            payment_status,
            total_amount
        FROM orders
        WHERE order_id = %s
        LIMIT 1
        """,
        (order_id,),
    )
    return cur.fetchone()


def _safe_nullable_int(value):
    try:
        if value is None or str(value).strip() == "":
            return None
        return int(value)
    except Exception:
        return None


@payment_bp.route("/create_order", methods=["POST"])
def create_order():
    data = request.get_json(silent=True) or {}
    amount = _safe_int(data.get("amount"), 0)

    if amount <= 0:
        return jsonify({"status": "error", "message": "Valid amount is required"}), 400

    key_id, secret = _razorpay_keys()
    if not key_id or not secret:
        return jsonify({
            "status": "error",
            "message": "Razorpay keys are missing. Set RAZORPAY_KEY_ID and RAZORPAY_SECRET in environment variables.",
        }), 500

    try:
        import razorpay  # type: ignore

        client = razorpay.Client(auth=(key_id, secret))
        order = client.order.create({
            "amount": amount,
            "currency": "INR",
            "payment_capture": 1,
        })

        return jsonify({
            "status": "success",
            "order": order,
            "key_id": key_id,
        }), 200

    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500


@payment_bp.route("/verify_payment", methods=["POST"])
def verify_payment():
    data = request.get_json(silent=True) or {}

    order_id = str(data.get("order_id") or "").strip()
    payment_id = str(data.get("payment_id") or "").strip()
    signature = str(data.get("signature") or "").strip()

    if not order_id or not payment_id or not signature:
        return jsonify({"status": "error", "message": "order_id, payment_id and signature are required"}), 400

    _, secret = _razorpay_keys()
    if not secret:
        return jsonify({"status": "error", "message": "Razorpay secret is missing"}), 500

    generated_signature = hmac.new(
        secret.encode("utf-8"),
        f"{order_id}|{payment_id}".encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()

    if generated_signature == signature:
        return jsonify({"status": "success"}), 200

    return jsonify({"status": "failed"}), 400


@payment_bp.route("/api/payment/record", methods=["POST"])
def record_payment():
    data = request.get_json(silent=True) or {}

    order_id = _safe_int(data.get("order_id"), 0)
    transaction_id = str(data.get("transaction_id") or data.get("payment_id") or "").strip()
    payment_method = str(data.get("payment_method") or "").strip() or "Online"
    payment_status = str(data.get("payment_status") or "").strip() or "Success"
    amount = data.get("amount")

    if order_id <= 0:
        return jsonify({"success": False, "message": "Valid order_id is required"}), 400
    if payment_method not in ["Online", "COD"]:
        return jsonify({"success": False, "message": "payment_method must be Online or COD"}), 400
    if payment_status not in ["Success", "Pending", "Failed"]:
        return jsonify({"success": False, "message": "payment_status must be Success, Pending or Failed"}), 400
    if payment_method == "Online" and not transaction_id:
        return jsonify({"success": False, "message": "transaction_id is required for online payment"}), 400
    if payment_method == "COD" and not transaction_id:
        transaction_id = f"COD-{order_id}-{datetime.now().strftime('%Y%m%d%H%M%S')}"

    conn = None
    cur = None
    try:
        conn = get_db_connection()
        cur = conn.cursor(dictionary=True)

        order_row = _load_order(cur, order_id)
        if not order_row:
            return jsonify({"success": False, "message": "Order not found"}), 404

        final_amount = _safe_float(amount, _safe_float(order_row.get("total_amount"), 0.0))
        seller_id = _safe_int(order_row.get("seller_id"), 0)
        delivery_staff_id = _safe_nullable_int(order_row.get("delivery_staff_id"))
        order_payment_status = "Paid" if payment_status == "Success" else ("Pending" if payment_status == "Pending" else "Failed")

        cur.execute(
            "SELECT payment_id FROM payment WHERE order_id = %s LIMIT 1",
            (order_id,),
        )
        existing = cur.fetchone()

        write_cur = conn.cursor()
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
                    payment_status,
                    transaction_id,
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
                    payment_status,
                    transaction_id,
                    datetime.now(),
                    final_amount,
                ),
            )

        write_cur.execute(
            "UPDATE orders SET payment_status = %s WHERE order_id = %s",
            (order_payment_status, order_id),
        )
        conn.commit()
        write_cur.close()

        return jsonify({
            "success": True,
            "message": "Payment recorded successfully",
            "order_id": order_id,
            "payment_method": payment_method,
            "payment_status": payment_status,
            "transaction_id": transaction_id,
            "amount": final_amount,
        }), 200

    except Exception as e:
        if conn:
            conn.rollback()
        return jsonify({"success": False, "message": str(e)}), 500
    finally:
        if cur:
            cur.close()
        if conn:
            conn.close()
