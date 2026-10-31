"""Rate limits over a sliding one-minute window: per user, and for the whole instance.

Why two limits: anonymous Firebase accounts are free to create, so a script can get a new uid for every
request. The per-user limit stops one person spamming; the instance cap bounds what one Cloud Run instance can
spend on the API (times --max-instances). In memory, so per instance. App Check comes before a public launch.
"""

import threading
import time
from collections import deque

FENETRE = 60  # seconds


def _purger(appels: deque[float], maintenant: float) -> None:
    """Drops the calls older than the window."""
    while appels and maintenant - appels[0] >= FENETRE:
        appels.popleft()


class Limiteur:
    def __init__(self, par_minute: int, par_minute_instance: int, horloge=time.monotonic):
        self.par_minute = par_minute
        self.par_minute_instance = par_minute_instance
        self.horloge = horloge
        self._par_uid: dict[str, deque[float]] = {}
        self._instance: deque[float] = deque()
        self._verrou = threading.Lock()

    def autoriser(self, uid: str) -> bool:
        maintenant = self.horloge()
        with self._verrou:
            # Forget idle users, so memory does not grow with every uid ever seen.
            for cle in [c for c, a in self._par_uid.items() if maintenant - a[-1] >= FENETRE]:
                del self._par_uid[cle]

            appels = self._par_uid.setdefault(uid, deque())
            _purger(appels, maintenant)
            _purger(self._instance, maintenant)
            if len(appels) >= self.par_minute or len(self._instance) >= self.par_minute_instance:
                if not appels:
                    del self._par_uid[uid]
                return False
            appels.append(maintenant)
            self._instance.append(maintenant)
            return True

    def suivis(self) -> int:
        """Number of users currently tracked (for tests)."""
        return len(self._par_uid)
