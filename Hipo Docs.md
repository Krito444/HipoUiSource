# HipoControls Base — guide Potassium

## Source et lancement

La source unique est [`HipoControlsBase/HipoControlsBase.lua`](HipoControlsBase/HipoControlsBase.lua). C’est un script client autonome destiné à l’éditeur Potassium, pas un `LocalScript` ou `ModuleScript` Roblox Studio.

1. Attache Potassium au client Roblox déjà dans une partie.
2. Ouvre `HipoControlsBase.lua` dans l’éditeur, ou colle tout son contenu dans un onglet.
3. Clique sur **Execute**.

Le script vérifie que le joueur local et `PlayerGui` sont disponibles. S’il est relancé, il ferme l’ancienne interface avant d’en créer une nouvelle.

Pour personnaliser le menu, modifie le bloc `AJOUTER VOTRE MENU PERSONNALISÉ ICI`, vers la fin du fichier. Garde les fonctions de la bibliothèque au-dessus de ce bloc.

## Organisation du menu

Un onglet latéral contient des onglets horizontaux. Chaque onglet horizontal contient des sections, puis des contrôles :

~~~lua
local inventory = addSidebarTab("Inventaire", "package")
local objects = inventory:Tab("Objets")
local options = objects:Section("Options", "package")

options:Toggle({
    Text = "Afficher les objets",
    Default = true,
    Callback = function(enabled)
        print(enabled)
    end,
})
~~~

Les icônes utilisent les noms Lucide, par exemple `settings`, `eye`, `search` ou `package`.

## Contrôles disponibles

### Bouton

~~~lua
options:Button({
    Text = "Enregistrer",
    ButtonText = "Sauvegarder",
    Style = "filled",
    Callback = function()
        print("Enregistré")
    end,
})
~~~

Styles disponibles : `outline`, `filled`, `ghost` et `soft`. `Primary = true` sélectionne aussi le style rempli.

### Curseur

~~~lua
options:Slider({
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

### Champ texte

~~~lua
options:Input({
    Text = "Nom",
    Placeholder = "Écris ici...",
    Default = "",
    Callback = function(value)
        print(value)
    end,
})
~~~

### Liste déroulante

~~~lua
options:Dropdown({
    Text = "Mode",
    Options = {"Simple", "Avancé", "Personnalisé"},
    Default = "Simple",
    Callback = function(choice)
        print(choice)
    end,
})
~~~

### Raccourci clavier

~~~lua
options:Keybind({
    Text = "Raccourci",
    Default = Enum.KeyCode.F,
    Callback = function(key)
        print("Touche pressée :", key.Name)
    end,
})
~~~

### Sélecteurs de couleur

~~~lua
options:ColorPicker({
    Text = "Couleur",
    Value = Color3.fromRGB(80, 170, 255),
    Callback = function(color)
        print(color)
    end,
})

options:Palette({
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

## Options communes

| Option | Utilité |
|---|---|
| `Text` | Nom du contrôle. |
| `Description` | Texte explicatif facultatif. |
| `Default` | Valeur initiale pour les toggles, curseurs, champs, listes et raccourcis. |
| `Value` | Valeur initiale pour les sélecteurs de couleur. |
| `Callback` | Fonction appelée lors d’un changement ou d’une action. |
| `Icon` | Icône facultative du contrôle. |

Les contrôles avec une valeur renvoient un objet de contrôle. Garde-le dans une variable pour consulter ou modifier sa valeur avec `:Get()` et `:Set(...)`.
