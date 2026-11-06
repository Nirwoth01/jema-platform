# Contribuer à Jema

Jema est en développement initial. Garder les changements petits et rattachés à un module produit ou technique.

## Règles de travail

- Utiliser TypeScript côté interface et API; conserver PostgreSQL comme source de vérité métier.
- Structurer l’API en modules NestJS, avec séparation des contrôleurs, services et accès aux données.
- Utiliser des paramètres SQL pour toutes les valeurs provenant d’une requête.
- Ajouter une nouvelle migration SQL pour une évolution du schéma. Ne pas modifier une migration déjà appliquée dans un environnement partagé.
- Placer les secrets dans un fichier `.env` local. Seul `.env.example`, sans secret réel, peut être versionné.
- Ne pas ajouter de données réelles de clients, vendeurs, paiements ou pièces d’identité au dépôt.
- Pour une modification de flux financier ou de stock, expliquer la transaction SQL et les effets d’un échec ou d’une reprise.

## Vérification disponible

Depuis la racine du dépôt, lancer la compilation TypeScript de l’API :

```powershell
npm run build:api
```

Ajouter les tests automatisés avec les prochains modules métier et couvrir en priorité les autorisations, les transitions d’état et les opérations financières sensibles.
