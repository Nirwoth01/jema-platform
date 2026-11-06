# Décision technique — Jema V1

Date : 6 novembre 2026
Statut : retenu

## Pile choisie

- Langage principal : TypeScript, côté interface et serveur.
- Runtime : Node.js, avec une version LTS prise en charge par les dépendances du projet.
- Front-end : Next.js, en PWA responsive pour la première version.
- API : NestJS, organisée en monolithe modulaire et exposée en REST.
- Base de données : PostgreSQL 18.
- Accès aux données : SQL paramétré avec le pilote Node.js pg, dans une couche repository. Les migrations restent des fichiers SQL versionnés.
- Application native : hors périmètre initial ; React Native/TypeScript pourra être étudié après la PWA.

## Raisons

- Une seule langue principale facilite le travail front-end et back-end.
- Les requêtes SQL paramétrées conviennent au schéma conçu et réutilisent les acquis SQL du porteur du projet.
- NestJS donne une structure claire en modules, contrôleurs, services et repositories.
- La PWA permet de commencer sur ordinateur, tablette et téléphone avec un seul front-end.

## Règles de réalisation

- Les requêtes passent par des paramètres SQL, jamais par concaténation de valeurs utilisateur.
- Les montants sont manipulés en décimaux exacts et en devise explicite.
- Les variables et secrets restent dans .env; le dépôt contiendra seulement .env.example.
- Les transactions métier sensibles seront exécutées par le back-end avec commit/rollback.
- Le projet commence comme monolithe modulaire; les microservices ne sont pas nécessaires en V1.

## Harmonisation documentaire

Le document Word d’architecture a été mis à jour en version 0.5 pour refléter Next.js, NestJS, TypeScript, Node.js et PostgreSQL 18. Le back-end inclut la configuration, l’accès SQL, les routes de disponibilité et le premier module de comptes avec sessions sécurisées. La livraison des codes de vérification SMS/e-mail reste à intégrer avant la production.
