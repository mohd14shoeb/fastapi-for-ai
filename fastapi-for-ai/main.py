# from email.headerregistry import Address

import os

from fastapi import FastAPI, Request
from datetime import datetime, timezone
from fastapi.middleware.cors import CORSMiddleware
from database import Base, engine
from dotenv import load_dotenv
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded

from src.core.rate_limit import limiter
from src.users.router import router as user_router
from src.documents.router import router as files_router
from src.webcrawllingpage.router import router as webcrawl_router

# from src.core.handlers import register_exception_handlers

Base.metadata.create_all(bind=engine)
allowed_origins = (
    os.getenv("allowed_origins", "").split(",") if os.getenv("allowed_origins") else []
)
app = FastAPI()
load_dotenv()  # Load environment variables from .env file

app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# register_exception_handlers(app)
@app.middleware("http")
async def log_request_time(request: Request, call_next):
    start_time = datetime.now(timezone.utc)
    response = await call_next(request)
    process_time = datetime.now(timezone.utc) - start_time
    print(
        f"Path {request.url.path}: Request processing time: {process_time.total_seconds():.4f} seconds"
    )
    return response


app.include_router(user_router)
app.include_router(files_router)
app.include_router(webcrawl_router)
