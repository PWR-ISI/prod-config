"""
WSGI config for file-upload-service.
"""

import os

from django.core.wsgi import get_wsgi_application

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'file_upload.settings')

application = get_wsgi_application()
