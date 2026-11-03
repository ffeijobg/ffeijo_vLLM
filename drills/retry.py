import functools, random, time

def retry(max_attempts=3, base=0.5, exceptions=(Exception,)):
    def deco(fn):
        @functools.wraps(fn)
        def wrapper(*a, **kw):
            for attempt in range(max_attempts):
                try:
                    return fn(*a, **kw)
                except exceptions:
                    if attempt == max_attempts - 1:
                        raise
                    time.sleep(base * 2 ** attempt + random.uniform(0, base / 2))
        return wrapper
    return deco
