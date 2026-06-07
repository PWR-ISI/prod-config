from rest_framework import serializers

from .models import FileRecord
from .s3_utils import presigned_url


class FileRecordSerializer(serializers.ModelSerializer):
    download_url = serializers.SerializerMethodField()

    class Meta:
        model = FileRecord
        fields = (
            "id",
            "original_name",
            "content_type",
            "size_bytes",
            "appointment_id",
            "created_at",
            "download_url",
        )
        read_only_fields = ("id", "created_at")

    def get_download_url(self, obj):
        if obj.s3_key and not obj.deleted:
            return presigned_url(obj.s3_key)
        return None


class FileUploadSerializer(serializers.Serializer):
    file = serializers.FileField()
    appointment_id = serializers.UUIDField(required=False, allow_null=True)


class PresignedUploadSerializer(serializers.Serializer):
    filename = serializers.CharField(max_length=255)
    content_type = serializers.CharField(default="application/octet-stream")
