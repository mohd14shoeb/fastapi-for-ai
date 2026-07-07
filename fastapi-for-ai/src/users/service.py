from sqlalchemy.orm import Session

from . import models
from . import schemas
from .utils import password_context


class UserService:
    def __init__(self, db: Session):
        self.db = db

    def create_user(self, user: schemas.UserCreate):

        db_user = models.User(
            name=user.name,
            email=user.email,
            age=user.age,
            role=user.role.value,
            password=password_context.hash(
                user.password
            ),  # Hash the password before storing
        )

        self.db.add(db_user)
        self.db.commit()
        self.db.refresh(db_user)

        db_address = models.Address(
            street=user.address.street,
            city=user.address.city,
            state=user.address.state,
            zip_code=user.address.zip_code,
            user_id=db_user.id,
        )

        self.db.add(db_address)
        self.db.commit()
        self.db.refresh(db_user)

        return db_user

    def get_all_users(self):

        return self.db.query(models.User).all()

    def get_user_by_id(self, user_id: int):

        return self.db.query(models.User).filter(models.User.id == user_id).first()

    def delete_user(self, user_id: int):

        user = self.get_user_by_id(user_id)

        if user:
            # Delete all associated addresses
            for address in user.addresses:
                self.db.delete(address)

            self.db.delete(user)
            self.db.commit()

        return user


def create_user_address(self, user_id: int, address: schemas.UserAddress):
    """Create a new address for a specific user."""
    db_address = models.Address(
        street=address.street,
        city=address.city,
        state=address.state,
        zip_code=address.zip_code,
        user_id=user_id,
    )
    self.db.add(db_address)
    self.db.commit()
    self.db.refresh(db_address)
    return db_address


def get_user_addresses(self, user_id: int):
    """Get all addresses for a specific user."""
    return self.db.query(models.Address).filter(models.Address.user_id == user_id).all()


def update_user_address(
    self, user_id: int, address_id: int, address: schemas.UserAddress
):
    """Update an existing address for a specific user."""
    db_address = (
        self.db.query(models.Address)
        .filter(models.Address.id == address_id, models.Address.user_id == user_id)
        .first()
    )
    if db_address:
        db_address.street = address.street
        db_address.city = address.city
        db_address.state = address.state
        db_address.zip_code = address.zip_code
        self.db.commit()
        self.db.refresh(db_address)
    return db_address
