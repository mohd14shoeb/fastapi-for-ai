from enum import Enum


class ErrorCode(str, Enum):
    USER_NOT_FOUND = "USER_001"

    EMAIL_ALREADY_EXISTS = "USER_002"

    INVALID_PASSWORD = "USER_003"

    INTERNAL_ERROR = "SYS_001"
