import { readFileSync } from "node:fs";
import { after, before, beforeEach, describe, test } from "node:test";

import { assertFails, assertSucceeds, initializeTestEnvironment } from "@firebase/rules-unit-testing";
import {
  Timestamp,
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  serverTimestamp,
  setDoc,
  updateDoc,
} from "firebase/firestore";

let env;

const echeance = (champs = {}) => ({
  organisme: "impots",
  organismeNom: "Finances publiques",
  action: "payer",
  titre: "Payer l'impôt sur le revenu",
  dateLimite: Timestamp.fromDate(new Date("2026-11-15T00:00:00Z")),
  montant: 120,
  resume: "Tu dois payer 120 € avant le 15 novembre.",
  aVerifier: false,
  fait: false,
  source: "claude",
  creeLe: serverTimestamp(),
  ...champs,
});

const base = (uid) => env.authenticatedContext(uid).firestore();
const chemin = (db, uid, id = "e1") => doc(db, "users", uid, "echeances", id);

async function creerPourAlice() {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(chemin(ctx.firestore(), "alice"), { ...echeance(), creeLe: Timestamp.now() });
  });
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-pli",
    firestore: { rules: readFileSync(new URL("../firestore.rules", import.meta.url), "utf8") },
  });
});

beforeEach(async () => env.clearFirestore());
after(async () => env.cleanup());

describe("read", () => {
  test("a user reads their own deadlines", async () => {
    await creerPourAlice();
    await assertSucceeds(getDoc(chemin(base("alice"), "alice")));
    await assertSucceeds(getDocs(collection(base("alice"), "users", "alice", "echeances")));
  });

  test("a user cannot read someone else's deadlines, one by one or as a list", async () => {
    await creerPourAlice();
    await assertFails(getDoc(chemin(base("bob"), "alice")));
    await assertFails(getDocs(collection(base("bob"), "users", "alice", "echeances")));
  });

  test("signed-out visitors read nothing", async () => {
    await creerPourAlice();
    await assertFails(getDoc(chemin(env.unauthenticatedContext().firestore(), "alice")));
  });

  test("everything outside users/{uid}/echeances is closed", async () => {
    await assertFails(getDoc(doc(base("alice"), "users", "alice")));
    await assertFails(setDoc(doc(base("alice"), "journal", "x"), { a: 1 }));
  });
});

describe("create", () => {
  test("a valid deadline is accepted", async () => {
    await assertSucceeds(setDoc(chemin(base("alice"), "alice"), echeance()));
  });

  test("a deadline without amount is accepted", async () => {
    await assertSucceeds(setDoc(chemin(base("alice"), "alice"), echeance({ action: "declarer", montant: null })));
  });

  test("signed-out visitors cannot create anything", async () => {
    await assertFails(setDoc(chemin(env.unauthenticatedContext().firestore(), "alice"), echeance()));
  });

  test("nobody writes into someone else's space", async () => {
    await assertFails(setDoc(chemin(base("bob"), "alice"), echeance()));
  });

  test("creation date is the server's, not the client's", async () => {
    const triche = echeance({ creeLe: Timestamp.fromDate(new Date("2020-01-01")) });
    await assertFails(setDoc(chemin(base("alice"), "alice"), triche));
  });

  test("a new deadline cannot start as done", async () => {
    await assertFails(setDoc(chemin(base("alice"), "alice"), echeance({ fait: true })));
  });

  test("unknown fields are refused", async () => {
    await assertFails(setDoc(chemin(base("alice"), "alice"), echeance({ admin: true })));
  });

  test("missing fields are refused", async () => {
    const { titre, ...sansTitre } = echeance();
    await assertFails(setDoc(chemin(base("alice"), "alice"), sansTitre));
  });

  for (const [nom, champs] of [
    ["unknown organisation", { organisme: "nasa" }],
    ["unknown action", { action: "pirater" }],
    ["empty title", { titre: "" }],
    ["title too long", { titre: "x".repeat(121) }],
    ["date as a string", { dateLimite: "2026-11-15" }],
    ["negative amount", { montant: -1 }],
    ["absurd amount", { montant: 1000000 }],
    ["amount as a string", { montant: "120" }],
    ["unknown source", { source: "pirate" }],
  ]) {
    test(`refused: ${nom}`, async () => {
      await assertFails(setDoc(chemin(base("alice"), "alice"), echeance(champs)));
    });
  }
});

describe("update and delete", () => {
  test("the owner ticks a deadline done", async () => {
    await creerPourAlice();
    await assertSucceeds(updateDoc(chemin(base("alice"), "alice"), { fait: true }));
  });

  test("the owner corrects the date and the amount", async () => {
    await creerPourAlice();
    const correction = { dateLimite: Timestamp.fromDate(new Date("2026-11-10T00:00:00Z")), montant: 90 };
    await assertSucceeds(updateDoc(chemin(base("alice"), "alice"), correction));
  });

  test("what the letter said cannot be rewritten: origin, creation date, sender, summary", async () => {
    await creerPourAlice();
    for (const champs of [
      { source: "manuel" },
      { creeLe: Timestamp.now() },
      { organisme: "caf" },
      { organismeNom: "Quelqu'un d'autre" },
      { resume: "Rien à payer." },
      { action: "aucune" },
    ]) {
      await assertFails(updateDoc(chemin(base("alice"), "alice"), champs));
    }
  });

  test("an update still has to be a valid deadline", async () => {
    await creerPourAlice();
    await assertFails(updateDoc(chemin(base("alice"), "alice"), { montant: -5 }));
  });

  test("someone else cannot tick it or delete it", async () => {
    await creerPourAlice();
    await assertFails(updateDoc(chemin(base("bob"), "alice"), { fait: true }));
    await assertFails(deleteDoc(chemin(base("bob"), "alice")));
  });

  test("the owner deletes it", async () => {
    await creerPourAlice();
    await assertSucceeds(deleteDoc(chemin(base("alice"), "alice")));
  });
});
