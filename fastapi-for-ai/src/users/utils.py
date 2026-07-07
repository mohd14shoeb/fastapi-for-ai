from passlib.context import CryptContext

# Shared password hashing context (sha256_crypt avoids bcrypt binary issues on some platforms)
password_context = CryptContext(schemes=["sha256_crypt"], deprecated="auto")


def capitalize_name(name: str):

    return name.title()
