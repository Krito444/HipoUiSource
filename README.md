# HipoControls — version autonome Roblox

Pour essayer l’interface dans un jeu Roblox standard sans `require`, utilise **HipoControls.client.lua**. Crée un `LocalScript` dans `StarterPlayer > StarterPlayerScripts`, copie-colle tout le contenu du fichier dedans, puis lance **Play**. Il contient la bibliothèque et un exemple prêt à modifier.

Un `LocalScript` standard ne peut pas exécuter directement du code téléchargé depuis GitHub Raw avec `loadstring(game:HttpGet(...))`. Le code client doit être inclus dans ton jeu.

Voir [Hipo Docs — ajouter des contrôles](Hipo%20Docs.md) pour personnaliser les sections et les contrôles.

## Autres sources

`HipoControls.ModuleScript.lua`, `TargetHunterClient.client.lua` et `TargetHunterServer.server.lua` sont les sources séparées de l’ancienne intégration Studio. `TestEnJeuExact.lua` sert à l’aperçu de l’interface avec le Remote neutralisé.