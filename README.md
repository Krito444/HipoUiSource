# HipoControls — Potassium

[`HipoControlsBase/HipoControlsBase.lua`](HipoControlsBase/HipoControlsBase.lua) retourne la bibliothèque. Elle crée une interface quand le script appelant exécute `HipoControls.new(options)`.

## Charger et créer une interface

```lua
local HipoControls = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/Krito444/HipoUiSource/main/HipoControlsBase/HipoControlsBase.lua"
))()

local ui = HipoControls.new({
    Title = "Mon interface",
    Keybind = Enum.KeyCode.RightControl,
})
```

Le script appelant configure le titre et le raccourci, puis ajoute ses pages et contrôles via l’instance `ui`.

Voir [Hipo Docs.md](Hipo%20Docs.md) pour les exemples de contrôles.
