# jac/roundtable/clock.jac
# The engine never reads the wall clock directly, so deadlines can be tested.

import from datetime { datetime, timedelta, timezone }

obj Clock {
    # Leave `fixed` unset for the real clock. With it set, now() returns that
    # instant and then moves it forward by `step_s`, which simulates time
    # passing during a run.
    has fixed: datetime | None = None,
        step_s: float = 0.0;

    def now() -> datetime {
        current = self.fixed;
        if current is None {
            return datetime.now(timezone.utc);
        }
        self.fixed = current + timedelta(seconds=self.step_s);
        return current;
    }
}

def fmt_ts(t: datetime) -> str {
    return t.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ");
}
