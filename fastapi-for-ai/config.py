import os

from dotenv import load_dotenv

load_dotenv()  # Load environment variables from .env file


class Settings:
    DATABASE_URL: str = os.getenv("DATABASE_URL", "sqlite:///users.db")
    ALLOWED_ORIGINS: list = (
        os.getenv("allowed_origins", "").split(",")
        if os.getenv("allowed_origins")
        else ["https://fastapi-for-ai.onrender.com/"]
    )
    SECRET_KEY: str = os.getenv("SECRET_KEY", "supersecretkey")
    ALGORITHM: str = os.getenv("ALGORITHM", "HS256")
    ACCESS_TOKEN_EXPIRE_MINUTES: int = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", 30))
    CRAWLING_URL: str = os.getenv("CRAWLING_URL")


settings = Settings()
