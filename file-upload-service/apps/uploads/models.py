import uuid

from django.db import models


class FileRecord(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user_id = models.UUIDField(db_index=True)
    appointment_id = models.UUIDField(null=True, blank=True, db_index=True)
    original_name = models.CharField(max_length=255)
    s3_key = models.CharField(max_length=512)
    content_type = models.CharField(max_length=100, default="application/octet-stream")
    size_bytes = models.PositiveIntegerField(default=0)
    deleted = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["user_id", "-created_at"]),
            models.Index(fields=["appointment_id", "-created_at"]),
        ]

    def __str__(self) -> str:
        return f"FileRecord {self.id} {self.original_name}"
