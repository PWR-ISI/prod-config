import logging

from django.conf import settings
from rest_framework import status
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.viewsets import ViewSet

from common.auth import IsAuthenticated
from common.events import publish

from .models import FileRecord
from .serializers import (
    FileRecordSerializer,
    FileUploadSerializer,
    PresignedUploadSerializer,
)
from .s3_utils import (
    upload_file_to_s3,
    presigned_url,
    presigned_put_url,
    save_to_dynamodb,
)

logger = logging.getLogger(__name__)


class FileViewSet(ViewSet):
    permission_classes = [IsAuthenticated]

    def list(self, request):
        """List current user's files."""
        user_id = request.user_id
        qs = FileRecord.objects.filter(user_id=user_id, deleted=False)
        return Response(FileRecordSerializer(qs, many=True).data)

    def retrieve(self, request, pk=None):
        """Get file metadata + presigned download URL."""
        try:
            file_record = FileRecord.objects.get(pk=pk, user_id=request.user_id, deleted=False)
        except FileRecord.DoesNotExist:
            return Response(
                {"detail": "Not found."}, status=status.HTTP_404_NOT_FOUND
            )
        return Response(FileRecordSerializer(file_record).data)

    def create(self, request):
        """Upload file to S3, save metadata to RDS + DynamoDB, publish SNS."""
        serializer = FileUploadSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        file_obj = serializer.validated_data["file"]
        appointment_id = serializer.validated_data.get("appointment_id")
        user_id = request.user_id

        # Validate file size (max 50MB)
        MAX_FILE_SIZE = 50 * 1024 * 1024  # 50MB
        if file_obj.size > MAX_FILE_SIZE:
            return Response(
                {"detail": "File size exceeds 50MB limit."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            s3_key = upload_file_to_s3(file_obj, user_id, appointment_id)
        except Exception as exc:
            logger.error("File upload failed: %s", exc)
            return Response(
                {"detail": "File upload failed."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        file_record = FileRecord.objects.create(
            user_id=user_id,
            appointment_id=appointment_id,
            original_name=file_obj.name,
            s3_key=s3_key,
            content_type=getattr(file_obj, "content_type", "application/octet-stream"),
            size_bytes=file_obj.size,
        )

        save_to_dynamodb(
            file_record.id,
            user_id,
            appointment_id,
            s3_key,
            file_obj.name,
        )

        publish(
            settings.FILE_UPLOAD_SNS_TOPIC_ARN,
            "file.uploaded",
            {
                "file_id": str(file_record.id),
                "user_id": str(user_id),
                "appointment_id": str(appointment_id) if appointment_id else None,
                "original_name": file_obj.name,
                "size_bytes": file_obj.size,
            },
        )

        return Response(
            FileRecordSerializer(file_record).data,
            status=status.HTTP_201_CREATED,
        )

    @action(detail=True, methods=["post"], url_path="delete")
    def delete_file(self, request, pk=None):
        """Soft delete a file."""
        try:
            file_record = FileRecord.objects.get(pk=pk, user_id=request.user_id)
        except FileRecord.DoesNotExist:
            return Response(
                {"detail": "Not found."}, status=status.HTTP_404_NOT_FOUND
            )

        file_record.deleted = True
        file_record.save()

        publish(
            settings.FILE_UPLOAD_SNS_TOPIC_ARN,
            "file.deleted",
            {
                "file_id": str(file_record.id),
                "user_id": str(request.user_id),
            },
        )

        return Response({"status": "deleted"})

    @action(detail=True, methods=["post"], url_path="share")
    def share(self, request, pk=None):
        """Generate presigned share URL."""
        try:
            file_record = FileRecord.objects.get(pk=pk, user_id=request.user_id, deleted=False)
        except FileRecord.DoesNotExist:
            return Response(
                {"detail": "Not found."}, status=status.HTTP_404_NOT_FOUND
            )

        url = presigned_url(file_record.s3_key, expiry=86400)  # 24 hours
        return Response({
            "download_url": url,
            "expires_in": 86400,
        })

    @action(detail=False, methods=["post"], url_path="presign")
    def presign_upload(self, request):
        """Return presigned PUT URL for direct browser upload."""
        serializer = PresignedUploadSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        filename = serializer.validated_data["filename"]
        content_type = serializer.validated_data.get("content_type", "application/octet-stream")

        result = presigned_put_url(filename, content_type)
        if not result:
            return Response(
                {"detail": "Failed to generate presigned URL."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        return Response(result)

    @action(detail=False, methods=["get"], url_path="appointment/(?P<appointment_id>[^/.]+)")
    def by_appointment(self, request, appointment_id=None):
        """List files for an appointment."""
        qs = FileRecord.objects.filter(appointment_id=appointment_id, deleted=False)
        return Response(FileRecordSerializer(qs, many=True).data)
