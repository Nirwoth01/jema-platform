# Inventaire fonctionnel — Jema V1

## Objectif

Jema est une plateforme de commerce en ligne pour la RDC. Elle réunit une marketplace ouverte, une boutique e-commerce Jema, des ventes confiées à Jema et la recherche de produits à la demande. Le schéma V1 doit permettre de lancer ces parcours sans figer les décisions commerciales encore en discussion.

## Modules fonctionnels

1. **Comptes et accès** — inscription, connexion, récupération du mot de passe, vérification du téléphone ou de l’adresse e-mail, sessions, rôles et permissions.
2. **Profils vendeurs** — boutique, coordonnées, zone d’activité, statut de vérification et destinations Mobile Money vérifiées.
3. **Catalogue et annonces** — catégories, produits, services, variantes, photos, descriptions FR/EN, disponibilité, prix, devise et état de publication.
4. **Recherche** — recherche textuelle, filtres par catégorie, type, zone, vendeur, prix et disponibilité, tri et pagination.
5. **Stock** — quantités disponibles, mouvements traçables, réservations temporaires au checkout, annulation ou expiration des réservations.
6. **Modèles de vente** — annonce libre par un vendeur, vente confiée à Jema, produit appartenant à Jema, recherche de produits pour un client.
7. **Mandats de vente confiée** — vendeur mandant, produits confiés, quantités, prix plancher, conditions et commissions convenues.
8. **Panier et e-commerce** — panier, recalcul du prix au checkout, une commande client et des sous-commandes par vendeur et modèle de vente.
9. **Commandes et exécution** — instantané des prix et conditions acceptés, états d’avancement, livraison par sous-commande, suivi et créneaux de services.
10. **Marchandage** — offres structurées liées à une annonce ou une demande, contre-offres, acceptation, refus, expiration et historique.
11. **Recherche à la demande** — demandes multi-produits, caractéristiques, budget, zone et délai ; devis détaillés de Jema, négociation et conversion en commande.
12. **Mobile Money** — tentatives de paiement M-Pesa, Airtel Money et Orange Money, événements opérateur dédupliqués, rapprochement et historique.
13. **Commissions et reversements** — règles configurables par modèle/catégorie, calcul figé par commande, suivi des sommes dues, paiements vendeurs, échecs et rapprochement.
14. **Remboursements et retours** — demandes de retour, remboursements partiels ou complets, décision, motif, statut et référence opérateur.
15. **Monnaies et taux** — USD et CDF, historique des taux, règle commerciale initiale de Jema de 1 USD = 2 300 CDF et taux figé dans chaque devis/commande.
16. **Messagerie** — conversations directes, conversations liées à une commande ou une demande, support, messages texte et pièces jointes privées.
17. **Groupes d’échange** — groupes publics ou privés, adhésions, rôles de modération, règles, signalements, blocage et départ.
18. **Notifications** — notifications dans l’application et préférences par canal/langue ; l’envoi SMS, e-mail ou push sera réalisé par des adaptateurs du back-end.
19. **Avis et confiance** — avis liés à une ligne de commande terminée, signalements d’utilisateurs, annonces, messages ou groupes et actions de modération.
20. **Support et litiges** — dossiers reliés à un compte, une commande ou une recherche ; assignation à un agent, preuves et suivi de résolution.
21. **Administration** — gestion des rôles, catégories, annonces, zones, règles de commission, taux de change, mandats, paiements, reversements et politiques.
22. **Journalisation financière et audit** — événements de paiement, traces d’approbation, grand livre à débits/crédits équilibrés et journal des actions d’administration.

## Règles métier traduites dans le modèle

- Les annonces des vendeurs sont gratuites ; la publication ne stocke aucun frais d’annonce.
- Le panier peut contenir plusieurs vendeurs. Le checkout crée une commande parent et des sous-commandes financières/logistiques distinctes.
- Le prix, la devise, le taux de change, les frais et l’offre acceptée sont enregistrés comme instantanés ; un changement ultérieur ne réécrit pas une ancienne commande.
- Pour une vente confiée, Jema agit comme vendeur visible et le propriétaire du stock reste identifié séparément. Le prix plancher et le mandat sont conservés.
- Les produits propres de Jema ne génèrent pas de commission vendeur. Les commissions applicables sont calculées par règle configurable ; aucun pourcentage n’est inventé ni activé par défaut.
- Un statut « payé » ne sera posé qu’après confirmation vérifiée de l’opérateur ou rapprochement serveur.
- Les paiements et reversements sont des transactions distinctes. Le modèle de données ne crée pas de portefeuille client retirable.
- Les messages de chat ne changent pas le prix. Seule une offre structurée acceptée peut être reprise dans une commande.
- Les informations sensibles des opérateurs ne sont pas conservées en clair. Les secrets d’API restent côté serveur ; les destinations de paiement doivent être chiffrées par l’application.
- Les contenus privés (documents de vérification, pièces de litige et messages) sont stockés comme fichiers privés avec des métadonnées et des droits d’accès.

## Décisions commerciales à compléter

Les taux de commission, les éventuels frais acheteur, l’arrondi CDF, les frais des opérateurs, le mode de reversement, son déclencheur, les règles d’annulation/retour et la politique de modération des groupes restent configurables ou à trancher avant la mise en production.
