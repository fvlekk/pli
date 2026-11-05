"""Rate limits over a sliding one-minute window: per user, and for the whole instance.

Why two limits: anonymous Firebase accounts are free to create, so a script can get a new uid for every
request. The per-user limit stops one person spamming; the instance cap bounds what the instance can spend on
the API. The daily caps slow down a leaked App Check token. In memory: a restart resets them, and Render's
free instance restarts after 15 idle minutes, so only the provider's spend limit really bounds a day's cost.
"""

import threading
import time
from collections import Counter, deque

FENETRE = 60  # seconds
JOUR = 86_400  # seconds


def _purger(appels: deque[float], maintenant: float) -> None:
    """Drops the calls older than the window."""
    while appels and maintenant - appels[0] >= FENETRE:
        appels.popleft()


class Limiteur:
    def __init__(
        self,
        par_minute: int,
        par_minute_instance: int,
        par_jour: int,
        par_jour_instance: int,
        horloge=time.monotonic,
    ):
        self.par_minute = par_minute
        self.par_minute_instance = par_minute_instance
        self.horloge = horloge
        self._par_uid: dict[str, deque[float]] = {}
        self._instance: deque[float] = deque()
        self.par_jour = par_jour
        self.par_jour_instance = par_jour_instance
        self._debut_jour = horloge()
        self._jour_par_uid: Counter[str] = Counter()
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

    def autoriser_aujourdhui(self, uid: str) -> bool:
        maintenant = self.horloge()
        with self._verrou:
            if maintenant - self._debut_jour >= JOUR:
                self._debut_jour = maintenant
                self._jour_par_uid.clear()
            if (
                self._jour_par_uid[uid] >= self.par_jour
                or self._jour_par_uid.total() >= self.par_jour_instance
            ):
                return False
            self._jour_par_uid[uid] += 1
            return True

    def suivis(self) -> int:
        """Number of users currently tracked (for tests)."""
        return len(self._par_uid)
