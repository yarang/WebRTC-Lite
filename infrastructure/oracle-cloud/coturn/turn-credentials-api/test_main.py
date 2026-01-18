"""
Characterization Tests for TURN Credentials API

These tests characterize the current behavior of the TURN Credentials API.
They document what the API actually does, not what it should do.

Test Naming: test_characterize_[component]_[scenario]

Requirements: REQ-U003, REQ-E007, REQ-N001
"""

import pytest
from datetime import datetime, timedelta
from fastapi.testclient import TestClient
from unittest.mock import patch, Mock
import hmac
import hashlib
import base64
import os

from main import (
    app,
    generate_turn_credentials,
    TURNCredentials,
    CredentialsRequest
)


###############################################################################
# TEST FIXTURES
###############################################################################

@pytest.fixture
def client():
    """Test client for FastAPI app"""
    return TestClient(app)


@pytest.fixture
def test_secret():
    """Test TURN secret"""
    return "test-secret-key-12345"


@pytest.fixture
def test_username():
    """Test username"""
    return "testuser123"


@pytest.fixture
def mock_env(test_secret):
    """Mock environment variables"""
    with patch.dict(os.environ, {
        'TURN_SECRET': test_secret,
        'TURN_SERVER': 'turn.example.com',
        'TURN_PORT': '5349',
        'API_KEY': '',
        'DEFAULT_TTL': '86400',
        'MAX_TTL': '86400',
        'MIN_TTL': '60'
    }):
        yield


###############################################################################
# CHARACTERIZATION TESTS: Root Endpoint
###############################################################################

def test_characterize_root_endpoint_returns_api_info(client, mock_env):
    """
    Characterize: Root endpoint returns API information

    Documents what the root endpoint actually returns.
    This is characterization - it captures current behavior.
    """
    response = client.get("/")

    # Characterize actual response structure
    assert response.status_code == 200
    data = response.json()
    assert "service" in data
    assert data["service"] == "TURN Credentials API"
    assert "version" in data
    assert data["version"] == "1.0.0"
    assert "description" in data


###############################################################################
# CHARACTERIZATION TESTS: Health Check
###############################################################################

def test_characterize_health_check_returns_healthy_status(client, mock_env):
    """
    Characterize: Health check returns healthy status

    Documents the actual health check response structure.
    """
    response = client.get("/health")

    # Characterize actual response
    assert response.status_code == 200
    data = response.json()
    assert "status" in data
    assert data["status"] == "healthy"
    assert "timestamp" in data
    assert "version" in data


###############################################################################
# CHARACTERIZATION TESTS: Credentials Generation
###############################################################################

def test_characterize_credentials_generation_structure(mock_env, test_username, test_secret):
    """
    Characterize: Credentials generation produces specific structure

    Documents the actual structure of generated credentials.
    """
    credentials = generate_turn_credentials(test_username, ttl=3600)

    # Characterize actual structure
    assert isinstance(credentials, TURNCredentials)
    assert hasattr(credentials, 'username')
    assert hasattr(credentials, 'password')
    assert hasattr(credentials, 'ttl')
    assert hasattr(credentials, 'uris')

    # Characterize username format (timestamp:username)
    assert ':' in credentials.username
    parts = credentials.username.split(':')
    assert len(parts) == 2
    assert parts[1] == test_username

    # Characterize password encoding (base64)
    decoded = base64.b64decode(credentials.password)
    assert len(decoded) > 0

    # Characterize URIs
    assert len(credentials.uris) >= 2
    assert any('turn:' in uri for uri in credentials.uris)


def test_characterize_credentials_password_is_hmac_sha1(mock_env, test_username, test_secret):
    """
    Characterize: Password is generated using HMAC-SHA1

    Verifies the actual password generation algorithm.
    """
    credentials = generate_turn_credentials(test_username, ttl=3600)

    # Reconstruct expected HMAC
    username_parts = credentials.username.split(':')
    timestamp = username_parts[0]

    hmac_obj = hmac.new(
        test_secret.encode(),
        credentials.username.encode(),
        hashlib.sha1
    )
    expected_password = base64.b64encode(hmac_obj.digest()).decode()

    # Characterize: Password matches HMAC-SHA1
    assert credentials.password == expected_password


def test_characterize_credentials_timestamp_is_future(mock_env, test_username):
    """
    Characterize: Credentials contain future timestamp

    Documents how timestamp is calculated.
    """
    ttl = 3600
    credentials = generate_turn_credentials(test_username, ttl=ttl)

    # Extract timestamp from username
    username_parts = credentials.username.split(':')
    timestamp = int(username_parts[0])

    # Characterize: Timestamp is in future
    now = int(datetime.now().timestamp())
    assert timestamp > now

    # Characterize: Timestamp is approximately TTL seconds in future
    time_diff = timestamp - now
    assert time_diff >= ttl - 10  # Allow 10 second margin
    assert time_diff <= ttl + 10


###############################################################################
# CHARACTERIZATION TESTS: POST Endpoint
###############################################################################

def test_characterize_post_credentials_returns_valid_response(client, mock_env, test_username):
    """
    Characterize: POST /turn-credentials returns valid response

    Documents the actual POST endpoint behavior.
    """
    request_data = {
        "username": test_username,
        "ttl": 3600
    }

    response = client.post("/turn-credentials", json=request_data)

    # Characterize actual response
    assert response.status_code == 200
    data = response.json()

    # Characterize response structure
    assert "username" in data
    assert "password" in data
    assert "ttl" in data
    assert "uris" in data
    assert isinstance(data["uris"], list)


def test_characterize_post_credentials_validates_username(client, mock_env):
    """
    Characterize: POST endpoint validates username format

    Documents actual username validation behavior.
    """
    # Test empty username
    response = client.post("/turn-credentials", json={"username": "", "ttl": 3600})
    assert response.status_code == 422  # Validation error

    # Test invalid characters
    response = client.post("/turn-credentials", json={"username": "user@#$%", "ttl": 3600})
    assert response.status_code == 422  # Validation error


def test_characterize_post_credentials_validates_ttl_range(client, mock_env, test_username):
    """
    Characterize: POST endpoint validates TTL range

    Documents actual TTL validation behavior.
    """
    # Test TTL below minimum
    response = client.post("/turn-credentials", json={"username": test_username, "ttl": 30})
    assert response.status_code == 422  # Validation error

    # Test TTL above maximum
    response = client.post("/turn-credentials", json={"username": test_username, "ttl": 100000})
    assert response.status_code == 422  # Validation error


###############################################################################
# CHARACTERIZATION TESTS: GET Endpoint
###############################################################################

def test_characterize_get_credentials_returns_valid_response(client, mock_env, test_username):
    """
    Characterize: GET /turn-credentials returns valid response

    Documents the actual GET endpoint behavior.
    """
    response = client.get(f"/turn-credentials?username={test_username}&ttl=3600")

    # Characterize actual response
    assert response.status_code == 200
    data = response.json()
    assert "username" in data
    assert "password" in data


###############################################################################
# CHARACTERIZATION TESTS: Error Handling
###############################################################################

def test_characterize_missing_secret_returns_error(client, test_username):
    """
    Characterize: Missing TURN_SECRET causes error

    Documents actual error handling for missing configuration.
    Actual: Returns 200 with password generated from empty secret.
    """
    with patch.dict(os.environ, {'TURN_SECRET': '', 'TURN_SERVER': 'turn.example.com', 'TURN_PORT': '5349'}):
        response = client.get(f"/turn-credentials?username={test_username}")

        # Characterize actual behavior: Returns 200 with credentials (not secure, but documents reality)
        assert response.status_code == 200
        data = response.json()
        # When secret is empty, HMAC still generates password (using empty key)
        assert "password" in data
        # The password is generated but insecure (empty key)
        assert len(data["password"]) > 0


def test_characterize_invalid_username_returns_validation_error(client, mock_env):
    """
    Characterize: Invalid username returns validation error

    Documents actual validation error format.
    Actual: Returns 400 with error detail from manual validation.
    """
    # Characterize: Empty username triggers manual validation error
    response = client.get("/turn-credentials?username=")

    # Characterize actual behavior: Returns 400 (manual validation, not 422)
    assert response.status_code == 400
    data = response.json()
    assert "error" in data


###############################################################################
# CHARACTERIZATION TESTS: URI Generation
###############################################################################

def test_characterize_generated_uris_include_transport_types(mock_env, test_username):
    """
    Characterize: Generated URIs include different transport types

    Documents actual URI generation behavior.
    """
    credentials = generate_turn_credentials(test_username, ttl=3600)

    # Characterize: URIs contain UDP transport
    assert any('transport=udp' in uri for uri in credentials.uris)

    # Characterize: URIs contain TCP transport
    assert any('transport=tcp' in uri for uri in credentials.uris)

    # Characterize: URIs contain TURNS (secure) transport
    assert any('turns:' in uri for uri in credentials.uris)


def test_characterize_generated_uris_use_correct_server_and_port(mock_env, test_username):
    """
    Characterize: Generated URIs use configured server and port

    Documents actual URI format.
    """
    credentials = generate_turn_credentials(test_username, ttl=3600)

    # Characterize: URIs contain server name
    assert all('turn.example.com' in uri for uri in credentials.uris)

    # Characterize: URIs contain correct ports
    assert any(':5349' in uri for uri in credentials.uris)


###############################################################################
# BEHAVIOR SNAPSHOT: Complete Credential Response
###############################################################################

def test_characterize_complete_credentials_snapshot(mock_env, test_username):
    """
    Snapshot: Complete credentials response for reference

    This test captures a complete snapshot of the credentials response
    for documentation purposes.
    """
    credentials = generate_turn_credentials(test_username, ttl=3600)

    # Snapshot the complete structure
    snapshot = {
        "username": credentials.username,
        "password": credentials.password,
        "ttl": credentials.ttl,
        "uris": credentials.uris
    }

    # Document the snapshot structure
    assert isinstance(snapshot["username"], str)
    assert isinstance(snapshot["password"], str)
    assert isinstance(snapshot["ttl"], int)
    assert isinstance(snapshot["uris"], list)
    assert all(isinstance(uri, str) for uri in snapshot["uris"])

    # This serves as documentation of actual behavior
    print(f"\nCREDENTIALS_SNAPSHOT: {snapshot}")
