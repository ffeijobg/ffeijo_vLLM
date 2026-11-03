import time
from retry import retry

calls, sleeps = [], []
time.sleep = lambda s: sleeps.append(s)          # no real waiting

@retry(max_attempts=3, base=0.5, exceptions=(ValueError,))
def flaky():
    calls.append(1)
    raise ValueError("boom")

try:
    flaky()
except ValueError:
    pass
assert len(calls) == 3, "must try exactly max_attempts times, then re-raise"
assert len(sleeps) == 2 and sleeps[1] > sleeps[0], "the delay must grow with each attempt"
assert flaky.__name__ == "flaky", "use functools.wraps"

calls.clear()

@retry(exceptions=(ValueError,))
def other():
    calls.append(1)
    raise KeyError("x")

try:
    other()
except KeyError:
    pass
assert len(calls) == 1, "must not retry exceptions that are not listed"
print("all checks passed")
