"""
TURN Credentials API for WebRTC-Lite

This FastAPI application provides time-limited TURN credentials
for WebRTC clients using HMAC-SHA1 authentication.

Requirements: REQ-U003, REQ-E007, REQ-N001

Author: WebRTC-Lite
Version: 1.0.0
"""

from fastapi import FastAPI, HTTPException, status, Depends
from fastapi.security import APIKeyHeader
from pydantic import BaseModel, Field, validator
from datetime import datetime, timedelta
from typing import List, Optional
import hmac
import hashlib
import base64
import os
import secrets
import logging
from contextlib import asynccontextmanager

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

###############################################################################
# CONFIGURATION
###############################################################################

# Load environment variables
TURN_SECRET = os.environ.get('TURN_SECRET', '')
TURN_SERVER = os.environ.get('TURN_SERVER', 'turn.example.com:5349')
TURN_PORT = int(os.environ.get('TURN_PORT', 5349))
API_KEY = os.environ.get('API_KEY', '')
DEFAULT_TTL = int(os.environ.get('DEFAULT_TTL', 86400))
MAX_TTL = int(os.environ.get('MAX_TTL', 86400))
MIN_TTL = int(os.environ.get('MIN_TTL', 60))


###############################################################################
# PYDANTIC MODELS
###############################################################################

class TURNCredentials(BaseModel):
    """TURN credentials response model"""
    username: str = Field(..., description="Time-based username")
    password: str = Field(..., description="HMAC-SHA1 generated password")
    ttl: int = Field(..., ge=60, le=86400, description="Credential lifetime in seconds")
    uris: List[str] = Field(..., description="TURN server URIs")

    class Config:
        json_schema_extra = {
            "example": {
                "username": "1737910400:user123",
                "password": "dGVzdHBhc3N3b3Jk",
                "ttl": 86400,
                "uris": [
                    "turn:turn.example.com:5349?transport=udp",
                    "turn:turn.example.com:5349?transport=tcp",
                    "turns:turn.example.com:5349?transport=tcp"
                ]
            }
        }


class CredentialsRequest(BaseModel):
    """Request model for TURN credentials"""
    username: str = Field(..., min_length=1, max_length=128, description="Username")
    ttl: Optional[int] = Field(DEFAULT_TTL, ge=MIN_TTL, le=MAX_TTL, description="TTL in seconds")

    @validator('username')
    def validate_username(cls, v):
        """Validate username contains only safe characters"""
        if not v or len(v.strip()) == 0:
            raise ValueError('Username cannot be empty')
        # Allow alphanumeric, underscore, hyphen, dot
        import re
        if not re.match(r'^[a-zA-Z0-9._-]+$', v):
            raise ValueError('Username contains invalid characters')
        return v


class HealthResponse(BaseModel):
    """Health check response"""
    status: str
    version: str
    timestamp: datetime


class APIInfo(BaseModel):
    """API information"""
    service: str
    version: str
    description: str


###############################################################################
# AUTHENTICATION
###############################################################################

api_key_header = APIKeyHeader(name="X-API-Key", auto_error=False)


async def verify_api_key(api_key: str = Depends(api_key_header)):
    """Verify API key if configured"""
    if API_KEY and api_key != API_KEY:
        logger.warning(f"Invalid API key attempt from {api_key}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid API key"
        )
    return api_key


###############################################################################
# HELPER FUNCTIONS
###############################################################################

def generate_turn_credentials(username: str, ttl: int = DEFAULT_TTL) -> TURNCredentials:
    """
    Generate time-limited TURN credentials using HMAC-SHA1.

    Args:
        username: The username to generate credentials for
        ttl: Time to live in seconds (default: 86400)

    Returns:
        TURNCredentials object with username, password, ttl, and URIs

    Raises:
        ValueError: If TURN_SECRET is not configured
    """
    if not TURN_SECRET:
        logger.error("TURN_SECRET environment variable not set")
        raise ValueError("TURN server secret not configured")

    # Calculate timestamp for expiry
    timestamp = int(datetime.now().timestamp()) + ttl
    turn_username = f"{timestamp}:{username}"

    # Generate HMAC-SHA1 signature
    hmac_obj = hmac.new(
        TURN_SECRET.encode(),
        turn_username.encode(),
        hashlib.sha1
    )
    password = base64.b64encode(hmac_obj.digest()).decode()

    # Build TURN server URIs
    uris = [
        f"turn:{TURN_SERVER}:{TURN_PORT}?transport=udp",
        f"turn:{TURN_SERVER}:{TURN_PORT}?transport=tcp",
        f"turns:{TURN_SERVER}:5349?transport=tcp"
    ]

    logger.info(f"Generated credentials for user={username}, ttl={ttl}s")

    return TURNCredentials(
        username=turn_username,
        password=password,
        ttl=ttl,
        uris=uris
    )


###############################################################################
# LIFECYCLE MANAGEMENT
###############################################################################

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan manager"""
    logger.info("Starting TURN Credentials API...")

    # Validate configuration
    if not TURN_SECRET:
        logger.warning("TURN_SECRET not set - using insecure default")
    if not API_KEY:
        logger.warning("API_KEY not set - endpoint is not protected")

    logger.info("TURN Credentials API started successfully")
    yield
    logger.info("TURN Credentials API shutting down...")


###############################################################################
# FASTAPI APPLICATION
###############################################################################

app = FastAPI(
    title="TURN Credentials API",
    description="API for generating time-limited TURN credentials for WebRTC",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
    lifespan=lifespan
)


###############################################################################
# ENDPOINTS
###############################################################################

@app.get("/", response_model=APIInfo, tags=["Root"])
async def root() -> APIInfo:
    """
    Root endpoint with API information

    Returns:
        APIInfo: Basic API information
    """
    return APIInfo(
        service="TURN Credentials API",
        version="1.0.0",
        description="Provides time-limited TURN credentials for WebRTC clients"
    )


@app.get("/health", response_model=HealthResponse, tags=["Health"])
async def health_check() -> HealthResponse:
    """
    Health check endpoint

    Returns:
        HealthResponse: Current API health status
    """
    return HealthResponse(
        status="healthy",
        version="1.0.0",
        timestamp=datetime.now()
    )


@app.post("/turn-credentials", response_model=TURNCredentials, tags=["Credentials"])
async def get_turn_credentials(
    request: CredentialsRequest,
    api_key: str = Depends(verify_api_key)
) -> TURNCredentials:
    """
    Generate TURN credentials for a WebRTC client

    This endpoint generates time-limited TURN credentials using HMAC-SHA1
    authentication. The credentials include a username with embedded timestamp
    and a password generated using the TURN server secret.

    Args:
        request: Credentials request with username and optional TTL
        api_key: API key for authentication (if configured)

    Returns:
        TURNCredentials: Generated TURN credentials

    Raises:
        HTTPException: If request validation fails
    """
    try:
        credentials = generate_turn_credentials(
            username=request.username,
            ttl=request.ttl
        )
        logger.info(f"CREDENTIALS_ISSUED: user={request.username}, ttl={request.ttl}s")
        return credentials

    except ValueError as e:
        logger.error(f"Configuration error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="TURN server configuration error"
        )
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error"
        )


@app.get("/turn-credentials", response_model=TURNCredentials, tags=["Credentials"])
async def get_turn_credentials_get(
    username: str,
    ttl: int = DEFAULT_TTL,
    api_key: str = Depends(verify_api_key)
) -> TURNCredentials:
    """
    Generate TURN credentials (GET method for testing)

    This is a convenience endpoint for testing. Use POST for production.

    Args:
        username: Username to generate credentials for
        ttl: Time to live in seconds (default: 86400)
        api_key: API key for authentication (if configured)

    Returns:
        TURNCredentials: Generated TURN credentials
    """
    if not username or len(username) > 128:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid username"
        )

    if ttl < MIN_TTL or ttl > MAX_TTL:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"TTL must be between {MIN_TTL} and {MAX_TTL} seconds"
        )

    return await get_turn_credentials(
        CredentialsRequest(username=username, ttl=ttl),
        api_key
    )


###############################################################################
# ERROR HANDLERS
###############################################################################

from fastapi.responses import JSONResponse


@app.exception_handler(HTTPException)
async def http_exception_handler(request, exc):
    """HTTP exception handler"""
    logger.warning(f"HTTP {exc.status_code}: {exc.detail}")
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "error": exc.detail,
            "status_code": exc.status_code
        }
    )


@app.exception_handler(Exception)
async def general_exception_handler(request, exc):
    """General exception handler"""
    logger.error(f"Unhandled exception: {str(exc)}")
    return JSONResponse(
        status_code=500,
        content={
            "error": "Internal server error",
            "status_code": 500
        }
    )


###############################################################################
# MAIN
###############################################################################

if __name__ == "__main__":
    import uvicorn

    # Run the application
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8080,
        reload=True,
        log_level="info"
    )
