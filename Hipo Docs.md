# HipoControls — guide Potassium

## Source et lancement

La source unique est [`HipoControlsBase/HipoControlsBase.lua`](HipoControlsBase/HipoControlsBase.lua). Elle retourne une bibliothèque; elle ne crée pas l’interface avant l’appel à `HipoControls.new(options)`.

Dans ton script client, charge la source puis crée l’interface :

~~~lua
local HipoControls = loadstring(game:HttpGet(
    "https://github.com/Krito444/HipoUiSource/raw/refs/heads/main/HipoControlsBase/HipoControlsBase.lua"
))()

local UI_CONFIG = {
    Title = "Mon interface",
    Keybind = Enum.KeyCode.RightControl,
}

local ui = HipoControls.new(UI_CONFIG)
~~~

`ui` est l’instance de l’interface. Si une autre interface HipoControls est déjà ouverte, elle est fermée avant la création de la nouvelle.

## Configurer le titre et le raccourci

`UI_CONFIG` appartient au script appelant. Change `Title` et `Keybind` à cet endroit; le code de la bibliothèque reste identique.

~~~lua
local UI_CONFIG = {
    Title = "Bloxburg Helper",
    Keybind = Enum.KeyCode.RightControl,
}
~~~

`Keybind` définit le raccourci initial pour afficher ou masquer l’interface. Il reste modifiable pendant la session dans **Settings > General > Hide UI**. La taille de la fenêtre reste fixe.

## Organisation du menu

Un onglet latéral contient des pages. Chaque page contient des sections, puis des contrôles. Les sections d’une page se répartissent en deux colonnes; elles s’ajoutent alternativement à gauche et à droite. Sur une fenêtre étroite, elles repassent en une seule colonne. Appelle `AddPage` sur l’instance `ui` :

~~~lua
local objects = ui:AddPage("Inventaire", "package", "Objets")
local options = objects:Section("Options", "package")

options:Toggle({
    Text = "Afficher les objets",
    Description = "Active l’affichage des objets de l’inventaire.",
    Default = true,
    Callback = function(enabled)
        print("Afficher les objets :", enabled)
    end,
})
~~~

L’image ci-dessous juxtapose le code et le rendu dans l’interface.

![Exemple de code et rendu du toggle dans Hipo Controls](images/ajout-toggle-code-rendu.png)

Chaque ligne prépare une partie du menu : `AddPage` crée le bouton latéral et la page, `:Section` regroupe les contrôles et `:Toggle` ajoute l’interrupteur. `Default` définit son état au démarrage. La fonction `Callback` reçoit `true` quand le toggle est activé et `false` quand il est désactivé.
À l’exécution, clique sur l’icône **Inventaire** dans la barre latérale pour afficher la page.

Tu peux ajouter plusieurs pages au même onglet latéral en donnant leurs noms après le nom de la première page. Le troisième résultat contient les constructeurs de contrôles, indexés par nom :

~~~lua
local farm, _, farmPages = ui:AddPage("Farm", "package", "Farm", "AutreTabs")
local farmOptions = farm:Section("Options Farm", "settings")
local otherOptions = farmPages.AutreTabs:Section("Autres options", "settings")

local objects = ui:AddPage("Inventaire", "package", "Objets")
~~~

`Farm` et `AutreTabs` deviennent deux pages horizontales sous le même bouton latéral **Farm**. `Inventaire` reste un onglet latéral séparé. Le premier résultat de `AddPage` reste le constructeur de contrôles de la première page, ce qui conserve les anciens appels à trois paramètres.

### Ranger le script avec des tables

Tu peux ranger les pages, les sections et les contrôles dans des tables nommées. La table `sections` contient les sections par page; les tables `toggles` et `buttons` regroupent ensuite les contrôles par type. Les clés (`Farm`, `Options1`, `AutoFarm`, etc.) servent à retrouver facilement chaque élément dans ton script.

~~~lua
local farmPage, _, farmPageNames = ui:AddPage("Farm", "package", "Farm", "AutreTabs")
local inventoryPage = ui:AddPage("Inventaire", "package", "Objets")

local pages = {
    Farm = farmPage,
    AutreTabs = farmPageNames.AutreTabs,
    Inventaire = inventoryPage,
}

local sections = {
    Farm = {
        Options1 = pages.Farm:Section("Options 1", "settings"),
        Options2 = pages.Farm:Section("Options 2", "settings"),
    },
    AutreTabs = {
        Options = pages.AutreTabs:Section("Autres options", "settings"),
    },
    Inventaire = {
        Options = pages.Inventaire:Section("Options", "package"),
    },
}

local toggles = {
    Farm = {
        AutoFarm = sections.Farm.Options1:Toggle({
            Text = "Auto Farm",
            Default = false,
            Callback = function(enabled)
                print("Auto Farm :", enabled)
            end,
        }),
    },
    Inventaire = {
        AfficherObjets = sections.Inventaire.Options:Toggle({
            Text = "Afficher les objets",
            Default = true,
        }),
    },
}

local buttons = {
    Farm = {
        Demarrer = sections.Farm.Options2:Button({
            Text = "Démarrer le farm",
            ButtonText = "Run",
            Callback = function()
                print("Farm démarré")
            end,
        }),
    },
}
~~~

Par exemple, `sections.Farm.Options1` désigne la première section de Farm et `toggles.Farm.AutoFarm` désigne son toggle. Pour retrouver un bouton, cherche dans `buttons`; pour ajouter d’autres familles de contrôles, reprends le même modèle avec une table dédiée, comme `dropdowns` ou `sliders`. La méthode de création reste `:Section(...)` au singulier : `sections` est simplement une table Lua qui organise ton script.

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

Les contrôles avec une valeur renvoient un objet de contrôle. Garde-le dans une variable pour consulter ou modifier sa valeur avec `:Get()` et `:Set(...)`. Pour fermer l’interface et nettoyer ses connexions, appelle `ui:Destroy()`.
