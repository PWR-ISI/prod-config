"""
Django settings for file-upload-service.

Env-driven configuration.
"""
from pathlib import Path

import environ

# Configure logging
from logging_config import configure_logging  # noqa: F401

BASE_DIR = Path(__file__).resolve().parent.parent

env = environ.Env(DEBUG=(bool, False))
env_file = BASE_DIR / ".env"
if env_file.exists():
    environ.Env.read_env(env_file)

SECRET_KEY = env("DJANGO_SECRET_KEY", default="dev-not-secret-change-me")
DEBUG = env("DEBUG", default=False)
ALLOWED_HOSTS = env.list("ALLOWED_HOSTS", default=["*"])
APPEND_SLASH = False

INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "rest_framework",
    "drf_spectacular",
    "corsheaders",
    "common",
    "apps.uploads",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "corsheaders.middleware.CorsMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "common.auth.JWTStubMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
    "common.middleware.RequestLoggingMiddleware",
    "common.middleware.MetricsMiddleware",
    "common.middleware.UserContextMiddleware",
    "common.middleware.ErrorHandlingMiddleware",
]

CORS_ALLOW_ALL_ORIGINS = True
CORS_ALLOW_CREDENTIALS = True

ROOT_URLCONF = "file_upload.urls"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

WSGI_APPLICATION = "file_upload.wsgi.application"

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": env("DJANGO_DB_NAME", default="fileupload_db"),
        "USER": env("DJANGO_DB_USER", default="fileupload_user"),
        "PASSWORD": env("DJANGO_DB_PASSWORD", default="othersecretpassword"),
        "HOST": env("DJANGO_DB_HOST", default="db"),
        "PORT": env("DJANGO_DB_PORT", default="5432"),
    }
}

if env.bool("USE_SQLITE", default=False):
    DATABASES["default"] = {
        "ENGINE": "django.db.backends.sqlite3",
        "NAME": BASE_DIR / "db.sqlite3",
    }

AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator"},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

LANGUAGE_CODE = "en-us"
TIME_ZONE = "UTC"
USE_I18N = True
USE_TZ = True

STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

REST_FRAMEWORK = {
    "DEFAULT_RENDERER_CLASSES": ["rest_framework.renderers.JSONRenderer"],
    "DEFAULT_PARSER_CLASSES": [
        "rest_framework.parsers.JSONParser",
        "rest_framework.parsers.MultiPartParser",
    ],
    "DEFAULT_PAGINATION_CLASS": "common.pagination.DefaultPagination",
    "PAGE_SIZE": 25,
    "DEFAULT_SCHEMA_CLASS": "drf_spectacular.openapi.AutoSchema",
    "EXCEPTION_HANDLER": "common.exceptions.exception_handler",
}

SPECTACULAR_SETTINGS = {
    "TITLE": "File Upload Service API",
    "DESCRIPTION": "Handles file uploads to S3 and metadata storage.",
    "VERSION": "0.1.0",
    "SERVE_INCLUDE_SCHEMA": False,
}

AWS_REGION = env("AWS_REGION", default="us-east-1")
AWS_ENDPOINT_URL = env("AWS_ENDPOINT_URL", default="") or None
AWS_S3_BUCKET = env("AWS_S3_BUCKET", default="")

DYNAMODB_FILE_TABLE = env("DYNAMODB_FILE_TABLE", default="isi-prod-file-metadata")
DYNAMODB_NOTIFICATION_TABLE = env("DYNAMODB_NOTIFICATION_TABLE", default="isi-prod-notifications")

FILE_UPLOAD_SNS_TOPIC_ARN = env("FILE_UPLOAD_SNS_TOPIC_ARN", default="")
INTERNAL_SHARED_TOKEN = env("INTERNAL_SHARED_TOKEN", default="dev-internal-token")

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "simple": {"format": "%(asctime)s %(levelname)s %(name)s %(message)s"},
    },
    "handlers": {
        "console": {"class": "logging.StreamHandler", "formatter": "simple"},
    },
    "root": {"handlers": ["console"], "level": env("LOG_LEVEL", default="INFO")},
}

# Monitoring & Observability
ENVIRONMENT = env("ENVIRONMENT", default="development")
SENTRY_DSN = env("SENTRY_DSN", default="")
DATADOG_API_KEY = env("DATADOG_API_KEY", default="")
CLOUDWATCH_LOG_GROUP = env("CLOUDWATCH_LOG_GROUP", default="/ecs/file-upload-service")
CLOUDWATCH_REGION = env("CLOUDWATCH_REGION", default=AWS_REGION)
