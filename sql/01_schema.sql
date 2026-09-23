-- ============================================
-- SCHÉMA BASE GESTION COMMERCIALE
-- ============================================

DROP TABLE IF EXISTS lignes_commande CASCADE;
DROP TABLE IF EXISTS paiements CASCADE;
DROP TABLE IF EXISTS commandes CASCADE;
DROP TABLE IF EXISTS stocks CASCADE;
DROP TABLE IF EXISTS produits CASCADE;
DROP TABLE IF EXISTS clients CASCADE;

-- 👥 CLIENTS
CREATE TABLE clients (
    id              SERIAL PRIMARY KEY,
    nom             VARCHAR(100) NOT NULL,
    prenom          VARCHAR(100),
    email           VARCHAR(150) UNIQUE,
    telephone       VARCHAR(20),
    adresse         TEXT,
    ville           VARCHAR(80),
    pays            VARCHAR(80) DEFAULT 'Madagascar',
    date_inscription TIMESTAMP DEFAULT NOW(),
    actif           BOOLEAN DEFAULT TRUE
);

-- 📦 PRODUITS
CREATE TABLE produits (
    id              SERIAL PRIMARY KEY,
    reference       VARCHAR(50) UNIQUE NOT NULL,
    designation     VARCHAR(200) NOT NULL,
    categorie       VARCHAR(80),
    prix_unitaire   NUMERIC(12,2) NOT NULL CHECK (prix_unitaire >= 0),
    actif           BOOLEAN DEFAULT TRUE,
    date_creation   TIMESTAMP DEFAULT NOW()
);

-- 📊 STOCKS
CREATE TABLE stocks (
    id              SERIAL PRIMARY KEY,
    produit_id      INTEGER REFERENCES produits(id),
    quantite        INTEGER NOT NULL DEFAULT 0,
    seuil_alerte    INTEGER DEFAULT 10,
    date_maj        TIMESTAMP DEFAULT NOW()
);

-- 🧾 COMMANDES
CREATE TABLE commandes (
    id              SERIAL PRIMARY KEY,
    client_id       INTEGER REFERENCES clients(id),
    date_commande   TIMESTAMP DEFAULT NOW(),
    statut          VARCHAR(30) DEFAULT 'en_attente',
    montant_total   NUMERIC(14,2) DEFAULT 0,
    adresse_livraison TEXT
);

-- 📄 LIGNES DE COMMANDE
CREATE TABLE lignes_commande (
    id              SERIAL PRIMARY KEY,
    commande_id     INTEGER REFERENCES commandes(id) ON DELETE CASCADE,
    produit_id      INTEGER REFERENCES produits(id),
    quantite        INTEGER NOT NULL CHECK (quantite > 0),
    prix_unitaire   NUMERIC(12,2) NOT NULL,
    sous_total      NUMERIC(14,2) NOT NULL
);

-- 💰 PAIEMENTS
CREATE TABLE paiements (
    id              SERIAL PRIMARY KEY,
    commande_id     INTEGER REFERENCES commandes(id),
    date_paiement   TIMESTAMP DEFAULT NOW(),
    montant         NUMERIC(14,2) NOT NULL,
    methode         VARCHAR(30),
    reference       VARCHAR(100),
    statut          VARCHAR(30) DEFAULT 'valide'
);

-- 📊 INDEX (pour accélérer les requêtes)
CREATE INDEX idx_commandes_client ON commandes(client_id);
CREATE INDEX idx_commandes_date ON commandes(date_commande);
CREATE INDEX idx_lignes_commande ON lignes_commande(commande_id);
CREATE INDEX idx_paiements_commande ON paiements(commande_id);
CREATE INDEX idx_clients_email ON clients(email);

-- ✅ Message de confirmation
\echo 'Schéma créé avec succès !'
