"""S3 file upload utilities."""
import logging
import time
from uuid import uuid4

from django.conf import settings

from common.aws import aws_client

logger = logging.getLogger(__name__)


def upload_file_to_s3(file_obj, user_id: str, appointment_id: str = None) -> str:
    """Upload file to S3, return s3_key. Returns empty string if no bucket configured."""
    if not settings.AWS_S3_BUCKET:
        logger.warning("AWS_S3_BUCKET not configured; skipping S3 upload")
        return ""

    key = f"files/{user_id}/{uuid4()}/{file_obj.name}"
    try:
        s3 = aws_client("s3")
        s3.upload_fileobj(
            file_obj,
            settings.AWS_S3_BUCKET,
            key,
            ExtraArgs={"ContentType": getattr(file_obj, "content_type", "application/octet-stream")},
        )
        logger.info("Uploaded file to S3: %s", key)
        return key
    except Exception as exc:
        logger.error("Failed to upload file to S3: %s", exc)
        raise


def presigned_url(s3_key: str, expiry: int = 3600) -> str:
    """Generate presigned download URL for a file."""
    if not settings.AWS_S3_BUCKET:
        return ""

    s3 = aws_client("s3")
    try:
        url = s3.generate_presigned_url(
            "get_object",
            Params={"Bucket": settings.AWS_S3_BUCKET, "Key": s3_key},
            ExpiresIn=expiry,
        )
        return url
    except Exception as exc:
        logger.error("Failed to generate presigned URL: %s", exc)
        return ""


def presigned_put_url(filename: str, content_type: str = "application/octet-stream", expiry: int = 3600) -> str:
    """Generate presigned PUT URL for direct browser upload."""
    if not settings.AWS_S3_BUCKET:
        return ""

    key = f"temp/{uuid4()}/{filename}"
    s3 = aws_client("s3")
    try:
        url = s3.generate_presigned_url(
            "put_object",
            Params={"Bucket": settings.AWS_S3_BUCKET, "Key": key, "ContentType": content_type},
            ExpiresIn=expiry,
        )
        return {"url": url, "key": key}
    except Exception as exc:
        logger.error("Failed to generate presigned PUT URL: %s", exc)
        return None


def save_to_dynamodb(file_id: str, user_id: str, appointment_id: str, s3_key: str, original_name: str):
    """Save file metadata to DynamoDB."""
    if not settings.DYNAMODB_FILE_TABLE:
        return

    try:
        dynamodb = aws_client("dynamodb")
        dynamodb.put_item(
            TableName=settings.DYNAMODB_FILE_TABLE,
            Item={
                "file_id": {"S": str(file_id)},
                "user_id": {"S": str(user_id)},
                "created_at": {"N": str(int(time.time()))},
                "appointment_id": {"S": str(appointment_id) if appointment_id else ""},
                "s3_key": {"S": s3_key},
                "original_name": {"S": original_name},
            },
        )
        logger.info("Saved file metadata to DynamoDB: %s", file_id)
    except Exception as exc:
        logger.error("Failed to save to DynamoDB: %s", exc)
        # Non-fatal; DynamoDB is optional
