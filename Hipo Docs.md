# Hipo Docs
## Ajouter des contrôles — guide rapide

Ce guide correspond au fichier autonome HipoControls.client.lua. Il contient la bibliothèque complète et peut être lancé dans un jeu Roblox standard.

## Démarrage rapide — fichier unique

1. Dans Roblox Studio, crée un `LocalScript` sous `StarterPlayer > StarterPlayerScripts`, puis copie-colle dedans tout le contenu de `HipoControls.client.lua`.
2. Lance le jeu avec **Play**. L’interface et les contrôles d’exemple apparaissent automatiquement.
3. Personnalise le code après le commentaire `PERSONNALISE TON INTERFACE À PARTIR D'ICI`, en bas du fichier.

Le fichier contient la bibliothèque et le code de démarrage. Il n’utilise ni `require`, ni `loadstring`, ni `game:HttpGet`. Un `LocalScript` Roblox standard ne peut pas télécharger puis exécuter du code Luau depuis GitHub Raw. Pour un jeu Roblox standard, le code doit donc être inclus dans le jeu.

## Ajouter un contrôle

Dans `HipoControls.client.lua`, repère la ligne :

~~~lua
local main = win:Section("Paramètres", "settings")
~~~

Ajoute tes contrôles après cette ligne, avec `main:NomDuContrôle({...})`. Tu peux en ajouter autant que tu veux.

Pour créer une autre carte :

~~~lua
local display = win:Section("Affichage", "eye")

display:Toggle({
    Text = "Afficher les effets",
    Default = true,
})
~~~

Dans la bibliothèque, chaque appel à `win:Section(...)` crée une carte dans la fenêtre. Tu peux ajouter autant de sections et de contrôles que nécessaire.

Si tu as déjà un conteneur graphique, tu peux le fournir à la place :

~~~lua
local window = HipoControls.new(monScreenGui, {Title = "Mon interface"})
~~~

## Choisir un contrôle

### Interrupteur — Toggle

Reçoit true quand l’option est activée et false quand elle est désactivée.

~~~lua
main:Toggle({
    Text = "Activer",
    Description = "Description facultative.",
    Default = false,
    Callback = function(enabled)
        print(enabled)
    end,
})
~~~

### Bouton — Button

Le callback s’exécute au clic. ButtonText est le texte du bouton.

~~~lua
main:Button({
    Text = "Enregistrer",
    ButtonText = "Sauvegarder",
    Style = "filled",
    Callback = function()
        print("Enregistré")
    end,
})
~~~

Styles disponibles : outline, filled, ghost et soft. Tu peux aussi écrire Primary = true pour utiliser le style filled.

### Curseur — Slider

Min et Max définissent les bornes. Step règle le pas et Suffix ajoute une unité après le nombre.

~~~lua
main:Slider({
    Text = "Distance",
    Min = 0,
    Max = 100,
    Step = 5,
    Default = 25,
    Suffix = " studs",
    Callback = function(value)
        print(value)
    end,
})
~~~

### Champ texte — Input

Le callback est appelé quand le joueur valide le texte ou quitte le champ.

~~~lua
main:Input({
    Text = "Nom",
    Placeholder = "Écris ici...",
    Default = "",
    Callback = function(text)
        print(text)
    end,
})
~~~

### Liste — Dropdown

Options contient les choix. Default doit être un des choix.

~~~lua
main:Dropdown({
    Text = "Mode",
    Options = {"Simple", "Avancé", "Personnalisé"},
    Default = "Simple",
    Callback = function(choice)
        print(choice)
    end,
})
~~~

### Raccourci clavier — Keybind

Clique sur le contrôle pour choisir une touche. Ensuite, Callback s’exécute quand cette touche est pressée.

~~~lua
main:Keybind({
    Text = "Raccourci",
    Default = Enum.KeyCode.F,
    Callback = function(key)
        print("Touche pressée :", key.Name)
    end,
})
~~~

### Sélecteur de couleur — ColorPicker

Value est la couleur initiale. Callback reçoit la nouvelle couleur.

~~~lua
main:ColorPicker({
    Text = "Couleur",
    Value = Color3.fromRGB(80, 170, 255),
    Callback = function(color)
        print(color)
    end,
})
~~~

### Palette de couleurs — Palette

Affiche plusieurs couleurs sous forme de pastilles. Value doit être une couleur présente dans Colors.

~~~lua
main:Palette({
    Text = "Couleur rapide",
    Colors = {
        Color3.fromRGB(80, 170, 255),
        Color3.fromRGB(190, 220, 35),
        Color3.fromRGB(240, 90, 110),
    },
    Value = Color3.fromRGB(80, 170, 255),
    Callback = function(color)
        print(color)
    end,
})
~~~

## Lire ou modifier une valeur

Les contrôles qui ont une valeur renvoient un handle. Garde-le dans une variable pour lire ou changer la valeur plus tard.

~~~lua
local volume = main:Slider({
    Text = "Volume",
    Min = 0,
    Max = 100,
    Default = 50,
})

print(volume:Get()) -- lit la valeur actuelle
volume:Set(75)      -- change la valeur et appelle Callback
volume:Set(25, true) -- change la valeur sans appeler Callback
~~~

Cette méthode fonctionne pour Toggle, Slider, Input, Dropdown, Keybind, ColorPicker et Palette.

## Les options à retenir

| Option | Sert à |
|---|---|
| Text | Nom affiché à côté du contrôle. |
| Description | Petite explication sous le nom. |
| Default | Valeur au démarrage pour Toggle, Slider, Input, Dropdown et Keybind. |
| Value | Valeur au démarrage pour ColorPicker et Palette. |
| Callback | Code exécuté lorsque la valeur ou l’action change. |
| Icon | Icône facultative à côté du nom. |

Les icônes utilisent les noms Lucide, par exemple settings, eye, search ou heart. Une icône inconnue est simplement ignorée.

## Si rien ne s’affiche

Vérifie ces points :

1. Le code complet est collé dans un `LocalScript` sous `StarterPlayer > StarterPlayerScripts`.
2. Tu as lancé le jeu avec **Play**.
3. Ouvre **Vue > Output (Sortie)** pour lire une éventuelle erreur.

## À propos des onglets

Le fichier autonome utilise `win:Section` pour créer des cartes dans la fenêtre. Il ne reprend pas toute l’API Ember : les options `Subtitle`, `Size` et `Keybind` ne sont pas encore prises en charge par ce fichier.

## Référence de présentation

Le guide suit une organisation débutant inspirée de la documentation Ember : démarrage rapide, contrôles séparés, puis lecture des valeurs. Les exemples ci-dessus correspondent au fichier autonome HipoControls de ce dossier.

[Documentation Ember](https://rbx.lol/docs/ember/)

