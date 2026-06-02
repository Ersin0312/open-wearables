"""In-app coach endpoint: proxies a chat turn to the Anthropic Claude API,
enriched with the user's logged data. The Anthropic key stays server-side."""

from uuid import UUID

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from app.database import DbSession
from app.services import ApiKeyDep
from app.services.coach_service import coach_service

router = APIRouter()


class CoachTurn(BaseModel):
    role: str
    content: str


class CoachChatRequest(BaseModel):
    message: str
    history: list[CoachTurn] = []


class CoachChatResponse(BaseModel):
    reply: str


class CoachStatusResponse(BaseModel):
    enabled: bool


@router.get("/users/{user_id}/coach/status", response_model=CoachStatusResponse)
def coach_status(user_id: UUID, _api_key: ApiKeyDep) -> CoachStatusResponse:
    """Whether the coach is configured (Anthropic key present)."""
    return CoachStatusResponse(enabled=coach_service.is_enabled())


@router.post("/users/{user_id}/coach/chat", response_model=CoachChatResponse)
async def coach_chat(
    user_id: UUID,
    payload: CoachChatRequest,
    db: DbSession,
    _api_key: ApiKeyDep,
) -> CoachChatResponse:
    """Send one chat turn to the coach. The backend gathers the user's recent
    data, builds the persona prompt, and calls Claude."""
    if not coach_service.is_enabled():
        raise HTTPException(status_code=503, detail="Coach nicht konfiguriert (ANTHROPIC_API_KEY fehlt).")
    try:
        reply = await coach_service.chat(
            db,
            user_id,
            payload.message,
            [t.model_dump() for t in payload.history],
        )
    except ValueError as e:
        raise HTTPException(status_code=502, detail=str(e))
    return CoachChatResponse(reply=reply)
