from django.contrib import admin

from .models import FileRecord


@admin.register(FileRecord)
class FileRecordAdmin(admin.ModelAdmin):
    list_display = ("id", "user_id", "original_name", "size_bytes", "deleted", "created_at")
    list_filter = ("deleted", "created_at")
    search_fields = ("original_name", "user_id", "appointment_id")
    readonly_fields = ("id", "created_at")
