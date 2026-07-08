from slowapi import Limiter
from slowapi.util import get_remote_address

# Single shared limiter — import this anywhere
limiter = Limiter(key_func=get_remote_address)
