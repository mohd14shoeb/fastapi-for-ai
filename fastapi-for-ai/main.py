# from email.headerregistry import Address

from fastapi import FastAPI, Request
from datetime import datetime, timezone
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from database import Base, engine
from src.users.router import router as user_router
# from src.core.handlers import register_exception_handlers

Base.metadata.create_all(bind=engine)

app = FastAPI()
app.add_middleware(
    TrustedHostMiddleware,
    allowed_hosts=["127.0.0.1:53331", "localhost:53331", "localhost", "127.0.0.1"],
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

# class UserRole(str, Enum):
#     ADMIN = "admin"
#     USER = "user"
#     CLIENT = "client"


# app = FastAPI()


# class Address(BaseModel):
#     street: str
#     city: str
#     state: str
#     zip_code: str


# class User(BaseModel):
#     user_name: str
#     user_age: int
#     user_role: UserRole
#     user_email: str
#     user_address: Address


# @app.get("/")
# async def read_root():
#     return {"Hello": "World welcome india"}

# @app.get("/users/{user_id}")
# async def get_users(user_id: int):
#     return {"user_id ": user_id, "message": f"Hello user {user_id}, welcome india"}


# @app.get("/products/{product}")
# async def get_products(product: str):
#     return {"product ": product, "message": f"Hello product {product}, welcome india"}


# @app.get("/users/{user_id}/products/{product_id}")
# async def get_user_products(user_id: int, product_id: str):
#     return {
#         "user_id ": user_id,
#         "product_id": product_id,
#         "message": f"Hello user {user_id}, welcome india, you asked for product {product_id}",
#     }


# @app.get("/users/role/{role}")
# async def get_users_by_role(role: UserRole):
#     return {
#         "role": role.value,
#         "message": f"Fetching all {role.value} roles",
#         "all_roles": [r.value for r in UserRole],
#     }


# @app.post("/create-user/")
# async def create_user(user: User):
#     return {
#         "data": user,
#         "message": f"User created with name {user.user_name}",
#     }


# @app.get("/users/")
# async def get_all_users():
#     return {"message": "Fetching all users", "users": ["user1", "user2", "user3"]}
