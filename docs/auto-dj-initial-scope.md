# Auto-DJ local

## Scope initial validé

Le premier objectif est de vérifier qu'un Auto-DJ comportemental améliore réellement les
sessions d'écoute avant d'investir dans l'analyse audio.

### Expérience utilisateur

- L'utilisateur démarre explicitement l'Auto-DJ depuis le lecteur courant.
- La première version propose un seul mode, **Équilibré**.
- L'Auto-DJ conserve quelques prochains morceaux dans la file et la complète progressivement.
- Chaque proposition fournit une courte raison basée sur des données réellement disponibles.
- Deux actions légères permettent de guider la session :
  - **Plus comme ça**
  - **Pas pour cette session**
- Un ajout manuel dans la file reste prioritaire.
- Un morceau n'est pas répété dans la même session ; l'Auto-DJ s'arrête proprement
  lorsque tous les candidats disponibles ont été joués.
- L'utilisateur peut arrêter l'Auto-DJ à tout moment.
- L'apprentissage et les données restent sur l'iPhone.
- Une commande permet de réinitialiser l'apprentissage.

### Signaux locaux

La première version distingue et enregistre :

- sélection manuelle d'un morceau ;
- démarrage automatique ;
- fin naturelle ;
- skip rapide ou tardif ;
- réécoute ;
- ajout ou retrait manuel dans la file ;
- ajout ou retrait des favoris ;
- feedback positif ou négatif de l'Auto-DJ.

Le moteur peut utiliser :

- favoris ;
- appartenance aux playlists ;
- artiste, album et genre disponibles ;
- récence ;
- complétions ;
- skips ;
- réécoutes ;
- transitions précédemment réussies.

### Raisons affichables

Une raison ne doit mentionner que des informations connues, par exemple :

- souvent terminé ;
- présent dans la même playlist ;
- transition déjà appréciée ;
- artiste familier ;
- morceau peu écouté récemment.

La première version ne doit pas prétendre connaître l'énergie, le tempo, l'humeur, les voix ou
la proximité sonore d'un fichier.

## Modules et seams testés

### `ListeningHistory`

Interface publique responsable de :

- recevoir des événements d'écoute typés ;
- distinguer fin naturelle, skip et sélection ;
- calculer des agrégats par morceau et par transition ;
- borner l'historique récent ;
- persister, réinitialiser et supprimer les données d'un morceau.

Le lecteur émet les événements mais ne contient aucune logique de recommandation.

### `AutoDJ`

Interface publique responsable de :

- classer une liste de candidats pour une session ;
- éviter répétitions et morceaux trop récents ;
- intégrer les résumés d'écoute, favoris, playlists et métadonnées ;
- retourner le prochain morceau avec des raisons lisibles ;
- rester déterministe pour un même contexte afin de permettre des tests fiables.

La file de lecture conserve la responsabilité de jouer, déplacer et supprimer les morceaux.

## Critères de sortie

### Exactitude

- Une fin naturelle n'est jamais enregistrée comme un skip.
- Les commandes de l'application, de l'écran verrouillé et du casque produisent les mêmes
  catégories d'événements.
- Un morceau ajouté manuellement n'est jamais supprimé ou déplacé silencieusement par l'Auto-DJ.
- La suppression d'un morceau nettoie ses données dérivées.
- La réinitialisation supprime l'apprentissage sans toucher aux morceaux, playlists ou favoris.

### Utilité

Sur l'iPhone réel, comparer l'Auto-DJ au shuffle avec :

- taux de skip dans les 20 premières secondes ;
- morceaux retirés de la file ;
- taux de complétion ;
- feedback positif et négatif ;
- répétitions d'artiste gênantes.

La phase suivante n'est engagée que si le moteur comportemental produit une amélioration utile ou
si ses limites sont clairement attribuables aux métadonnées manquantes.

## Hors scope initial

- analyse des MP3 ;
- BPM, énergie, humeur ou détection de voix ;
- Core ML ou autre modèle embarqué ;
- serveur, compte ou synchronisation entre appareils ;
- profils Gym, Focus ou Soirée ;
- modes Confort et Découverte ;
- page complète de statistiques ou profil détaillé « Mon DJ » ;
- recommandations collaboratives entre utilisateurs.

## Phases ultérieures

### Phase 2

- ajouter Confort, Équilibré et Découverte ;
- afficher un historique léger des sessions ;
- ajouter la page secondaire « Mon DJ » ;
- permettre de corriger les préférences apprises.

### Phase 3

- prototyper une analyse locale et versionnée après import ;
- mesurer énergie relative, dynamique, brillance et tempo avec confiance ;
- comparer le moteur avec et sans ces caractéristiques sur une bibliothèque réelle.

### Phase 4

- tester un seul modèle d'embeddings musicaux avec Core ML ;
- vérifier licence, conversion, taille, latence, mémoire, énergie et qualité de voisinage ;
- conserver le modèle uniquement s'il apporte un gain clair par rapport aux phases précédentes.

Un backend ne sera envisagé qu'après démonstration d'une limite impossible à résoudre localement.
