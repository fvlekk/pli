"""Rate limits over a sliding one-minute window and over a day: per user, per client IP, and for the instance.

Why three limits: anonymous Firebase accounts are free to create, so a script can get a new uid for
every request. The per-user limit stops one person spamming; the per-IP limit stops one machine cycling
through fresh accounts; the instance cap bounds what the instance can spend on the API. The daily caps slow
down a leaked App Check token. An unknown IP (proxy header missing) is only held by the other limits.
In memory: a restart resets them, and Render's free instance restarts after 15 idle minutes, so only the
provider's spend limit really bounds a day's cost.
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
        par_minute_ip: int,
        par_jour_ip: int,
        horloge=time.monotonic,
    ):
        self.par_minute = par_minute
        self.par_minute_instance = par_minute_instance
        self.par_minute_ip = par_minute_ip
        self.horloge = horloge
        self._par_uid: dict[str, deque[float]] = {}
        self._par_ip: dict[str, deque[float]] = {}
        self._instance: deque[float] = deque()
        self.par_jour = par_jour
        self.par_jour_instance = par_jour_instance
        self.par_jour_ip = par_jour_ip
        self._debut_jour = horloge()
        self._jour_par_uid: Counter[str] = Counter()
        self._jour_par_ip: Counter[str] = Counter()
        self._verrou = threading.Lock()

    def autoriser(self, uid: str, ip: str | None) -> bool:
        maintenant = self.horloge()
        with self._verrou:
            # Forget idle users and addresses, so memory does not grow with every one ever seen.
            for suivis in (self._par_uid, self._par_ip):
                for cle in [c for c, a in suivis.items() if not a or maintenant - a[-1] >= FENETRE]:
                    del suivis[cle]

            appels = self._par_uid.get(uid, deque())
            appels_ip = self._par_ip.get(ip, deque()) if ip is not None else deque()
            for file in (appels, appels_ip, self._instance):
                _purger(file, maintenant)
            if (
                len(appels) >= self.par_minute
                or len(appels_ip) >= self.par_minute_ip
                or len(self._instance) >= self.par_minute_instance
            ):
                return False
            appels.append(maintenant)
            self._par_uid[uid] = appels
            if ip is not None:
                appels_ip.append(maintenant)
                self._par_ip[ip] = appels_ip
            self._instance.append(maintenant)
            return True

    def autoriser_aujourdhui(self, uid: str, ip: str | None) -> bool:
        maintenant = self.horloge()
        with self._verrou:
            if maintenant - self._debut_jour >= JOUR:
                self._debut_jour = maintenant
                self._jour_par_uid.clear()
                self._jour_par_ip.clear()
            if (
                self._jour_par_uid[uid] >= self.par_jour
                or (ip is not None and self._jour_par_ip[ip] >= self.par_jour_ip)
                or self._jour_par_uid.total() >= self.par_jour_instance
            ):
                return False
            self._jour_par_uid[uid] += 1
            if ip is not None:
                self._jour_par_ip[ip] += 1
            return True

    def suivis(self) -> int:
        """Number of users and addresses currently tracked (for tests)."""
        return len(self._par_uid) + len(self._par_ip)
