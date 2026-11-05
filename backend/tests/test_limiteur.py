from pli.limiteur import Limiteur


class Horloge:
    def __init__(self):
        self.t = 0.0

    def __call__(self):
        return self.t


def test_per_user_limit_resets_after_a_minute():
    horloge = Horloge()
    limiteur = Limiteur(2, 100, 1000, 1000, horloge=horloge)
    assert limiteur.autoriser("a") and limiteur.autoriser("a")
    assert not limiteur.autoriser("a")
    horloge.t = 60
    assert limiteur.autoriser("a")


def test_instance_cap_stops_a_flood_of_fresh_anonymous_accounts():
    limiteur = Limiteur(10, 5, 1000, 1000, horloge=Horloge())
    acceptes = sum(limiteur.autoriser(f"anonyme-{i}") for i in range(50))
    assert acceptes == 5


def test_idle_users_are_forgotten():
    horloge = Horloge()
    limiteur = Limiteur(10, 1000, 1000, 1000, horloge=horloge)
    for i in range(200):
        limiteur.autoriser(f"u{i}")
    horloge.t = 120
    limiteur.autoriser("nouveau")
    assert limiteur.suivis() <= 2  # the newcomer and the instance counter


def test_daily_limit_per_user_resets_after_a_day():
    horloge = Horloge()
    limiteur = Limiteur(10, 100, 2, 100, horloge=horloge)
    assert limiteur.autoriser_aujourdhui("alice")
    assert limiteur.autoriser_aujourdhui("alice")
    assert not limiteur.autoriser_aujourdhui("alice")
    assert limiteur.autoriser_aujourdhui("bob"), "another user keeps their own allowance"
    horloge.t = 86_400
    assert limiteur.autoriser_aujourdhui("alice")


def test_daily_limit_for_the_instance_stops_new_accounts():
    limiteur = Limiteur(10, 100, 5, 2, horloge=Horloge())
    assert limiteur.autoriser_aujourdhui("a")
    assert limiteur.autoriser_aujourdhui("b")
    assert not limiteur.autoriser_aujourdhui("c")
