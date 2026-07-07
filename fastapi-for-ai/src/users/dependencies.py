from fastapi import Depends
from sqlalchemy.orm import Session

from database import get_db


def get_database(db: Session = Depends(get_db)):
    return db
