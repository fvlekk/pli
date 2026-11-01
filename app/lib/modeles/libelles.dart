/// French labels for the ids shared with the backend schema and the Firestore rules.
const organismes = {
  'impots': 'Impôts',
  'caf': 'Caf',
  'assurance_maladie': 'Assurance Maladie',
  'urssaf': 'Urssaf',
  'france_travail': 'France Travail',
  'prefecture': 'Préfecture',
  'antai': 'Amendes',
  'crous': 'Crous',
  'ants': 'ANTS',
  'mutuelle': 'Mutuelle',
  'assurance': 'Assurance',
  'energie': 'Énergie',
  'bailleur': 'Logement',
  'autre': 'Autre',
};

const actions = {
  'payer': 'Payer',
  'declarer': 'Déclarer',
  'envoyer_documents': 'Envoyer des documents',
  'renouveler': 'Renouveler',
  'se_presenter': 'Se présenter',
  'demander': 'Faire la demande',
  'repondre': 'Répondre',
  'aucune': 'Rien à faire',
};

String libelleOrganisme(String id) => organismes[id] ?? 'Autre';

/// One emoji per organisation, shown in its pill (like Buddy's category pills).
const _emojis = {
  'impots': '🧾',
  'caf': '👶',
  'assurance_maladie': '🩺',
  'urssaf': '💼',
  'france_travail': '🧑‍💼',
  'prefecture': '🏛️',
  'antai': '🚗',
  'crous': '🎓',
  'ants': '🪪',
  'mutuelle': '💊',
  'assurance': '🛡️',
  'energie': '⚡',
  'bailleur': '🏠',
  'autre': '✉️',
};

String emojiOrganisme(String id) => _emojis[id] ?? '✉️';
