from pydantic import BaseModel
from enum import Enum


class UserRole(str, Enum):
    ADMIN = "admin"
    USER = "user"
    CLIENT = "client"


class UserAddressCreate(BaseModel):
    street: str
    city: str
    state: str
    zip_code: str


class AddressResponse(BaseModel):
    id: int
    street: str
    city: str
    state: str
    zip_code: str
    user_id: int

    class Config:
        from_attributes = True


class UserCreate(BaseModel):
    name: str
    age: int
    email: str
    role: UserRole
    address: UserAddressCreate
    password: str


class UserResponse(BaseModel):
    id: int
    name: str
    age: int
    email: str
    role: UserRole
    addresses: list[AddressResponse]

    class Config:
        from_attributes = True
