# Base de données Jema

## Pré-requis

- PostgreSQL 18 est installé.
- Le serveur PostgreSQL doit apparaître comme connecté dans pgAdmin 4.
- La base cible doit être une base de développement vide nommée jema_dev.

## Pile applicative

TypeScript/Node.js, Next.js pour le front-end, NestJS pour l’API Jema, PostgreSQL 18 et SQL paramétré via le pilote Node.js pg. La décision complète se trouve dans docs/Decision_stack_technique_Jema_V1.md.

## Contenu

Le script 001_initial_schema.sql installe le schéma initial : comptes et rôles, vendeurs, catalogue, stock, mandats, sourcing, panier, commandes multi-vendeurs, paiements, commissions, reversements, grand livre, conversations, groupes, support, modération et audit.

Il initialise les langues français/anglais, les monnaies CDF/USD, le profil marchand technique de Jema et le taux commercial initial de 1 USD = 2 300 CDF. Aucun taux de commission n’est créé : les règles doivent être définies et validées avant d’autoriser des achats.

## Exécution dans pgAdmin

1. Dans l’arbre Servers → PostgreSQL 18 → Databases, crée une base jema_dev si elle n’existe pas.
2. Clique droit sur jema_dev, puis ouvre Query Tool.
3. Ouvre 001_initial_schema.sql depuis C:\Pro_Jema\database.
4. Vérifie que la barre de connexion du Query Tool cible bien jema_dev, puis exécute le script avec F5.
5. Les tables apparaissent sous Schemas → public → Tables après actualisation.

Le script est une migration initiale à exécuter une seule fois dans une base vide. Il ne supprime aucune donnée. Ne l’exécute pas dans une base contenant déjà des tables Jema.

## Règles techniques

- Tous les montants sont en NUMERIC; le taux de change est figé dans chaque ligne de commande.
- Les identifiants sont des UUID et les dates sont enregistrées en UTC.
- Les mots de passe doivent être hachés par l’API (Argon2id ou bcrypt). Le hash, et jamais le mot de passe, est conservé.
- Les secrets d’API Mobile Money ne vont ni dans PostgreSQL ni dans le dépôt de code.
- Le numéro du compte de reversement est prévu pour être chiffré côté application et stocké en binaire chiffré.
- La base ne constitue pas un portefeuille client retirable.
- Les transactions, vérifications de permissions, idempotence des webhooks, calcul de commissions et rapprochement seront implémentés et contrôlés dans les services back-end.

## Décisions encore nécessaires

Taux de commission par modèle/catégorie, frais éventuels de l’acheteur, règles d’arrondi, déclencheur de reversement, politiques de retour et configuration des comptes marchands des opérateurs.
