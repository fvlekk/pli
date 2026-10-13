from pli.limiteur import Limiteur


class Horloge:
    def __init__(self):
        self.t = 0.0

    def __call__(self):
        return self.t


def test_per_user_limit_resets_after_a_minute():
    horloge = Horloge()
    limiteur = Limiteur(par_minute=2, par_minute_instance=100, horloge=horloge)
    assert limiteur.autoriser("a") and limiteur.autoriser("a")
    assert not limiteur.autoriser("a")
    horloge.t = 60
    assert limiteur.autoriser("a")


def test_instance_cap_stops_a_flood_of_fresh_anonymous_accounts():
    limiteur = Limiteur(par_minute=10, par_minute_instance=5, horloge=Horloge())
    acceptes = sum(limiteur.autoriser(f"anonyme-{i}") for i in range(50))
    assert acceptes == 5


def test_idle_users_are_forgotten():
    horloge = Horloge()
    limiteur = Limiteur(par_minute=10, par_minute_instance=1000, horloge=horloge)
    for i in range(200):
        limiteur.autoriser(f"u{i}")
    horloge.t = 120
    limiteur.autoriser("nouveau")
    assert limiteur.suivis() <= 2  # the newcomer and the instance counter
