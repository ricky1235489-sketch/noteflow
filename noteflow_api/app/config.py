from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    app_name: str = "NoteFlow API"
    debug: bool = True

    # Database (async PostgreSQL for prod, SQLite for dev)
    database_url: str = "sqlite+aiosqlite:///./noteflow.db"

    # Firebase Auth
    firebase_project_id: str = ""  # Empty = dev mode (skip verification)

    # Storage (local for dev, S3 for prod)
    upload_dir: str = "./uploads"
    output_dir: str = "./outputs"

    # Redis (for Celery task queue)
    redis_url: str = "redis://localhost:6379/0"

    # Audio constraints
    max_file_size_bytes: int = 50 * 1024 * 1024  # 50MB
    allowed_extensions: set[str] = {".mp3", ".wav", ".m4a"}
    free_max_duration_seconds: int = 30
    pro_max_duration_seconds: int = 600

    # Rate limits
    free_monthly_conversions: int = 3

    # S3 / Cloudflare R2 (empty = use local storage)
    s3_bucket: str = ""
    s3_region: str = "us-east-1"
    s3_endpoint_url: str = ""  # For R2: https://<account>.r2.cloudflarestorage.com
    s3_access_key_id: str = ""
    s3_secret_access_key: str = ""

    # CORS
    cors_origins: list[str] = ["http://localhost:*", "http://127.0.0.1:*"]

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8"}


settings = Settings()
