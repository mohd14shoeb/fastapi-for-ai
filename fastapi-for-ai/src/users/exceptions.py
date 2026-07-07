from fastapi import status

from core.exceptions import AppException
from core.error_codes import ErrorCode


class UserNotFound(AppException):
    def __init__(self):

        super().__init__(
            message="User not found",
            error_code=ErrorCode.USER_NOT_FOUND,
            status_code=status.HTTP_404_NOT_FOUND,
        )


class EmailAlreadyExists(AppException):
    def __init__(self):

        super().__init__(
            message="Email already exists",
            error_code=ErrorCode.EMAIL_ALREADY_EXISTS,
            status_code=status.HTTP_409_CONFLICT,
        )


# from fastapi import status

# from core.exceptions import AppException


# class UserNotFoundException(AppException):

#     def __init__(self):
#         super().__init__( status_code=status.HTTP_404_NOT_FOUND, message="User not found", error_code="USER_404")


# class EmailAlreadyExistsException(AppException):

#     def __init__(self):

#         super().__init__(
#             status_code=status.HTTP_409_CONFLICT,
#             message="Email already exists",
#             error_code="USER_409"
#         )


# class InvalidPasswordException(AppException):

#     def __init__(self):

#         super().__init__(
#             status_code=status.HTTP_400_BAD_REQUEST,
#             message="Password is invalid",
#             error_code="USER_400"
#         )
