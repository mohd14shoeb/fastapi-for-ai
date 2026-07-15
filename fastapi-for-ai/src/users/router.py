from fastapi import APIRouter, Depends, Header, HTTPException, Request
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from datetime import datetime, timedelta, timezone
from jose import JWTError, jwt
from sqlalchemy.orm import Session
from config import settings
from src.core.rate_limit import limiter
from .dependencies import get_db
from .service import UserService
from . import models
from .schemas import UserAddressCreate, UserCreate, UserResponse, AddressResponse
from .utils import password_context


router = APIRouter(prefix="/users", tags=["Users"])

# Simple secret key for JWT configuration; in production use env variable
SECRET_KEY = settings.SECRET_KEY
ALGORITHM = settings.ALGORITHM
ACCESS_TOKEN_EXPIRE_MINUTES = settings.ACCESS_TOKEN_EXPIRE_MINUTES


def create_access_token(data: dict, expires_delta: timedelta | None = None):
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + (
        expires_delta or timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    )
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt


@router.get("/check-auth-header")
def check_auth_token_header(x_auth_token: str = Header(None)):
    if not x_auth_token:
        raise HTTPException(status_code=401, detail="X-Auth-Token header missing")
    else:
        try:
            payload = jwt.decode(x_auth_token, SECRET_KEY, algorithms=[ALGORITHM])
            user_id: str = payload.get("sub")
            if user_id is None:
                raise HTTPException(status_code=401, detail="Invalid token")
            return {"user_id": user_id, "payload": payload}
        except JWTError:
            raise HTTPException(status_code=401, detail="Invalid token")


def verify_token(token: str = Depends(OAuth2PasswordBearer(tokenUrl="/users/login"))):
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        user_id: str = payload.get("sub")
        if user_id is None:
            raise HTTPException(status_code=401, detail="Invalid token")
        return user_id
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid token")


# Checking the token in the header for protected routes
@router.get("/protected")
def protected_route(user_id: str = Depends(verify_token)):
    return {"message": f"User_id: {user_id} - You have access to this protected route!"}


# Login endpoint to generate JWT token based on user email
@router.post("/login")
async def login(
    form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)
):
    service = UserService(db)
    # Simple lookup by email
    user = (
        service.db.query(models.User)
        .filter(models.User.email == form_data.username)
        .first()
    )
    if not user:
        raise HTTPException(status_code=401, detail="Invalid email ")
    if not password_context.verify(form_data.password, user.password):
        raise HTTPException(status_code=401, detail="Invalid password")
    access_token = create_access_token(data={"sub": str(user.id)})
    return {
        "access_token": access_token,
        "token_type": "bearer",
        "user_id": user.id,
        "name": user.name,
    }


@router.post("", response_model=UserResponse)
def create_user(user: UserCreate, db: Session = Depends(get_db)):
    service = UserService(db)
    return service.create_user(user)


@router.get("", response_model=list[UserResponse])  # static — same for everyone
@limiter.limit("5/minute")  # rate limit applied to this endpoint
async def get_users(request: Request, db: Session = Depends(get_db)):
    service = UserService(db)
    return service.get_all_users()


@router.get("/{user_id}", response_model=UserResponse)
def get_user(user_id: int, db: Session = Depends(get_db)):
    service = UserService(db)
    user = service.get_user_by_id(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user


@router.get("/{user_id}/address", response_model=list[AddressResponse])
def get_address(user_id: int, db: Session = Depends(get_db)):
    service = UserService(db)
    address = service.get_user_addresses(user_id)
    if not address:
        raise HTTPException(status_code=404, detail="Address not found")
    return address


@router.put("/{user_id}/address/{address_id}", response_model=AddressResponse)
def update_address(
    user_id: int, address_id: int, address: UserCreate, db: Session = Depends(get_db)
):
    service = UserService(db)
    updated_address = service.update_user_address(user_id, address_id, address)
    if not updated_address:
        raise HTTPException(status_code=404, detail="Address not found")
    return updated_address


@router.post("/{user_id}/address", response_model=AddressResponse)
def create_user_address(
    user_id: int, address: UserAddressCreate, db: Session = Depends(get_db)
):
    service = UserService(db)
    new_address = service.create_user_address(user_id, address)
    if not new_address:
        raise HTTPException(status_code=404, detail="User not found")
    return new_address


@router.delete("/{user_id}")
def delete_user(user_id: int, db: Session = Depends(get_db)):
    service = UserService(db)
    user = service.delete_user(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return {"message": "User deleted successfully"}
