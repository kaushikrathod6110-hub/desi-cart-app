
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt
from werkzeug.utils import secure_filename
import os
import uuid
from db import get_db_connection

category_bp = Blueprint('category', __name__)

ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'webp'}
UPLOAD_FOLDER = os.path.join(os.getcwd(), "uploads")
os.makedirs(UPLOAD_FOLDER, exist_ok=True)


def _is_admin():
    return str(get_jwt().get("role", "")).lower() == "admin"


def _allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS


def _save_image(file_storage):
    if not file_storage or not getattr(file_storage, 'filename', ''):
        return None
    if not _allowed_file(file_storage.filename):
        raise ValueError('Only png, jpg, jpeg and webp files are allowed')
    original = secure_filename(file_storage.filename)
    ext = original.rsplit('.', 1)[1].lower()
    filename = f"category_{uuid.uuid4().hex[:12]}.{ext}"
    file_storage.save(os.path.join(UPLOAD_FOLDER, filename))
    return filename


@category_bp.route('/api/categories')
def get_categories():
    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)
    try:
        cur.execute("SELECT * FROM category WHERE status='active' ORDER BY category_id ASC")
        return jsonify(cur.fetchall() or [])
    finally:
        cur.close()
        conn.close()


@category_bp.route('/api/add-category', methods=['POST'])
@jwt_required()
def add_category():
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    name = (request.form.get("category_name") or '').strip()
    desc = (request.form.get("description") or '').strip()
    file = request.files.get("category_image")

    if not name:
        return jsonify({"error": "Category name is required"}), 400
    if not desc:
        return jsonify({"error": "Description is required"}), 400
    if not file:
        return jsonify({"error": "Image required"}), 400

    try:
        filename = _save_image(file)
    except ValueError as exc:
        return jsonify({"error": str(exc)}), 400

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)
    try:
        cur.execute("SELECT * FROM category WHERE LOWER(category_name)=LOWER(%s) LIMIT 1", (name,))
        existing = cur.fetchone()

        if existing:
            if str(existing.get("status") or '').lower() == 'inactive':
                cur.execute(
                    "UPDATE category SET category_name=%s, description=%s, category_image=%s, status='active' WHERE category_id=%s",
                    (name, desc, filename, existing['category_id'])
                )
                conn.commit()
                return jsonify({"msg": "Category Restored", "category_id": existing['category_id']}), 200
            return jsonify({"error": "Category already exists"}), 400

        cur.execute(
            "INSERT INTO category (category_name, description, category_image, status) VALUES (%s, %s, %s, 'active')",
            (name, desc, filename)
        )
        conn.commit()
        return jsonify({"msg": "Category Added", "category_id": cur.lastrowid}), 200
    finally:
        cur.close()
        conn.close()


@category_bp.route('/api/update-category/<int:id>', methods=['PUT'])
@jwt_required()
def update_category(id):
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    name = (request.form.get("category_name") or '').strip()
    desc = (request.form.get("description") or '').strip()
    file = request.files.get("category_image")

    if not name:
        return jsonify({"error": "Category name is required"}), 400
    if not desc:
        return jsonify({"error": "Description is required"}), 400

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)
    try:
        cur.execute("SELECT * FROM category WHERE category_id=%s LIMIT 1", (id,))
        existing = cur.fetchone()
        if not existing:
            return jsonify({"error": "Category not found"}), 404

        cur.execute(
            "SELECT * FROM category WHERE LOWER(category_name)=LOWER(%s) AND category_id!=%s LIMIT 1",
            (name, id)
        )
        duplicate = cur.fetchone()
        if duplicate and str(duplicate.get('status') or '').lower() == 'active':
            return jsonify({"error": "Category name already exists"}), 400

        filename = existing.get('category_image')
        if file and getattr(file, 'filename', ''):
            try:
                filename = _save_image(file)
            except ValueError as exc:
                return jsonify({"error": str(exc)}), 400

        cur.execute(
            "UPDATE category SET category_name=%s, description=%s, category_image=%s WHERE category_id=%s",
            (name, desc, filename, id)
        )
        conn.commit()
        return jsonify({"msg": "updated", "category_id": id}), 200
    finally:
        cur.close()
        conn.close()


@category_bp.route('/api/toggle-category/<int:id>', methods=['PUT'])
@jwt_required()
def toggle_category(id):
    if not _is_admin():
        return jsonify({"message": "Access denied. Admin only."}), 403

    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)
    try:
        cur.execute("SELECT category_id FROM category WHERE category_id=%s LIMIT 1", (id,))
        row = cur.fetchone()
        if not row:
            return jsonify({"error": "Category not found"}), 404

        cur = conn.cursor()
        cur.execute("UPDATE category SET status='inactive' WHERE category_id=%s", (id,))
        conn.commit()
        return jsonify({"msg": "inactive", "category_id": id}), 200
    finally:
        try:
            cur.close()
        except Exception:
            pass
        conn.close()
