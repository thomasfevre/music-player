# Auto-DJ personnalisé sur iPhone

## Faisabilité technique et recommandation pour SunoPlayer

Date de recherche : 25 juillet 2026  
Périmètre : application iOS SwiftUI locale, cible minimale iOS 17  
Sources : documentation Apple et documentation officielle des projets cités

## Résumé exécutif

Un Auto-DJ personnalisé, local et crédible est faisable dans SunoPlayer. Il ne faut toutefois pas commencer par un modèle audio.

La meilleure trajectoire est :

1. construire un moteur déterministe à partir des métadonnées et de vrais signaux d’écoute locaux ;
2. mesurer s’il améliore réellement les enchaînements ;
3. ajouter une analyse audio locale légère, exécutée une seule fois par fichier, pour les morceaux mal renseignés ;
4. n’envisager des embeddings ou un backend qu’après un test comparatif sur une bibliothèque réelle.

Le niveau 1 est à la fois le plus simple, le plus explicable et le plus important. Il apporte la personnalisation que les frameworks audio seuls ne peuvent pas fournir. Le niveau 2 peut ensuite améliorer la cohérence sonore. Le niveau 3 est techniquement possible, mais ajoute des risques de conversion de modèle, de taille, de licence et, dans le cas d’un backend, de confidentialité et d’exploitation.

Verdict :

| Niveau | Faisabilité | Risque principal | Recommandation |
|---|---:|---|---|
| 1. Score déterministe local | Élevée | mauvaise définition des signaux d’écoute | À construire en premier |
| 2A. DSP local Apple seulement | Élevée pour énergie et caractéristiques bas niveau, moyenne pour le tempo | qualité variable selon les styles | À prototyper après le niveau 1 |
| 2B. Modèle audio embarqué | Moyenne | licence, conversion et validation | Spike limité avant toute intégration produit |
| 3A. Embeddings et similarité entièrement locaux | Moyenne | modèle crédible et coût d’analyse | Seulement si le DSP apporte un gain insuffisant |
| 3B. Recommandation par backend | Élevée techniquement, faible cohérence produit actuelle | confidentialité, coûts et dépendance réseau | À éviter tant qu’un besoin mesuré ne le justifie pas |

## 1. Point de départ dans le code actuel

L’architecture existante est une bonne base, mais elle ne contient pas encore les données nécessaires à une personnalisation réelle.

### Ce qui existe déjà

- `Track.swift` stocke un identifiant stable, le titre, l’artiste, l’album, le genre, la durée, la date d’import et une version de scan des métadonnées.
- `MusicLibraryManager.swift` copie les fichiers dans le conteneur de l’application, extrait les métadonnées avec `AVURLAsset`, persiste la bibliothèque en JSON et stocke les favoris localement.
- `Playlist.swift` possède déjà des règles déterministes pour l’artiste, l’album, le genre, les favoris et les ajouts récents.
- `AudioPlayerManager.swift` expose la lecture, la file, le morceau courant, la position, la fin de lecture et les commandes distantes.
- `PlaybackQueue.swift` sait mélanger, avancer, reculer et insérer des morceaux dans la file.
- `PRIVACY.md` promet actuellement zéro collecte, zéro réseau et un traitement local.

### Ce qui manque

- aucun historique d’écoute ;
- aucune distinction entre un morceau chargé, réellement écouté, terminé ou ignoré rapidement ;
- aucun compteur de répétition ou de réécoute ;
- aucune provenance de lecture, par exemple playlist, bibliothèque, recherche ou Auto-DJ ;
- aucune caractéristique audio comme BPM, énergie, voix ou embedding ;
- aucun score de recommandation ni explication de ce score.

La position sauvegardée dans `AudioPlayerManager` permet de reprendre un morceau, mais elle ne constitue pas un historique d’écoute. Un Auto-DJ ne doit surtout pas compter une lecture dès qu’un `AVPlayerItem` est créé.

## 2. Niveau 1 : recommandation déterministe locale

### Verdict

Faisabilité élevée. C’est le socle produit recommandé.

Ce niveau ne demande ni SoundAnalysis, ni Core ML, ni serveur. Il exploite les informations déjà présentes et ajoute une instrumentation locale légère.

### Données à ajouter

Deux couches suffisent :

```swift
struct ListeningEvent: Codable {
    let trackID: UUID
    let startedAt: Date
    let listenedSeconds: TimeInterval
    let completed: Bool
    let skippedEarly: Bool
    let source: PlaybackSource
}

struct TrackListeningSummary: Codable {
    let trackID: UUID
    var playCount: Int
    var completionCount: Int
    var earlySkipCount: Int
    var replayCount: Int
    var totalListenedSeconds: TimeInterval
    var lastPlayedAt: Date?
}
```

Il faut conserver des agrégats par morceau et seulement une fenêtre bornée d’événements récents. Un journal JSON illimité finirait par devenir coûteux à réécrire. Pour une première version, un fichier d’agrégats et un petit journal circulaire sont suffisants. SQLite ou SwiftData peuvent devenir utiles plus tard, mais ne sont pas requis pour prouver le concept.

### Définitions à rendre explicites

Les règles suivantes doivent être décidées avant de coder :

- une lecture est-elle comptée après 30 secondes, après 50 % du morceau, ou selon le minimum des deux ?
- un skip est-il « précoce » avant 10 secondes, avant 20 % du morceau, ou les deux ?
- une recherche manuelle dans un morceau invalide-t-elle le signal de complétion ?
- une réécoute immédiate est-elle plus forte qu’une lecture répétée plusieurs jours plus tard ?
- les commandes de l’écran verrouillé et du casque produisent-elles exactement les mêmes événements que l’interface de l’application ?

### Score de départ

Un score déterministe peut combiner :

```text
score =
  proximité de genre, artiste et album
  + préférence issue des favoris
  + taux de complétion
  + signal de réécoute
  + nouveauté contrôlée
  + cohérence avec les derniers morceaux de la session
  - skips précoces
  - répétition récente du même artiste
  - morceau joué trop récemment
```

Les modes du prototype peuvent uniquement modifier les poids :

- **Comfort** favorise les favoris, les artistes connus et les morceaux souvent terminés ;
- **Balanced** équilibre familiarité, variété et cohérence de session ;
- **Discovery** augmente la nouveauté, sans recommander les morceaux souvent ignorés.

Un départage stable par UUID ou par hachage du nom de fichier rend les tests reproductibles. Le moteur doit retourner à la fois le morceau choisi et deux ou trois raisons lisibles. Ces raisons peuvent alimenter directement l’explication prévue dans l’option C2.

### Pourquoi ce niveau reste indispensable même avec un modèle

Un modèle audio peut dire que deux morceaux se ressemblent. Il ne sait pas, à lui seul, que l’utilisateur :

- termine souvent un artiste ;
- ignore un autre style le matin ;
- souhaite éviter deux morceaux du même album à la suite ;
- veut plus de découverte aujourd’hui ;
- vient de retirer un morceau de la file.

La personnalisation vient donc du moteur de politique et des signaux d’écoute. Le modèle audio n’est qu’une source de caractéristiques supplémentaire.

## 3. Niveau 2 : analyse audio locale à l’import

### 3.1 Décoder le signal

AVFoundation fournit les briques nécessaires pour lire les fichiers locaux sous forme PCM :

- `AVAudioFile` lit les fichiers au moyen de `AVAudioPCMBuffer`, de façon séquentielle ou à une position donnée avec `framePosition` ([Apple, AVAudioFile](https://developer.apple.com/documentation/avfaudio/avaudiofile)).
- `AVAssetReaderTrackOutput` peut convertir une piste audio stockée en sortie PCM linéaire non compressée ([Apple, AVAssetReaderTrackOutput](https://developer.apple.com/documentation/avfoundation/avassetreadertrackoutput)).
- `AVAudioPCMBuffer` donne accès aux échantillons flottants ou entiers nécessaires au calcul ([Apple, AVAudioPCMBuffer](https://developer.apple.com/documentation/avfaudio/avaudiopcmbuffer)).

SunoPlayer utilise déjà `AVURLAsset` pour les métadonnées. L’analyse pourrait être déclenchée après la copie et l’extraction de ces métadonnées, mais elle doit quitter le `MainActor` et avoir sa propre file de travail.

### 3.2 Ce qu’Accelerate permet

Le framework Accelerate fournit du calcul vectorisé optimisé pour la performance et l’énergie sur CPU. Sa bibliothèque vDSP comprend FFT, convolution, corrélation, filtrage et réductions comme moyenne ou maximum ([Apple, Accelerate](https://developer.apple.com/documentation/accelerate), [Apple, vDSP](https://developer.apple.com/documentation/accelerate/vdsp-library)).

Avec AVFoundation et vDSP, SunoPlayer peut calculer sans dépendance externe :

- RMS ou une approximation d’intensité moyenne ;
- crête et plage dynamique approximative ;
- centroid spectral, roll-off et flux spectral ;
- densité des attaques ;
- enveloppe d’onsets ;
- tempo estimé par autocorrélation de l’enveloppe ;
- indicateurs de stabilité du tempo.

Ces mesures peuvent produire une notion utile d’« énergie » relative à la bibliothèque personnelle et aider à éviter un passage brutal entre deux morceaux.

### Limite importante

Accelerate fournit les opérations mathématiques, pas l’interprétation musicale. Il n’existe pas dans vDSP de fonction prête à l’emploi pour « humeur », « présence de voix », « danceability » ou « recommande le prochain morceau ». La documentation officielle expose des primitives de signal, pas ces attributs musicaux. Cette conclusion est une inférence à partir de la surface d’API documentée.

Une estimation de BPM artisanale doit être validée par style. Les morceaux ambient, les rythmes syncopés, le demi-temps et le double-temps produisent fréquemment des ambiguïtés. Le résultat doit donc stocker un niveau de confiance et rester optionnel dans le score.

### 3.3 Ce que SoundAnalysis apporte, et ce qu’il n’apporte pas

SoundAnalysis sait analyser un fichier avec `SNAudioFileAnalyzer` et exécuter soit le classifieur Apple, soit un modèle Core ML personnalisé ([Apple, classification d’un fichier audio](https://developer.apple.com/documentation/soundanalysis/classifying-sounds-in-an-audio-file)). Le classifieur intégré reconnaît plus de 300 sons génériques, par exemple rire ou applaudissements ([Apple, SoundAnalysis](https://developer.apple.com/documentation/soundanalysis)).

Il ne constitue pas une API d’analyse musicale comparable à Spotify Audio Features. La documentation ne propose pas de sortie BPM, énergie continue, valence, humeur, embedding musical ou recommandation.

Create ML peut entraîner un `MLSoundClassifier`, mais il faut fournir un jeu de données étiqueté. Apple recommande au moins dix exemples par catégorie et une classe négative, et rappelle qu’un classifieur renvoie toujours une des classes apprises ([Apple, MLSoundClassifier](https://developer.apple.com/documentation/createml/mlsoundclassifier/)).

Conséquences :

- SoundAnalysis est une bonne plomberie d’inférence sur fichier ;
- Create ML est pertinent si SunoPlayer possède un jeu de musique légalement utilisable et correctement annoté ;
- ni l’un ni l’autre ne fournit gratuitement un modèle fiable pour BPM, humeur, voix ou similarité musicale ;
- une classification « énergique / calme » entraînée sur quelques morceaux personnels serait trop fragile pour une fonctionnalité App Store.

### 3.4 Modèle de données conseillé

Ne pas ajouter tous les résultats directement dans `Track`. Il vaut mieux persister un enregistrement séparé, versionné et recalculable :

```swift
struct TrackAudioFeatures: Codable {
    let trackID: UUID
    let analyzerVersion: Int
    let analyzedAt: Date
    let status: AnalysisStatus

    var tempoBPM: Float?
    var tempoConfidence: Float?
    var energy: Float?
    var dynamicRange: Float?
    var spectralBrightness: Float?
    var vocalProbability: Float?
    var moodScores: [String: Float]?
    var embedding: [Float]?
}
```

La persistance séparée offre quatre avantages :

- les migrations de `Track` restent simples ;
- une nouvelle version de l’analyse peut recalculer les seuls morceaux obsolètes ;
- un échec n’empêche pas l’import du fichier ;
- les données dérivées peuvent être effacées et reconstruites.

Chaque travail doit être `pending`, `running`, `completed` ou `failed`, et reprendre après interruption. La suppression d’un morceau doit également supprimer ses caractéristiques et son historique.

## 4. Niveau 3 : similarité avancée

### 4.1 Modèle embarqué et recherche locale

Core ML est adapté à l’inférence sur appareil. Apple indique que le framework peut employer CPU, GPU et Neural Engine, et que l’exécution strictement locale évite une dépendance réseau et aide à préserver la confidentialité ([Apple, Core ML](https://developer.apple.com/documentation/coreml/)).

Une architecture possible :

1. décoder et normaliser un ou plusieurs extraits du morceau ;
2. générer un embedding musical avec un modèle Core ML ;
3. agréger les embeddings des fenêtres en un vecteur par morceau ;
4. calculer la similarité cosinus entre le morceau courant et les candidats ;
5. fournir cette similarité au score déterministe du niveau 1 ;
6. appliquer ensuite les contraintes de variété, récence, skips et mode de découverte.

Pour une bibliothèque personnelle de quelques milliers de morceaux, une recherche exhaustive en mémoire est probablement suffisante. Il n’est pas nécessaire d’intégrer immédiatement un index vectoriel complexe. Cette hypothèse doit être vérifiée avec la taille réelle maximale de bibliothèque.

### Empreinte de stockage

Le modèle Discogs-EffNet officiel d’Essentia produit un embedding de 1 280 valeurs flottantes par fenêtre ([métadonnées officielles du modèle](https://essentia.upf.edu/models/feature-extractors/discogs-effnet/discogs-effnet-bs64-1.json)). Un seul vecteur `Float32` agrégé représente environ 5 Kio par morceau, soit environ 4,9 Mio pour 1 000 morceaux et 48,8 Mio pour 10 000. `Float16` divise ce stockage par deux, sous réserve d’un test de qualité de voisinage.

Le poids du modèle source Discogs-EffNet est d’environ 18 Mo dans les formats TensorFlow ou ONNX publiés par Essentia ([index officiel des poids](https://essentia.upf.edu/models/feature-extractors/discogs-effnet/)). La taille finale Core ML peut différer après conversion et compression.

### 4.2 Essentia comme référence technique

Essentia est une bibliothèque C++ reconnue de music information retrieval. Elle propose des descripteurs spectraux, tonals, rythmiques, BPM, danceability, ainsi que des modèles de classification et d’embeddings. Son support iOS est indiqué comme partiel ([documentation officielle Essentia](https://essentia.upf.edu/documentation.html)).

Exemples pertinents :

- `RhythmExtractor2013` retourne BPM, positions des battements et confiance, avec une entrée à 44,1 kHz ([référence officielle](https://essentia.upf.edu/reference/std_RhythmExtractor2013.html)) ;
- Discogs-EffNet vise 400 styles et expose des embeddings de 1 280 dimensions ;
- des variantes contrastives ont été entraînées pour rapprocher artiste, label, sortie ou morceau ;
- une tête officielle MTG-Jamendo produit 56 étiquettes de mood et thème comme `calm`, `energetic`, `happy` ou `sad`, mais son PR-AUC de test publié est 0,14 et son ROC-AUC 0,76 ([métadonnées officielles mood/theme](https://essentia.upf.edu/models/classification-heads/mtg_jamendo_moodtheme/mtg_jamendo_moodtheme-discogs_multi_embeddings-effnet-1.json)) ;
- Essentia publie également des classifieurs `voice_instrumental`, `danceability` et plusieurs humeurs ([catalogue officiel des modèles](https://essentia.upf.edu/models.html)).

Ces modèles rendent le niveau 3 crédible pour un prototype. Ils ne rendent pas leur intégration produit automatique.

### Blocage de licence

Essentia est proposée sous AGPLv3 pour les applications non commerciales et sous licence propriétaire sur demande. Sa page de licence indique aussi que ses modèles préentraînés sont réservés à un usage non commercial sous CC BY-NC-ND 4.0, avec licence propriétaire disponible sur demande. Elle demande enfin un audit des dépendances GPL et LGPL, et cite FFTW, FFmpeg et d’autres composants ([licence officielle Essentia](https://essentia.upf.edu/licensing_information.html)).

Pour une application fermée distribuée sur l’App Store, Essentia et ses modèles ne doivent donc pas être intégrés sans :

1. confirmation écrite de la licence du modèle exact ;
2. licence commerciale ou stratégie de conformité validée juridiquement ;
3. audit de toutes les dépendances réellement liées ;
4. vérification des obligations d’attribution et de redistribution.

Le site des modèles et la page de licence ont déjà présenté des libellés Creative Commons différents selon les versions. Il faut considérer la licence attachée au fichier exact comme l’autorité, pas une supposition générale.

Une alternative plus sûre consiste à réimplémenter uniquement les caractéristiques DSP nécessaires avec AVFoundation et Accelerate. Cela évite l’AGPL, mais ne permet pas de recopier le code d’Essentia.

### Risque de conversion vers Core ML

Core ML Tools convertit des modèles TensorFlow ou PyTorch, mais une conversion réussie n’est pas une preuve d’équivalence. Il faut vérifier :

- les opérations non supportées ;
- les formes dynamiques ou les lots fixes ;
- la reproduction exacte du prétraitement audio ;
- l’écart numérique entre modèle source et modèle converti ;
- la latence, la mémoire et l’énergie sur les plus anciens iPhone pris en charge.

Apple recommande actuellement le chemin stable `torch.jit.trace` pour PyTorch. Le chemin `torch.export` de Core ML Tools 8 est indiqué en bêta avec environ 70 % de couverture des opérations, et le support de `torch.jit.script` reste limité ([Apple, workflow de conversion PyTorch](https://apple.github.io/coremltools/docs-guides/source/convert-pytorch-workflow.html)). Apple documente aussi des erreurs d’opérations non supportées et des écarts numériques possibles ([Apple, FAQ Core ML Tools](https://apple.github.io/coremltools/docs-guides/source/faqs.html)).

Le modèle Discogs-EffNet publié par Essentia possède des variantes à lot fixe de 64 et une variante ONNX dynamique. La documentation précise que le port dynamique vers TensorFlow n’avait pas été possible pour cette distribution ([Essentia, modèles](https://essentia.upf.edu/models.html)). Pour iOS, il faut préférer une entrée à lot 1 ou fixe adaptée, puis refaire les tests de référence.

### 4.3 Backend

Un backend devient utile seulement si l’un des besoins suivants est confirmé :

- modèle trop lourd pour les appareils ciblés ;
- recommandations collaboratives entre utilisateurs ;
- entraînement continu sur une population ;
- catalogue partagé et recherche vectorielle très large ;
- besoin de faire évoluer rapidement le modèle sans nouvelle version de l’application.

Il change néanmoins le produit :

- dépendance réseau et coût d’exploitation ;
- compte utilisateur ou identifiant pseudonyme à gérer ;
- politique de rétention et de suppression ;
- chiffrement en transit et au repos ;
- nouveaux cas de panne ;
- changement du discours de confidentialité.

Pour SunoPlayer, qui lit des fichiers personnels et promet actuellement un fonctionnement entièrement local, un backend est une expansion de périmètre, pas une simple optimisation.

## 5. Exécution en arrière-plan

L’application cible iOS 17. Il faut donc concevoir l’analyse comme un travail interruptible et non comme une opération garantie après chaque import.

Apple précise qu’une application est normalement suspendue en arrière-plan et que les modes disponibles sont limités. Le mode `audio` est destiné à la lecture de contenu audible, tandis que `processing` sert aux tâches planifiées ([Apple, modes d’exécution en arrière-plan](https://developer.apple.com/documentation/xcode/configuring-background-execution-modes)).

`BGProcessingTask` peut exécuter un travail long pendant plusieurs minutes, mais le système peut l’interrompre. Il ne s’exécute que lorsque l’appareil est inactif et peut être terminé lorsque l’utilisateur reprend l’appareil ([Apple, BGProcessingTask](https://developer.apple.com/documentation/backgroundtasks/bgprocessingtask)). Apple indique également que le système choisit le moment de lancement, notamment pour les travaux lourds comme le ML ou la maintenance de base de données ([Apple, stratégies d’arrière-plan](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app)).

Conséquences d’architecture :

- analyser d’abord en avant-plan après l’import, avec progression visible ;
- limiter la concurrence à un fichier à la fois au début ;
- enregistrer un checkpoint entre chaque morceau ;
- annuler proprement à l’expiration ;
- reprendre les éléments `pending` plus tard ;
- éventuellement planifier le reliquat avec `BGProcessingTask` ;
- proposer une option « uniquement quand l’appareil charge » pour une grande bibliothèque ;
- ne pas détourner le mode de lecture audio pour maintenir une analyse silencieuse.

Apple limite aussi l’usage de l’arrière-plan à son objectif déclaré dans la règle 2.5.4 et demande d’éviter une consommation excessive d’énergie dans la règle 2.4.2 ([App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)).

À partir d’iOS 26, `BGContinuedProcessingTask` permet à un travail explicitement lancé par l’utilisateur de continuer avec une progression système visible et annulable. Il peut même accéder au GPU sur les appareils compatibles, mais peut toujours être interrompu ([Apple, WWDC25](https://developer.apple.com/videos/play/wwdc2025/227/)). C’est une amélioration optionnelle pour iOS 26, pas la base d’une application qui supporte iOS 17.

## 6. Performance et stockage

Il n’existe pas de chiffre universel crédible pour le temps d’analyse d’un morceau. Il dépend du codec, de la durée, du modèle, du nombre de fenêtres et du téléphone. Toute estimation produit doit donc venir d’un benchmark sur appareils réels.

### Budget de test recommandé

Tester au minimum :

- plus ancien iPhone officiellement supporté ;
- iPhone médian récent ;
- 100 morceaux représentatifs ;
- MP3 de plusieurs débits, M4A, WAV et tout autre format réellement importé ;
- morceaux courts et longs ;
- analyse pendant lecture et sans lecture ;
- mode économie d’énergie ;
- appareil chaud et froid ;
- import initial de 10, 100 et 1 000 morceaux.

Mesures :

- temps réel par minute d’audio ;
- mémoire maximale ;
- variation de batterie ;
- état thermique ;
- taille du cache ;
- taux d’échec ;
- impact sur lecture, recherche et défilement ;
- délai avant première recommandation utile.

### Stratégie de fenêtres

Une analyse complète donne davantage de signal pour le tempo, mais coûte plus cher. Une analyse par extraits peut suffire pour énergie, voix, humeur ou embedding.

Le prototype doit comparer :

- fichier complet ;
- trois fenêtres, par exemple début utile, milieu et fin ;
- une seule fenêtre de 30 secondes ;
- agrégation moyenne et médiane ;
- exclusion du silence d’introduction.

Le choix doit être fait sur la qualité de recommandation et non uniquement sur le temps d’inférence.

## 7. Confidentialité et App Store

Apple définit la « collecte » comme une transmission hors appareil accessible au développeur ou à un tiers au-delà du traitement temps réel. Apple précise que des données traitées uniquement sur l’appareil ne sont pas considérées comme collectées pour la fiche de confidentialité ([Apple, App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)).

### Niveaux 1 et 2 entièrement locaux

Ils peuvent rester cohérents avec la déclaration actuelle de non-collecte, à condition qu’aucun SDK ne transmette les événements ou les caractéristiques. La politique de confidentialité doit néanmoins expliquer clairement :

- que l’historique d’écoute local personnalise l’Auto-DJ ;
- que les fichiers sont analysés localement ;
- que l’audio ne quitte pas l’appareil ;
- comment réinitialiser les préférences et supprimer les données dérivées.

Même si la fiche App Store n’exige pas de déclarer un traitement strictement local, la transparence dans l’application reste souhaitable.

### Backend

Si SunoPlayer transmet de l’audio, des extraits, des empreintes, des embeddings, des métadonnées ou l’historique d’écoute, la promesse actuelle devient fausse. Apple classe explicitement les données d’écoute musicale dans `Product Interaction` et les recommandations personnalisées dans `Product Personalization` ([Apple, App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)).

Il faudrait alors :

- mettre à jour App Store Connect ;
- obtenir un consentement clair avant envoi ;
- minimiser les données ;
- documenter rétention et suppression ;
- auditer chaque prestataire et SDK ;
- permettre un usage local ou une désactivation si le produit le promet ;
- réviser `PRIVACY.md`.

### Modèles téléchargés

Core ML documente le téléchargement et la compilation de modèles sur l’appareil. Toutefois, la règle App Store 2.5.2 interdit de télécharger ou exécuter du code qui introduit ou change les fonctionnalités ([Apple, Core ML](https://developer.apple.com/documentation/coreml/), [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)).

Un modèle doit donc être traité comme une ressource de données pour une fonctionnalité déjà examinée, avec un comportement produit borné. Un remplacement distant qui ajouterait de nouveaux types de fonctionnalités augmenterait le risque de revue. Pour une première version, embarquer le modèle validé est plus simple.

## 8. Architecture recommandée

```text
AudioPlayerManager
    publie des événements réels de session
            |
            v
ListeningHistoryStore
    agrégats par morceau + événements récents bornés
            |
            v
RecommendationEngine
    candidats + score + raisons + contraintes
      ^                         |
      |                         v
TrackAudioFeatureStore     PlaybackQueue
      ^
      |
AudioAnalysisService
    AVFoundation -> Accelerate -> Core ML optionnel
```

### Responsabilités

`ListeningHistoryStore`

- reçoit les mêmes événements depuis l’interface, les commandes distantes et la fin automatique ;
- calcule les agrégats ;
- ne dépend pas de SwiftUI ;
- permet une suppression complète.

`RecommendationEngine`

- fonction pure ou acteur isolé ;
- prend une session, des candidats, des résumés d’écoute et des caractéristiques optionnelles ;
- retourne un classement stable et des raisons ;
- fonctionne même si aucune analyse audio n’est disponible.

`AudioAnalysisService`

- décode hors du thread principal ;
- limite la concurrence ;
- est annulable et reprenable ;
- versionne son schéma et son algorithme ;
- ne bloque jamais l’import ou la lecture.

`TrackAudioFeatureStore`

- indexé par `Track.id` ;
- stocke état, version et résultats dérivés ;
- sait invalider une ancienne version ;
- supprime les données orphelines.

`AutoDJSession`

- conserve le morceau de départ, le mode, les morceaux récents et une graine de départage ;
- demande quelques candidats à l’avance, pas toute une playlist définitive ;
- insère via les opérations de file existantes ;
- respecte toute modification manuelle de l’utilisateur.

### Gardes produit

- ne jamais supprimer ou réordonner silencieusement les ajouts manuels ;
- ne pas recommander le même morceau dans une fenêtre récente ;
- limiter les répétitions d’artiste et d’album ;
- donner priorité à un « jouer ensuite » manuel ;
- afficher pourquoi un morceau a été choisi ;
- permettre « moins comme ça », « plus comme ça » ou une action équivalente ;
- pouvoir désactiver l’apprentissage local et réinitialiser ses données.

## 9. Plan par phases

### Phase 0 : instrumentation fiable

Objectif : produire des événements d’écoute justes.

- définir lecture, complétion, skip précoce et réécoute ;
- centraliser les événements de l’écran, du casque, de l’écran verrouillé et de la fin automatique ;
- stocker agrégats et historique borné ;
- ajouter export ou écran de diagnostic local pour vérifier les données.

Critère de sortie : sur un scénario manuel connu, les compteurs correspondent exactement aux actions effectuées.

### Phase 1 : Auto-DJ déterministe

Objectif : livrer une valeur utilisateur sans analyse audio.

- générer les candidats à partir de la bibliothèque ;
- ajouter Comfort, Balanced et Discovery ;
- expliquer chaque choix ;
- appliquer contraintes de récence et répétition ;
- comparer Auto-DJ à un shuffle aléatoire.

Critère de sortie : baisse mesurable des skips précoces face au shuffle, sans hausse des répétitions gênantes.

### Phase 2 : DSP Apple local

Objectif : améliorer les transitions lorsque les métadonnées sont faibles.

- extraire énergie relative, dynamique, brillance et tempo avec confiance ;
- analyser en tâche interruptible et versionnée ;
- tester fichier complet contre fenêtres ;
- intégrer chaque caractéristique séparément dans le score.

Critère de sortie : chaque caractéristique doit améliorer une métrique ou une évaluation humaine. Sinon, elle reste hors production.

### Phase 3 : spike modèle embarqué

Objectif : vérifier la valeur des embeddings et des attributs sémantiques.

- sélectionner un seul modèle avec licence exploitable ;
- reproduire exactement son prétraitement ;
- convertir en Core ML ;
- comparer les sorties source et Core ML ;
- mesurer taille, latence, mémoire, énergie et qualité de voisins ;
- tester modèle seul, DSP seul et combinaison.

Critère de sortie : gain clair par rapport à la phase 2, licence confirmée et budget appareil acceptable.

### Phase 4 : décision backend

Objectif : ne créer un service que si les limites locales sont prouvées.

- documenter le besoin impossible ou insuffisant sur appareil ;
- faire une analyse de menace et de confidentialité ;
- définir consentement, rétention, suppression et coût ;
- maintenir une expérience locale de repli si elle fait partie de la promesse produit.

## 10. Méthode d’évaluation

Une recommandation « correcte » est subjective. Il faut donc mesurer plusieurs signaux.

### Métriques comportementales locales

- taux de skip dans les 10, 20 et 30 premières secondes ;
- taux de complétion ;
- morceaux retirés manuellement de la file ;
- morceaux rejoués ;
- ajout en favoris après recommandation ;
- durée de session ;
- diversité d’artistes et de genres ;
- répétition du même artiste dans une fenêtre de cinq morceaux.

### Évaluation hors ligne

Créer un petit corpus personnel de transitions notées :

- bonne transition ;
- acceptable ;
- mauvaise ;
- raison éventuelle, par exemple énergie, style, voix ou répétition.

Comparer en aveugle :

- shuffle ;
- métadonnées seules ;
- métadonnées et historique ;
- historique et DSP ;
- historique, DSP et embeddings.

Cette évaluation doit inclure les styles réellement présents dans la bibliothèque de l’utilisateur. Les métriques publiques d’un modèle ne prouvent pas sa qualité sur des morceaux Suno, des fichiers mal tagués ou une collection très personnelle.

## 11. Questions ouvertes à valider

### Produit

1. L’Auto-DJ doit-il prolonger n’importe quelle lecture, ou seulement une session explicitement lancée ?
2. Le premier objectif est-il la cohérence de transition, la découverte ou la réduction des skips ?
3. Quelle action utilisateur traduit le mieux un feedback négatif sans alourdir le lecteur ?
4. L’utilisateur veut-il voir des BPM et humeurs, ou seulement bénéficier du résultat ?
5. L’historique d’écoute doit-il compter avant l’activation de l’Auto-DJ ?

### Données

6. Quelle est la taille réelle et maximale des bibliothèques ?
7. Quelle proportion des morceaux possède artiste, album et genre fiables ?
8. Quels codecs et quelles durées sont réellement présents ?
9. Les fichiers Suno ont-ils des tags cohérents ou faut-il privilégier l’audio ?
10. Faut-il synchroniser l’historique entre appareils, ce qui changerait la portée confidentialité ?

### Qualité audio

11. Un tempo approximatif améliore-t-il réellement l’écoute, ou l’énergie suffit-elle ?
12. Les erreurs demi-temps et double-temps sont-elles acceptables si la confiance est faible ?
13. Trois fenêtres audio reproduisent-elles assez bien le caractère d’un morceau complet ?
14. La voix et l’humeur apportent-elles plus de valeur que genre, énergie et habitudes ?
15. Faut-il analyser pendant la lecture ou mettre l’analyse en pause pour protéger batterie et stabilité ?

### Modèles et licence

16. Existe-t-il un modèle musical avec licence commerciale explicite compatible avec le budget ?
17. Le modèle exact se convertit-il sans opération personnalisée vers Core ML ?
18. Les sorties Core ML restent-elles numériquement proches des sorties de référence ?
19. Le modèle fonctionne-t-il sur le plus ancien iPhone supporté ?
20. La valeur des embeddings justifie-t-elle le coût face à un DSP Apple simple ?

## Conclusion

La proposition recommandée n’est pas « ajouter de l’IA » mais construire un système progressif :

1. instrumentation locale fiable ;
2. politique déterministe personnalisée et explicable ;
3. caractéristiques audio locales optionnelles ;
4. modèle embarqué seulement après preuve de valeur ;
5. backend seulement après preuve d’une limite locale.

Cette trajectoire préserve l’identité actuelle de SunoPlayer : simple, personnel, hors ligne et respectueux des fichiers privés. Elle permet aussi d’arrêter l’investissement à chaque phase si la suivante n’apporte pas un gain mesurable.
