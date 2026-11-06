# API Jema

API REST modulaire en TypeScript avec NestJS 12, Node.js et PostgreSQL. La V1 utilise le pilote `pg` et des requêtes SQL paramétrées pour rester proche du schéma PostgreSQL déjà préparé.

## Démarrage local

1. Depuis la racine `C:\Pro_Jema`, copiez `apps/api/.env.example` vers `apps/api/.env`.
2. Dans `apps/api/.env`, remplacez `DATABASE_PASSWORD` par le mot de passe PostgreSQL local. Ce fichier est ignoré par Git.
3. Vérifiez dans pgAdmin que le serveur PostgreSQL 18 et la base `jema_dev` sont accessibles.
4. Depuis la racine du projet, lancez `npm install`, puis `npm run dev:api`.
5. Consultez `http://127.0.0.1:3001/api/v1/health/live` et `http://127.0.0.1:3001/api/v1/health/ready`.

La route `live` indique que le processus HTTP répond. La route `ready` vérifie aussi la connexion PostgreSQL. Les erreurs de configuration font échouer le démarrage avec les noms des variables manquantes, sans afficher leurs valeurs.

## Structure

- `src/config` : validation du fichier d’environnement.
- `src/database` : pool PostgreSQL, accès SQL paramétré et transactions.
- `src/health` : disponibilité HTTP et base de données.
- `src/common` : identifiant de requête et format uniforme des erreurs.

Les premiers modules métier à ajouter sont l’authentification et les comptes, puis le catalogue et les annonces. Les opérations d’achat, de paiement et de versement utiliseront `DatabaseService.transaction`.
