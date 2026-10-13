"""Rate limits (sliding one-minute window): per user, and for the whole instance.

The per-user limit alone is not enough: anonymous Firebase accounts are free to create, so a script can get a
new uid for every request. The instance-wide cap bounds what one Cloud Run instance can spend on the API
(times --max-instances for the service). App Check is the next layer before a public launch.
In memory, so per instance: a shared store (Firestore, Redis) is the next step if needed.
"""

import threading
import time
from collections import defaultdict, deque

GLOBAL = "*"


class Limiteur:
    def __init__(self, par_minute: int, par_minute_instance: int, horloge=time.monotonic):
        self.limites = {GLOBAL: par_minute_instance}
        self.par_minute = par_minute
        self.horloge = horloge
        self._appels: dict[str, deque[float]] = defaultdict(deque)
        self._verrou = threading.Lock()
        self._dernier_menage = horloge()

    def _purger(self, appels: deque[float], maintenant: float) -> None:
        while appels and maintenant - appels[0] >= 60:
            appels.popleft()

    def _menage(self, maintenant: float) -> None:
        """Forgets users with no call in the last minute, so memory does not grow with every uid seen."""
        if maintenant - self._dernier_menage < 60:
            return
        self._dernier_menage = maintenant
        for cle in [c for c, appels in self._appels.items() if not appels or maintenant - appels[-1] >= 60]:
            del self._appels[cle]

    def autoriser(self, cle: str) -> bool:
        maintenant = self.horloge()
        with self._verrou:
            self._menage(maintenant)
            utilisateur, instance = self._appels[cle], self._appels[GLOBAL]
            self._purger(utilisateur, maintenant)
            self._purger(instance, maintenant)
            if len(utilisateur) >= self.par_minute or len(instance) >= self.limites[GLOBAL]:
                return False
            utilisateur.append(maintenant)
            instance.append(maintenant)
            return True

    def suivis(self) -> int:
        return len(self._appels)
