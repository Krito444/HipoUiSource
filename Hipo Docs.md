# Guide HipoControls

Ce guide explique comment charger la bibliothèque, créer les pages et sections du menu, puis y ajouter les contrôles.

## 1. Exemple minimal complet

Copie cet exemple dans un script Potassium. Il charge la bibliothèque, crée le menu, ajoute une page, une section, un toggle et un bouton :

```lua
local HipoControls = loadstring(game:HttpGet(
    "https://github.com/Krito444/HipoUiSource/raw/refs/heads/main/HipoControlsBase/HipoControlsBase.lua"
))()
local ui = HipoControls.new({
	Title = "Game Name ",
	Keybind = Enum.KeyCode.RightControl,
})

local Inventaire = ui:AddPage("Inventaire", "package", "Objets")
local Options = Inventaire:Section("Options", "settings")

local AfficherObjets = Options:Toggle({
    Text = "Afficher les objets",
    Default = true,
    Callback = function(active)
        print("Afficher les objets :", active)
    end,
})

local Actualiser = Options:Button({
    Text = "Actualiser",
    ButtonText = "Run",
    Callback = function()
        print("Actualisation demandée")
    end,
})
```

La bibliothèque ne crée pas le menu avant l’appel à `HipoControls.new(...)`. La taille de la fenêtre utilise sa valeur par défaut. `Title` règle le titre; `Keybind` définit le raccourci pour masquer ou réafficher le menu. Ce raccourci peut ensuite être changé dans **Settings**.

## 2. Configurer la page affichée au lancement

Par défaut, le menu ouvre la première page ajoutée. Pour en choisir une autre, ajoute `DefaultTab` dans la table passée à `HipoControls.new` :

```lua
local UI_CONFIG = {
    Title = "Mon interface",
    Keybind = Enum.KeyCode.RightControl,
    DefaultTab = "Objets",
}
```

Si plusieurs onglets latéraux contiennent une page du même nom, précise aussi son onglet :

```lua
local UI_CONFIG = {
    Title = "Mon interface",
    Keybind = Enum.KeyCode.RightControl,
    DefaultTab = { Sidebar = "Farm", Page = "Récolte" },
}
```

## 3. Ajouter une page et une section

`AddPage` prend le nom de l’onglet latéral, son icône Lucide et le nom de la page. `Section` crée une carte dans cette page. Les contrôles s’ajoutent ensuite à la section.

```lua
local Inventaire = ui:AddPage("Inventaire", "package", "Objets")
local Options = Inventaire:Section("Options", "settings")
```

Les sections d’une page se placent automatiquement en deux colonnes, en alternant gauche et droite.

### Plusieurs pages sous le même onglet

Ajoute les noms des pages supplémentaires à la fin de l’appel. Le troisième résultat permet de récupérer chaque page par son nom :

```lua
local Farm, _, FarmPages = ui:AddPage("Farm", "package", "Récolte", "AutreTabs")

local OptionsRecolte = Farm:Section("Options", "settings")
local OptionsAutres = FarmPages.AutreTabs:Section("Autres options", "settings")
```

Ici, **Récolte** et **AutreTabs** sont deux pages du même onglet latéral **Farm**.

## 4. Ranger les pages, sections et contrôles

Les tables Lua servent à organiser ton script et à retrouver facilement chaque contrôle. Elles ne sont pas obligatoires, mais deviennent pratiques lorsque le menu grandit.

```lua
local Pages = {
    Farm = ui:AddPage("Farm", "package", "Récolte"),
    Inventaire = ui:AddPage("Inventaire", "package", "Objets"),
}

local Sections = {
    Farm = {
        Options = Pages.Farm:Section("Options", "settings"),
        Actions = Pages.Farm:Section("Actions", "zap"),
    },
    Inventaire = {
        Options = Pages.Inventaire:Section("Options", "settings"),
    },
}

local Toggles = {
    Farm = {
        AutoFarm = Sections.Farm.Options:Toggle({
            Text = "Auto Farm",
            Default = false,
            Callback = function(active)
                print("Auto Farm :", active)
            end,
        }),
    },
}

local Buttons = {
    Farm = {
        Demarrer = Sections.Farm.Actions:Button({
            Text = "Démarrer",
            ButtonText = "Run",
            Callback = function()
                print("Farm démarré")
            end,
        }),
    },
}
```

Par exemple, `Sections.Farm.Options` désigne la section **Options** de la page **Récolte**, et `Toggles.Farm.AutoFarm` désigne son toggle.

## 5. Les contrôles disponibles

Chaque contrôle s’ajoute avec une méthode de la section : `Options:Toggle(...)`, `Options:Button(...)`, etc. `Text` est le libellé du contrôle. `Description` et `Icon` sont facultatifs.

### Toggle

Le callback reçoit `true` à l’activation et `false` à la désactivation.

```lua
local AutoFarm = Options:Toggle({
    Text = "Auto Farm",
    Description = "Active ou arrête le farm.",
    Default = false,
    Icon = "zap",
    Callback = function(active)
        print("État du farm :", active)
    end,
})
```

### Bouton

`Text` nomme l’action dans la ligne et `ButtonText` affiche le texte du bouton. Les styles possibles sont `outline` (par défaut), `filled`, `ghost` et `soft`.

```lua
local Demarrer = Options:Button({
    Text = "Démarrer",
    ButtonText = "Run",
    Style = "filled",
    Callback = function()
        print("Bouton cliqué")
    end,
})
```

Tu peux aussi utiliser `Primary = true` pour choisir le style `filled`.

### Curseur

`Step` règle le pas entre les valeurs; `Suffix` ajoute une unité après la valeur affichée.

```lua
local Vitesse = Options:Slider({
    Text = "Vitesse",
    Min = 0,
    Max = 100,
    Step = 5,
    Default = 25,
    Suffix = " studs",
    Callback = function(value)
        print("Vitesse :", value)
    end,
})
```

### Champ texte

Le callback reçoit le texte quand le joueur valide ou quitte le champ.

```lua
local Nom = Options:Input({
    Text = "Nom",
    Placeholder = "Écris un nom...",
    Default = "",
    Callback = function(value)
        print("Nom saisi :", value)
    end,
})
```

### Liste déroulante

`Default` doit correspondre à une valeur présente dans `Options`. Le callback reçoit l’option choisie.

```lua
local Mode = Options:Dropdown({
    Text = "Mode",
    Options = {"Simple", "Avancé", "Personnalisé"},
    Default = "Simple",
    Callback = function(choice)
        print("Mode choisi :", choice)
    end,
})
```

Les noms de méthodes `Dropdown` et `DropDown` sont tous deux acceptés.

> **Limite à connaître :** le dropdown Hipo est textuel. Il affiche les options avec `tostring` et les retrouve avec `table.find`; il ne dessine pas d’image par entrée. Pour une caisse, place donc son nom et son ID dans le libellé. Pour afficher une icône par option, il faut créer un menu personnalisé ou faire évoluer HipoUiSource pour accepter un champ `Icon` par option.

### Liste déroulante à sélection multiple

Utilise `:MultiDropdown` pour ajouter une case à cocher devant chaque option. Le menu reste ouvert pendant la sélection. Le callback reçoit un tableau contenant les options cochées; `Default` accepte aussi un tableau.

```lua
local ModesChoisis = Options:MultiDropdown({
    Text = "Modes actifs",
    Options = {"Simple", "Avancé", "Personnalisé"},
    Default = {"Simple", "Personnalisé"},
    Callback = function(selectedModes)
        print("Modes actifs :", table.concat(selectedModes, ", "))
    end,
})

-- Lire ou changer la sélection après sa création
local selection = ModesChoisis:Get()
ModesChoisis:Set({"Avancé"})
```

Tu peux aussi conserver `:Dropdown` et activer `MultiSelect = true` dans sa configuration :

```lua
local ModesChoisis = Options:Dropdown({
    Text = "Modes actifs",
    Options = {"Simple", "Avancé", "Personnalisé"},
    MultiSelect = true,
    Default = {"Simple"},
})
```

### Raccourci clavier

Clique sur le contrôle pour enregistrer un nouveau raccourci. Le callback est appelé lorsque cette touche est pressée.

```lua
local Raccourci = Options:Keybind({
    Text = "Action rapide",
    Default = Enum.KeyCode.F,
    Callback = function(key)
        print("Touche pressée :", key.Name)
    end,
})
```

### Choix de couleur

`ColorPicker` ouvre un sélecteur. `Palette` affiche des pastilles de couleur. Pour ces deux contrôles, utilise `Value` pour la couleur initiale.

```lua
local Couleur = Options:ColorPicker({
    Text = "Couleur",
    Value = Color3.fromRGB(80, 170, 255),
    Callback = function(color)
        print("Nouvelle couleur :", color)
    end,
})

local CouleurRapide = Options:Palette({
    Text = "Couleurs rapides",
    Colors = {
        Color3.fromRGB(80, 170, 255),
        Color3.fromRGB(190, 105, 255),
        Color3.fromRGB(240, 90, 110),
    },
    Value = Color3.fromRGB(80, 170, 255),
    Callback = function(color)
        print("Couleur choisie :", color)
    end,
})
```

## 6. Lire ou changer une valeur

Les contrôles qui ont une valeur (toggle, curseur, champ texte, liste, raccourci ou couleur) renvoient un objet que tu peux garder dans une variable. Utilise `:Get()` pour lire sa valeur et `:Set(...)` pour la changer.

```lua
print("Auto Farm :", Toggles.Farm.AutoFarm:Get())
Toggles.Farm.AutoFarm:Set(true)
```

`Set(value, true)` change la valeur sans appeler le callback. Pour un bouton, le résultat est une poignée différente : elle propose notamment `:SetText(...)`, `:Show()`, `:Hide()` et `:Destroy()`.

## 7. Options communes

| Option | Utilisation |
|---|---|
| `Text` | Libellé visible du contrôle. |
| `Description` | Petit texte explicatif sous le libellé. |
| `Icon` | Icône Lucide facultative, par exemple `package`, `settings`, `eye` ou `zap`. |
| `Default` | Valeur initiale d’un toggle, curseur, champ, liste ou raccourci. |
| `Value` | Valeur initiale d’une couleur; également utilisable comme valeur initiale selon le contrôle. |
| `Callback` | Fonction appelée quand le contrôle change ou est utilisé. |

Pour fermer le menu et nettoyer ses connexions, appelle :

```lua
ui:Destroy()
```
