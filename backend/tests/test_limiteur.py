from pli.limiteur import Limiteur


class Horloge:
    def __init__(self):
        self.t = 0.0

    def __call__(self):
        return self.t


def test_per_user_limit_resets_after_a_minute():
    horloge = Horloge()
    limiteur = Limiteur(2, 100, 1000, 1000, 1000, 1000, horloge=horloge)
    assert limiteur.autoriser("a", None) and limiteur.autoriser("a", None)
    assert not limiteur.autoriser("a", None)
    horloge.t = 60
    assert limiteur.autoriser("a", None)


def test_instance_cap_stops_a_flood_of_fresh_anonymous_accounts():
    limiteur = Limiteur(10, 5, 1000, 1000, 1000, 1000, horloge=Horloge())
    acceptes = sum(limiteur.autoriser(f"anonyme-{i}", None) for i in range(50))
    assert acceptes == 5


def test_idle_users_are_forgotten():
    horloge = Horloge()
    limiteur = Limiteur(10, 1000, 1000, 1000, 1000, 1000, horloge=horloge)
    for i in range(200):
        limiteur.autoriser(f"u{i}", None)
    horloge.t = 120
    limiteur.autoriser("nouveau", None)
    assert limiteur.suivis() <= 2  # the newcomer and the instance counter


def test_daily_limit_per_user_resets_after_a_day():
    horloge = Horloge()
    limiteur = Limiteur(10, 100, 2, 100, 1000, 1000, horloge=horloge)
    assert limiteur.autoriser_aujourdhui("alice", None)
    assert limiteur.autoriser_aujourdhui("alice", None)
    assert not limiteur.autoriser_aujourdhui("alice", None)
    assert limiteur.autoriser_aujourdhui("bob", None), "another user keeps their own allowance"
    horloge.t = 86_400
    assert limiteur.autoriser_aujourdhui("alice", None)


def test_daily_limit_for_the_instance_stops_new_accounts():
    limiteur = Limiteur(10, 100, 5, 2, 1000, 1000, horloge=Horloge())
    assert limiteur.autoriser_aujourdhui("a", None)
    assert limiteur.autoriser_aujourdhui("b", None)
    assert not limiteur.autoriser_aujourdhui("c", None)


def test_one_address_cycling_fresh_accounts_is_stopped():
    horloge = Horloge()
    limiteur = Limiteur(10, 100, 1000, 1000, 3, 1000, horloge=horloge)
    acceptes = sum(limiteur.autoriser(f"anonyme-{i}", "203.0.113.7") for i in range(10))
    assert acceptes == 3
    assert limiteur.autoriser("anonyme-x", "198.51.100.1"), "another address keeps its own allowance"
    horloge.t = 60
    assert limiteur.autoriser("anonyme-y", "203.0.113.7")


def test_a_refusal_by_address_costs_the_user_nothing():
    limiteur = Limiteur(2, 100, 1000, 1000, 1, 1000, horloge=Horloge())
    assert limiteur.autoriser("alice", "203.0.113.7")
    assert not limiteur.autoriser("alice", "203.0.113.7")
    assert limiteur.autoriser("alice", "198.51.100.1"), "the refused call was not counted for alice"


def test_daily_limit_per_address_resets_after_a_day():
    horloge = Horloge()
    limiteur = Limiteur(10, 100, 1000, 1000, 1000, 2, horloge=horloge)
    assert limiteur.autoriser_aujourdhui("a", "203.0.113.7")
    assert limiteur.autoriser_aujourdhui("b", "203.0.113.7")
    assert not limiteur.autoriser_aujourdhui("c", "203.0.113.7")
    assert limiteur.autoriser_aujourdhui("c", None), "an unknown address is held by the other limits only"
    horloge.t = 86_400
    assert limiteur.autoriser_aujourdhui("d", "203.0.113.7")


def test_idle_addresses_are_forgotten():
    horloge = Horloge()
    limiteur = Limiteur(10, 1000, 1000, 1000, 1000, 1000, horloge=horloge)
    for i in range(200):
        limiteur.autoriser(f"u{i}", f"10.0.0.{i}")
    horloge.t = 120
    limiteur.autoriser("nouveau", "10.0.1.1")
    assert limiteur.suivis() == 2
