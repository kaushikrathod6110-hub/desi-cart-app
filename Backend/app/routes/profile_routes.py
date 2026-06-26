from flask import Blueprint

profile_bp = Blueprint("profile", __name__)

# Admin profile APIs are handled in admin_routes.py to avoid duplicate
# /api/admin-profile route registration.
