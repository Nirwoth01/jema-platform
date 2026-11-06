# Jema

**Marketplace et plateforme e-commerce conçues pour la République démocratique du Congo.** Jema réunit vendeurs, clients et équipe Jema dans un même espace pour publier, rechercher, négocier, acheter et vendre des biens et des services.

> **État du projet :** développement initial. Le schéma PostgreSQL V1 et le socle de l’API sont en place. Les modules métier et les intégrations de paiement restent à construire.

## Vision produit

Jema prévoit quatre parcours commerciaux :

1. **Marketplace libre :** les vendeurs publient gratuitement. Une commission Jema est prélevée à la vente, selon un taux qui reste à configurer.
2. **Vente confiée à Jema :** un vendeur mandate Jema pour commercialiser ses produits. Après la vente, Jema calcule le montant net du vendeur et le reverse selon le mandat.
3. **Boutique Jema :** Jema propose ses propres produits dans le catalogue e-commerce.
4. **Recherche à la demande :** un client demande un ou plusieurs produits; Jema les recherche, prépare un devis avec sa commission, puis peut négocier le prix avec le client.

La plateforme prend également en charge les biens, les services, les paniers et commandes e-commerce, le marchandage, les conversations privées entre utilisateurs ou avec Jema, ainsi que des groupes d’échange.

## Paramètres de départ

- **Zone :** RDC entière, avec une activation progressive des vendeurs et services.
- **Langues :** français par défaut, anglais en deuxième langue.
- **Devises :** franc congolais (CDF) et dollar américain (USD).
- **Taux commercial initial :** 1 USD = 2 300 CDF. Il s’agit d’un taux de tarification Jema, pas d’une affirmation sur le taux officiel du marché.
- **Paiements ciblés :** M-Pesa, Airtel Money et Orange Money. Les intégrations réelles ne sont pas encore activées.
- **Commissions :** aucune grille de commission n’est activée par défaut. Les taux et règles doivent être décidés avant les ventes réelles.

## Architecture technique

- **Application web prévue :** Next.js et TypeScript, sous forme de PWA responsive.
- **API :** NestJS et TypeScript sur Node.js, en monolithe modulaire.
- **Données :** PostgreSQL 18 avec SQL versionné et requêtes paramétrées via le pilote `pg`.
- **Opérations sensibles :** transactions PostgreSQL pour les changements financiers et de stock.
- **Stockage de secrets :** variables locales dans `apps/api/.env`; ne jamais publier ce fichier ni des données de paiement.

Voir le [document d’architecture](docs/Architecture_Jema_RDC.docx), la [décision technique](docs/Decision_stack_technique_Jema_V1.md) et l’[inventaire fonctionnel](docs/Inventaire_fonctionnel_Jema_V1.md).

## Structure du dépôt

```text
apps/api/       API NestJS (configuration, PostgreSQL, disponibilité)
database/       schéma initial et documentation de base
docs/           architecture, décisions et exigences produit
```

Le détail de l’installation est dans le [guide de l’API](apps/api/README.md) et le [guide de base de données](database/README.md).

## Démarrage local

Prérequis : Node.js 26 (version indiquée par `.nvmrc`) et PostgreSQL 18. NestJS 12 prend en charge les versions Node.js documentées par le projet NestJS.

1. Installe les dépendances depuis la racine du dépôt :

   ```powershell
   npm ci
   ```

2. Dans pgAdmin, crée une base vide nommée `jema_dev`, puis exécute `database/001_initial_schema.sql` une seule fois dans cette base. Le fichier `database/README.md` explique aussi l’exécution avec `psql`.
3. Crée le fichier local de configuration et renseigne le mot de passe PostgreSQL :

   ```powershell
   Copy-Item apps/api/.env.example apps/api/.env
   ```

4. Lance l’API :

   ```powershell
   npm run dev:api
   ```

Routes de disponibilité :

- `GET http://127.0.0.1:3001/api/v1/health/live`
- `GET http://127.0.0.1:3001/api/v1/health/ready` — vérifie aussi PostgreSQL.

Pour compiler l’API : `npm run build:api`.

## Paiements et responsabilités

Les tables et l’architecture préparent le suivi des paiements, commissions, remboursements, événements opérateur, écritures comptables et reversements. Aucun secret opérateur ni traitement de paiement réel n’est inclus à ce stade. Avant une mise en production, les flux d’encaissement et de reversement devront être validés avec les opérateurs ou un partenaire de paiement adapté au modèle retenu.

## Contribution

Le dépôt est privé pendant le développement. Consulte [CONTRIBUTING.md](CONTRIBUTING.md) avant de modifier le schéma ou d’ajouter un module.
