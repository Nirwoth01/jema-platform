# API Jema

API REST modulaire en TypeScript avec NestJS 12, Node.js et PostgreSQL. L’accès aux données utilise le pilote `pg` et des requêtes SQL paramétrées.

## Démarrage local

1. Depuis la racine `C:\Pro_Jema`, copiez `apps/api/.env.example` vers `apps/api/.env`.
2. Dans `apps/api/.env`, remplacez `DATABASE_PASSWORD` par le mot de passe PostgreSQL local.
3. Générez un secret pour les jetons à usage unique et collez-le dans `AUTH_TOKEN_PEPPER` :

   ```powershell
   node -e "console.log(require('node:crypto').randomBytes(32).toString('base64url'))"
   ```

4. Dans pgAdmin, vérifiez que PostgreSQL 18 et la base `jema_dev` sont accessibles.
5. Depuis la racine du projet, lancez `npm install`, puis `npm run dev:api`.
6. Consultez `http://127.0.0.1:3001/api/v1/health/live` et `http://127.0.0.1:3001/api/v1/health/ready`.

Le fichier `.env` est ignoré par Git. Utilisez `127.0.0.1` comme hôte pour le front-end et l’API en développement afin que les cookies de session restent sur le même site.

## Authentification et comptes

Les comptes commencent en état `pending`. L’inscription demande un e-mail ou un numéro au format E.164, un prénom, un mot de passe d’au moins 12 caractères et, facultativement, la langue `fr` ou `en`. Le compte est activé après vérification du code à usage unique; le rôle initial est `buyer`.

| Méthode | Route | Usage |
| --- | --- | --- |
| `GET` | `/api/v1/auth/csrf` | Crée le cookie CSRF et retourne son jeton à envoyer dans `X-CSRF-Token`. |
| `POST` | `/api/v1/auth/register` | Crée un compte en attente et prépare la vérification. |
| `POST` | `/api/v1/auth/verify` | Vérifie le code et ouvre une session. |
| `POST` | `/api/v1/auth/verification/resend` | Prépare un nouveau code de vérification. |
| `POST` | `/api/v1/auth/login` | Ouvre une session pour un compte vérifié. |
| `POST` | `/api/v1/auth/logout` | Révoque la session courante. |
| `POST` | `/api/v1/auth/password/forgot` | Prépare la récupération sans confirmer si le compte existe. |
| `POST` | `/api/v1/auth/password/reset` | Remplace le mot de passe et révoque toutes les sessions. |
| `GET` | `/api/v1/users/me` | Retourne le profil de la session authentifiée. |
| `PATCH` | `/api/v1/users/me` | Modifie le prénom, le nom ou la langue préférée. |

Les requêtes du navigateur doivent utiliser `credentials: 'include'`. Chaque requête qui modifie des données doit inclure le jeton retourné par `/auth/csrf` dans l’en-tête `X-CSRF-Token`. En production, servir le front-end et l’API sur le même site (par exemple deux sous-domaines de Jema) pour que les cookies `SameSite=Strict` fonctionnent.

Corps des principales requêtes :

```json
POST /api/v1/auth/register
{
  "firstName": "Amina",
  "email": "amina@example.cd",
  "password": "une phrase secrète longue",
  "preferredLanguageCode": "fr"
}
```

Un compte peut aussi utiliser `phoneE164: "+243…"` à la place de l’e-mail. Le code est vérifié avec `POST /api/v1/auth/verify` et `{ "identifier": "amina@example.cd", "code": "123456" }`. La connexion utilise `POST /api/v1/auth/login` avec `{ "identifier": "…", "password": "…" }`.

Les mots de passe sont hachés avec Argon2id. Le navigateur reçoit une session opaque dans un cookie `HttpOnly`, `SameSite=Strict`; seul le hash du jeton de session est stocké en base. Les cookies sont `Secure` et préfixés `__Host-` en production. Les codes et jetons de vérification sont stockés sous forme de HMAC avec `AUTH_TOKEN_PEPPER`, limités dans le temps et à cinq essais pour une vérification de compte.

### Livraison des codes

Les fournisseurs SMS et e-mail ne sont pas encore intégrés. En local, `AUTH_EXPOSE_DEV_CODES=true` retourne le code de vérification ou de récupération dans la réponse API pour permettre le développement; cette option est acceptée uniquement avec `NODE_ENV=development` et un hôte loopback. En production, l’API refuse les parcours qui nécessitent l’envoi d’un code tant qu’un adaptateur de livraison n’est pas configuré. Ne pas activer l’exposition des codes sur un serveur accessible au public.

Les routes `/api/v1/auth/*` sont limitées à 20 requêtes par adresse IP sur 15 minutes, en plus de la limite générale de l’API.

## Structure

- `src/config` : validation des variables d’environnement.
- `src/database` : pool PostgreSQL, accès SQL paramétré et transactions.
- `src/auth` : inscription, vérification, sessions, connexion et récupération.
- `src/users` : lecture et modification du profil courant.
- `src/common/security` : cookies, contrôle CSRF et garde de session.
- `src/health` : disponibilité HTTP et base de données.

Les intégrations SMS/e-mail sont requises avant l’ouverture des inscriptions en production. Les modules catalogue, commandes, commissions, échanges et paiements viendront ensuite.
