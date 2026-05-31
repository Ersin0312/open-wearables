import json
from json import JSONDecodeError
from uuid import UUID

from fastapi import APIRouter, HTTPException, Request, UploadFile, status
from pydantic import ValidationError

from app.database import DbSession
from app.integrations.celery.tasks.process_xml_upload_task import process_xml_upload
from app.schemas.providers.apple.apple_xml import (
    PresignedURLRequest,
    PresignedURLResponse,
    SNSNotification,
)
from app.schemas.providers.apple.health_auto_export import HealthAutoExportPayload
from app.schemas.responses.upload import UploadDataResponse
from app.services import ApiKeyDep
from app.services.apple.apple_xml.presigned_url_service import presigned_url_service
from app.services.apple.apple_xml.sns_service import sns_service
from app.services.apple.health_auto_export_service import health_auto_export_service

router = APIRouter()


@router.post("/users/{user_id}/import/apple/xml/s3")
def import_xml_presigned_url(
    user_id: str,
    request: PresignedURLRequest,
    _api_key: ApiKeyDep,
) -> PresignedURLResponse:
    """Generate presigned URL for XML file upload and trigger processing task."""
    return presigned_url_service.create_presigned_url(user_id, request)


@router.post("/users/{user_id}/import/apple/xml/direct")
def import_xml_file(
    user_id: str,
    file: UploadFile,
    _api_key: ApiKeyDep,
) -> dict[str, str]:
    """Import XML file into the database."""
    file_contents = file.file.read()
    filename = file.filename or "upload.xml"

    task = process_xml_upload.delay(file_contents=file_contents, filename=filename, user_id=user_id)

    return {
        "status": "processing",
        "task_id": task.id,
        "user_id": user_id,
    }


@router.post("/users/{user_id}/import/apple/health-auto-export")
def import_health_auto_export(
    user_id: UUID,
    payload: HealthAutoExportPayload,
    db: DbSession,
    _api_key: ApiKeyDep,
) -> dict[str, object]:
    """Ingest body metrics (weight, body fat) from the 'Health Auto Export'
    iPhone app's REST automation. Point that app's REST export at this URL with
    the X-Open-Wearables-API-Key header; it then pushes Renpho → Apple Health
    data here automatically on its schedule."""
    counts = health_auto_export_service.ingest(db, user_id, payload)
    return {"status": "ok", "user_id": str(user_id), "ingested": counts}


@router.post("/sns/notification", status_code=status.HTTP_202_ACCEPTED)
async def receive_sns_notification(
    request: Request,
) -> UploadDataResponse:
    """Handle all SNS messages (subscription confirmation + S3 upload notifications)."""
    body = await request.body()
    try:
        notification = SNSNotification.model_validate(json.loads(body))
    except (ValidationError, JSONDecodeError) as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))

    result = await sns_service.handle_sns_notification(notification)

    if result.status_code not in (status.HTTP_200_OK, status.HTTP_202_ACCEPTED):
        raise HTTPException(status_code=result.status_code, detail=result.response)
    return result
