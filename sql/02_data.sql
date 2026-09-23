-- ============================================
-- GÉNÉRATION DE DONNÉES FICTIVES (v2 - robuste)
-- ============================================

-- 🧹 Nettoyage complet
TRUNCATE lignes_commande, paiements, commandes, stocks, produits, clients RESTART IDENTITY CASCADE;

-- 👥 5000 CLIENTS
INSERT INTO clients (nom, prenom, email, telephone, adresse, ville)
SELECT
    'Nom' || i,
    'Prenom' || i,
    'client' || i || '@example.mg',
    '+26134' || LPAD((i % 10000000)::text, 7, '0'),
    (i * 17) || ' Rue ' || (i % 500),
    (ARRAY['Antananarivo','Toamasina','Antsirabe','Fianarantsoa','Mahajanga','Toliara'])[1 + (i % 6)]
FROM generate_series(1, 5000) AS i;

-- 📦 1000 PRODUITS
INSERT INTO produits (reference, designation, categorie, prix_unitaire)
SELECT
    'REF-' || LPAD(i::text, 6, '0'),
    'Produit ' || i,
    (ARRAY['Informatique','Bureau','Alimentation','Vêtement','Maison','Sport'])[1 + (i % 6)],
    ROUND((RANDOM() * 500000 + 1000)::numeric, 2)
FROM generate_series(1, 1000) AS i;

-- 📊 STOCKS (1 ligne par produit)
INSERT INTO stocks (produit_id, quantite, seuil_alerte)
SELECT id, (RANDOM() * 500)::int, 10
FROM produits;

-- 🧾 20000 COMMANDES
INSERT INTO commandes (client_id, date_commande, statut, montant_total)
SELECT
    1 + (RANDOM() * 4999)::int,
    NOW() - (RANDOM() * INTERVAL '365 days'),
    (ARRAY['en_attente','validee','expediee','livree','annulee'])[1 + (RANDOM() * 4)::int],
    0
FROM generate_series(1, 20000);

-- 📄 LIGNES DE COMMANDE (3 par commande = 60000 lignes)
-- Pour chaque commande, on crée exactement 3 lignes via generate_series
INSERT INTO lignes_commande (commande_id, produit_id, quantite, prix_unitaire, sous_total)
SELECT
    c.id,
    p.id,
    qte,
    p.prix_unitaire,
    qte * p.prix_unitaire
FROM commandes c
CROSS JOIN generate_series(1, 3) AS ligne
CROSS JOIN LATERAL (
    SELECT id, prix_unitaire
    FROM produits
    ORDER BY RANDOM()
    LIMIT 1
) AS p
CROSS JOIN LATERAL (
    SELECT (1 + (RANDOM() * 5)::int) AS qte
) AS q;

-- 💰 PAIEMENTS (1 par commande non annulée)
INSERT INTO paiements (commande_id, montant, methode, reference, statut)
SELECT
    c.id,
    ROUND((RANDOM() * 1000000 + 10000)::numeric, 2),
    (ARRAY['especes','carte','virement','mobile'])[1 + (RANDOM() * 3)::int],
    'PAY-' || LPAD(c.id::text, 8, '0'),
    'valide'
FROM commandes c
WHERE c.statut <> 'annulee';

-- 🔄 Mise à jour du montant_total
UPDATE commandes c
SET montant_total = COALESCE(
    (SELECT SUM(sous_total) FROM lignes_commande WHERE commande_id = c.id),
    0
);

-- ✅ Résumé
\echo '--- RÉSUMÉ ---'
SELECT 'clients'         AS table_name, COUNT(*) AS nb FROM clients
UNION ALL SELECT 'produits',         COUNT(*) FROM produits
UNION ALL SELECT 'stocks',           COUNT(*) FROM stocks
UNION ALL SELECT 'commandes',        COUNT(*) FROM commandes
UNION ALL SELECT 'lignes_commande',  COUNT(*) FROM lignes_commande
UNION ALL SELECT 'paiements',        COUNT(*) FROM paiements;

\echo '--- TAILLE ---'
SELECT pg_size_pretty(pg_database_size('gestion_commerciale')) AS taille;
