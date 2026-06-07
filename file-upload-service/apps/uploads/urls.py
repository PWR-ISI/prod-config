from django.urls import path
from rest_framework.routers import DefaultRouter

from .views import FileViewSet

router = DefaultRouter(trailing_slash=False)
router.register("files", FileViewSet, basename="file")

urlpatterns = router.urls
