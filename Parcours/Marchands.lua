-- Parcours : module Marchands (ex-addon CuisineMarchands), étendu à tous les métiers de production.
-- Commandes : /cmarch (ou /parcours marchands ...), /cmarch <métier> pour filtrer.
-- Enregistre les marchands qui vendent des composants ou des recettes (patrons, plans, schémas, formules, manuels...).
-- Les relevés successifs d'un même marchand sont fusionnés (jamais écrasés).

CuisineMarchandsDB = CuisineMarchandsDB or {}

-- Composants de cuisine pouvant être vendus (id objet)
local COMPOSANTS = {
    [2678]  = "Epices douces",
    [2692]  = "Epices fortes",
    [3713]  = "Epices apaisantes",
    [17194] = "Epices spéciales (fête)",
    [159]   = "Eau de source",
    [10284] = "Farine simple",
    [1179]  = "Lait glacé",
    [4470]  = "Bois simple",
    [11291] = "Bois d'étoile",
    [4536]  = "Pomme rouge brillante",
    [1205]  = "Jus de melon",
    [1708]  = "Nectar sucré",
    [1645]  = "Jus de baie lunaire",
    [2596]  = "Outre de bière naine",
    [2894]  = "Bière au malt Rhapsody",
    [17196] = "Eau de vie spéciale (fête)",
    [8766]  = "Soupe de rosée matinale",
}

-- Réactifs courants vendus par les PNJ pour les autres métiers (ids certains ; noms anglais, remplacés par le nom du jeu à l'affichage)
local REACTIFS_COMMUNS = {
    [3371] = "Empty Vial", [3372] = "Leaded Vial", [8925] = "Crystal Vial",
    [2320] = "Coarse Thread", [2321] = "Fine Thread", [4291] = "Silken Thread", [14341] = "Rune Thread",
    [2880] = "Weak Flux", [3466] = "Strong Flux",
}

-- Composants des plans de progression (tous les métiers de production), lus dans ParcoursData : id -> { nom, metiers }
local planComposants
local function PlanComposants()
    if planComposants then return planComposants end
    planComposants = {}
    local data = ParcoursData
    if data and data.metiers then
        for mid, m in pairs(data.metiers) do
            if not m.recolte then
                for _, q in ipairs(m.quetes or {}) do
                    for _, ing in ipairs(q.ingredients or {}) do
                        if ing.id then
                            local e = planComposants[ing.id]
                            if not e then
                                e = { nom = ing.nom, metiers = {} }
                                planComposants[ing.id] = e
                            end
                            e.metiers[mid] = true
                        end
                    end
                end
            end
        end
    end
    return planComposants
end

local function EstComposant(id)
    return COMPOSANTS[id] ~= nil or REACTIFS_COMMUNS[id] ~= nil or PlanComposants()[id] ~= nil
end

-- Nom affiché d'un composant : nom du jeu (localisé) si disponible, sinon la table locale
local function NomComposant(id)
    if COMPOSANTS[id] then return COMPOSANTS[id] end
    local ok, n = pcall(function()
        if GetItemInfo then
            local r = GetItemInfo(id)
            if type(r) == "table" then return r.name end
            return r
        end
    end)
    if ok and type(n) == "string" and n ~= "" then return n end
    return REACTIFS_COMMUNS[id] or (PlanComposants()[id] and PlanComposants()[id].nom) or id
end

-- Recettes : classe d'objet "Recette" ; sous-classe -> métier (Classic)
local CLASSE_RECETTE = (Enum and Enum.ItemClass and Enum.ItemClass.Recipe) or 9
local SOUS_CLASSE_METIER = {
    [1] = "cuir", [2] = "couture", [3] = "ingenierie", [4] = "forge", [5] = "cuisine",
    [6] = "alchimie", [7] = "secourisme", [8] = "enchantement",
}

local debugActif = false

local function Print(msg)
    print("|cff66ccffCuisineMarchands|r " .. msg)
end

local function Arrondi(v)
    return math.floor(v * 1000 + 0.5) / 10  -- pourcentage, 1 décimale
end

-- GUID d'une créature : "Creature-0-serveur-instance-zone-npcID-uniqueID"
local function LireNpcId(guid)
    local typ, _, _, _, _, id = strsplit("-", guid)
    if typ == "Creature" or typ == "Vehicle" then
        return tonumber(id)
    end
    return nil
end

-- Classe et sous-classe d'un objet (nil si le jeu ne les donne pas)
local function InfoObjet(id)
    local cls, sub
    if GetItemInfoInstant then
        local _, _, _, _, _, a, b = GetItemInfoInstant(id)
        cls, sub = a, b
    end
    if cls == nil and GetItemInfo then
        local _, _, _, _, _, _, _, _, _, _, _, a, b = GetItemInfo(id)
        cls, sub = a, b
    end
    return cls, sub
end

-- Recettes de cuisine confirmées par les relevés en jeu (id objet)
local RECETTES_CONNUES = {
    [6325]  = true,  -- Recette : Goujon brillant
    [6326]  = true,  -- Recette : Maquereau ombré
    [12226] = true,  -- Recette : Aile de chauve-souris croustillante
}

-- Début du nom des objets de recette : Recette, Plans, Patron, Schéma, Formule, Manuel, Livre...
local PREFIXES_RECETTE = { "recette", "recipe", "rezept", "receta", "ricetta", "receita",
    "plans", "plan", "patron", "pattern", "schéma", "schema", "schematic", "formule", "formula",
    "manuel", "manual", "livre", "book" }

local function CommencePar(nom, prefixes)
    local n = (nom or ""):lower()
    for _, p in ipairs(prefixes) do
        if n:sub(1, #p) == p then
            local suite = n:sub(#p + 1, #p + 1)
            if suite == "" or suite:match("[%s:%.%-]") or n:sub(#p + 1, #p + 2) == "\194\160" then return true end
        end
    end
    return false
end

-- Lignes de l'info-bulle d'un objet du marchand (info-bulle cachée)
local tip
local function LignesInfoBulle(i)
    if not (CreateFrame and UIParent) then return nil end
    if not tip then
        tip = CreateFrame("GameTooltip", "CuisineMarchandsTip", UIParent, "GameTooltipTemplate")
    end
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    tip:ClearLines()
    tip:SetMerchantItem(i)
    local lignes = {}
    for n = 1, (tip:NumLines() or 0) do
        local g = _G["CuisineMarchandsTipTextLeft" .. n]
        local t = g and g:GetText()
        if t then lignes[#lignes + 1] = t end
    end
    return lignes
end

-- Métiers de production connus (ParcoursData) : liste d'ids et mots reconnus dans le client
local function MetiersProduction()
    local liste = {}
    local data = ParcoursData
    if data and data.metiers then
        for _, id in ipairs(data.ordre or {}) do
            local m = data.metiers[id]
            if m and not m.recolte then liste[#liste + 1] = { id = id, nom = m.nom, mots = m.motsClient or {} } end
        end
    end
    return liste
end

local function LigneMentionne(ligne, mots)
    local l = ligne:lower()
    for _, m in ipairs(mots) do
        if l:find("%f[%a]" .. m:gsub("%p", "%%%0") .. "%f[%A]") then return true end
    end
    return false
end

-- Métier cité par l'info-bulle : d'abord les lignes « Nécessite / Requires ... », puis toutes les lignes
local function MetierDansInfoBulle(lignes)
    if not lignes then return nil end
    local metiers = MetiersProduction()
    for passe = 1, 2 do
        for k = 2, #lignes do  -- la ligne 1 est le nom de l'objet
            local l = lignes[k]:lower()
            local exigence = l:find("nécessite", 1, true) or l:find("requires", 1, true) or l:find("requiert", 1, true) or l:find("requis", 1, true)
            if passe == 2 or exigence then
                for _, m in ipairs(metiers) do
                    if LigneMentionne(lignes[k], m.mots) then return m.id end
                end
            end
        end
    end
    return nil
end

-- Métier d'une recette vendue (nil si ce n'est pas une recette). La bêta ne fournit pas la catégorie des objets :
-- on s'appuie sur la sous-classe quand elle existe, sinon sur le nom puis sur l'info-bulle.
local function MetierDeRecette(id, nom, i, cls, sub)
    if cls == CLASSE_RECETTE and SOUS_CLASSE_METIER[sub] then return SOUS_CLASSE_METIER[sub] end
    if cls ~= nil and cls ~= CLASSE_RECETTE then return nil end
    if RECETTES_CONNUES[id] then return "cuisine" end
    if CommencePar(nom, PREFIXES_RECETTE) then
        local ok, lignes = pcall(LignesInfoBulle, i)
        if ok then return MetierDansInfoBulle(lignes) end
    end
    return nil
end

-- Lit tous les objets du marchand ouvert
local function Scanner()
    local composants, recettes, objets = {}, {}, {}
    local n = GetMerchantNumItems()
    local sansLien = 0
    for i = 1, n do
        local lien = GetMerchantItemLink(i)
        local id = lien and tonumber(lien:match("item:(%d+)"))
        if not id then
            sansLien = sansLien + 1
        else
            local cls, sub = InfoObjet(id)
            local nom = lien:match("%[(.-)%]")
            local entree = { i = i, id = id, nom = nom, cls = cls, sub = sub }
            if debugActif and CommencePar(nom, PREFIXES_RECETTE) then
                local ok, lignes = pcall(LignesInfoBulle, i)
                if ok then entree.lignes = lignes end
            end
            objets[#objets + 1] = entree
            if EstComposant(id) then
                composants[#composants + 1] = id
            else
                local metier = MetierDeRecette(id, nom, i, cls, sub)
                if metier then recettes[#recettes + 1] = { id = id, nom = nom, metier = metier } end
            end
        end
    end
    return composants, recettes, objets, n, sansLien
end

-- Ajoute à la fiche existante les composants/recettes pas encore connus ; retourne le nombre d'ajouts
local function Fusionner(entree, composants, recettes)
    entree.composants = entree.composants or {}
    entree.recettes = entree.recettes or {}
    local ajouts = 0
    local connus = {}
    for _, id in ipairs(entree.composants) do connus[id] = true end
    for _, id in ipairs(composants) do
        if not connus[id] then
            entree.composants[#entree.composants + 1] = id
            connus[id] = true
            ajouts = ajouts + 1
        end
    end
    local connues = {}
    for _, r in ipairs(entree.recettes) do connues[r.id] = true end
    for _, r in ipairs(recettes) do
        if not connues[r.id] then
            entree.recettes[#entree.recettes + 1] = r
            connues[r.id] = true
            ajouts = ajouts + 1
        end
    end
    return ajouts
end

local function Enregistrer(origine)
    local guid = UnitGUID("npc")
    if not guid then return end
    local nom = UnitName("npc")
    local npcId = LireNpcId(guid)
    local cle = npcId or nom
    if not cle then return end
    if not (GetMerchantNumItems and GetMerchantItemLink) then return end

    local composants, recettes, objets, n, sansLien = Scanner()

    if debugActif then
        CuisineMarchandsDB._debug = CuisineMarchandsDB._debug or {}
        CuisineMarchandsDB._debug[tostring(cle) .. "@" .. origine] = {
            nom = nom, nbObjets = n, sansLien = sansLien, objets = objets,
        }
        Print(string.format("[debug %s] %s : %d objets, %d sans lien, %d composant(s), %d recette(s)",
            origine, nom or "?", n, sansLien, #composants, #recettes))
    end

    if #composants == 0 and #recettes == 0 then return end

    -- Position du joueur (proche du marchand pendant l'échange)
    local mapID, x, y
    if C_Map and C_Map.GetBestMapForUnit then
        mapID = C_Map.GetBestMapForUnit("player")
    end
    if mapID and C_Map.GetPlayerMapPosition then
        local pos = C_Map.GetPlayerMapPosition(mapID, "player")
        if pos then
            x, y = pos:GetXY()
        end
    end

    local entree = CuisineMarchandsDB[cle]
    local nouveau = (entree == nil)
    if nouveau then
        entree = { composants = {}, recettes = {} }
        CuisineMarchandsDB[cle] = entree
    end
    entree.nom = nom
    entree.npcId = npcId
    entree.zone = GetRealZoneText()
    entree.mapID = mapID
    entree.x = x and Arrondi(x) or entree.x
    entree.y = y and Arrondi(y) or entree.y

    local ajouts = Fusionner(entree, composants, recettes)
    if nouveau or ajouts > 0 then
        Print(string.format("Marchand enregistré : %s (%s %s, %s) - %d composant(s), %d recette(s)",
            nom or "?", entree.zone or "?", entree.x or "?", entree.y or "?",
            #entree.composants, #entree.recettes))
    end
end

local function EnregistrerSur(origine)
    local ok, err = pcall(Enregistrer, origine)
    if not ok then
        Print("Erreur : " .. tostring(err))
    end
end


-- =====================================================================
-- FAVORIS : étoile dans la fenêtre du marchand + icônes carte / minimap
-- =====================================================================
local TEX_ETOILE = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"  -- icône n°1 = étoile jaune
local COORD_ETOILE = { 0, 0.25, 0, 0.25 }
-- Icône affichée sur la carte, la minimap et au-dessus du PNJ : la bourse du marchand (l'étoile reste dans sa fenêtre)
local TEX_BOURSE = "Interface\\GossipFrame\\VendorGossipIcon"
-- Professeurs de métier : le livre (icône de dialogue des instructeurs)
local TEX_LIVRE = "Interface\\GossipFrame\\TrainerGossipIcon"
local PREFIXE_PROF = "prof:"

local function EstProf(fav) return type(fav) == "table" and fav.type == "prof" end
local function TexFav(fav) return EstProf(fav) and TEX_LIVRE or TEX_BOURSE end

local function Favoris()
    CuisineMarchandsDB._favoris = CuisineMarchandsDB._favoris or {}
    return CuisineMarchandsDB._favoris
end

-- Clé du PNJ ouvert : l'id (ou le nom) pour un marchand ; "prof:" + id pour un professeur
local function CleMarchandOuvert(prof)
    local guid = UnitGUID("npc")
    if not guid then return nil end
    local nom = UnitName("npc")
    local npcId = LireNpcId(guid)
    local cle = npcId or nom
    if prof and cle then cle = PREFIXE_PROF .. tostring(cle) end
    return cle, nom, npcId
end

-- Position du joueur : mapID et coordonnées en fraction 0-1
local function PositionJoueur()
    local mapID, x, y
    if C_Map and C_Map.GetBestMapForUnit then
        mapID = C_Map.GetBestMapForUnit("player")
    end
    if mapID and C_Map.GetPlayerMapPosition then
        local pos = C_Map.GetPlayerMapPosition(mapID, "player")
        if pos then
            x, y = pos:GetXY()
        end
    end
    return mapID, x, y
end

local function TexteComposants(cle)
    local m = CuisineMarchandsDB[cle]
    if type(m) ~= "table" or not m.composants then return nil end
    local noms = {}
    for _, id in ipairs(m.composants) do
        noms[#noms + 1] = NomComposant(id)
    end
    if #noms == 0 then return nil end
    return table.concat(noms, ", ")
end

local function InfoBulleFavori(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local prof = EstProf(self.fav)
    GameTooltip:SetText((self.fav and self.fav.nom) or (prof and "Professeur" or "Marchand"))
    GameTooltip:AddLine(prof and "Professeur favori" or "Marchand favori", 1, 0.82, 0)
    if prof and self.fav.metier then GameTooltip:AddLine("Métier : " .. self.fav.metier, 1, 1, 1) end
    local t = TexteComposants(self.cle)
    if t then GameTooltip:AddLine(t, 0.8, 0.8, 0.8, true) end
    GameTooltip:Show()
end

local function ObtenirPin(pool, cle, parent, taille, souris, fav)
    local p = pool[cle]
    if not p then
        p = CreateFrame("Frame", nil, parent)
        p:SetSize(taille, taille)
        p.tex = p:CreateTexture(nil, "OVERLAY")
        p.tex:SetAllPoints()
        p.tex:SetTexture(TEX_BOURSE)
        if souris then
            p:EnableMouse(true)
            p:SetScript("OnEnter", InfoBulleFavori)
            p:SetScript("OnLeave", function() GameTooltip:Hide() end)
        else
            p:EnableMouse(false)  -- ne bloque pas les clics sur la minimap
        end
        pool[cle] = p
    end
    p.tex:SetTexture(TexFav(fav))
    return p
end

-- ---------- Carte du monde ----------
local pinsCarte = {}
local etatCarte = { affiches = 0, favs = {} }
local erreurCarte = nil
local carteTest = nil
local TAILLE_PIN_CARTE = 24

-- Cadre sur lequel poser les icônes : le canevas de la carte moderne, sinon les cadres de l'ancienne carte
local function ParentCarte()
    if WorldMapFrame then
        if WorldMapFrame.GetCanvas then
            local ok, canvas = pcall(WorldMapFrame.GetCanvas, WorldMapFrame)
            if ok and canvas then return canvas, "GetCanvas" end
        end
        local sc = WorldMapFrame.ScrollContainer
        if sc and sc.Child then return sc.Child, "ScrollContainer.Child" end
    end
    if WorldMapDetailFrame then return WorldMapDetailFrame, "WorldMapDetailFrame" end
    if WorldMapButton then return WorldMapButton, "WorldMapButton" end
    return nil, "aucun"
end

local function MapIDAffichee()
    if WorldMapFrame and WorldMapFrame.GetMapID then
        local ok, id = pcall(WorldMapFrame.GetMapID, WorldMapFrame)
        if ok and type(id) == "number" then return id end
    end
    return nil
end

-- Position (0-1) d'un favori sur la carte affichée : directe si c'est sa carte, sinon convertie via le monde
-- (le favori apparaît alors aussi sur la carte du continent)
local function PositionSurCarte(fav, mapID)
    if fav.mapID == mapID then return fav.x / 100, fav.y / 100, "directe" end
    if C_Map and C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos and CreateVector2D then
        local ok, x, y = pcall(function()
            local cont, wpos = C_Map.GetWorldPosFromMapPos(fav.mapID, CreateVector2D(fav.x / 100, fav.y / 100))
            if not (cont and wpos) then return nil end
            local _, mpos = C_Map.GetMapPosFromWorldPos(cont, wpos, mapID)
            if not mpos then return nil end
            if mpos.GetXY then return mpos:GetXY() end
            return mpos.x, mpos.y
        end)
        if ok and type(x) == "number" and type(y) == "number" and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
            return x, y, "convertie"
        end
    end
    return nil
end

local function RafraichirCarte()
    for _, p in pairs(pinsCarte) do p:Hide() end
    etatCarte.affiches = 0
    etatCarte.favs = {}
    local canvas, methode = ParentCarte()
    etatCarte.parent = methode
    if not canvas then return end
    local mapID = MapIDAffichee()
    etatCarte.mapID = mapID
    -- Taille du canevas : si le jeu ne l'a pas encore calculée (ouverture de la carte), taille par défaut
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    if type(w) ~= "number" or w < 1 then w = 1002 end
    if type(h) ~= "number" or h < 1 then h = 668 end
    -- Taille constante à l'écran quel que soit le zoom de la carte
    local k = 1
    local ec = canvas.GetEffectiveScale and canvas:GetEffectiveScale()
    local eu = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()
    if type(ec) == "number" and type(eu) == "number" and ec > 0 then k = eu / ec end
    if not mapID then return end
    for cle, fav in pairs(Favoris()) do
        local e = {}
        etatCarte.favs[cle] = e
        if not (fav.x and fav.y and fav.mapID) then
            e.raison = "favori sans position"
        else
            local fx, fy, mode = PositionSurCarte(fav, mapID)
            if not fx then
                e.raison = "hors de la carte affichée (" .. tostring(mapID) .. ")"
            else
                local p = ObtenirPin(pinsCarte, cle, canvas, TAILLE_PIN_CARTE, true, fav)
                if p:GetParent() ~= canvas then p:SetParent(canvas) end
                p.fav, p.cle = fav, cle
                p:SetFrameStrata("FULLSCREEN_DIALOG")
                p:SetFrameLevel(200)
                p:SetSize(TAILLE_PIN_CARTE * k, TAILLE_PIN_CARTE * k)
                p:ClearAllPoints()
                p:SetPoint("CENTER", canvas, "TOPLEFT", fx * w, -fy * h)
                p:Show()
                e.mode, e.fx, e.fy = mode, fx, fy
                etatCarte.affiches = etatCarte.affiches + 1
            end
        end
    end
end

local function RafraichirCarteSur()
    local ok, err = pcall(RafraichirCarte)
    if not ok and erreurCarte ~= tostring(err) then
        erreurCarte = tostring(err)
        Print("Carte : erreur (" .. erreurCarte .. ")")
    end
    return ok
end

local function InstallerHooksCarte()
    if not WorldMapFrame then return end
    if WorldMapFrame.HookScript then
        pcall(WorldMapFrame.HookScript, WorldMapFrame, "OnShow", RafraichirCarteSur)
        pcall(WorldMapFrame.HookScript, WorldMapFrame, "OnSizeChanged", RafraichirCarteSur)
    end
    if hooksecurefunc and WorldMapFrame.OnMapChanged then
        pcall(hooksecurefunc, WorldMapFrame, "OnMapChanged", RafraichirCarteSur)
    end
end

-- Rafraîchissement régulier tant que la carte est ouverte : la taille du canevas n'est pas toujours
-- connue à l'ouverture, et la carte affichée change quand on navigue dedans.
local carteFrame = CreateFrame("Frame")
local cumulCarte = 0
carteFrame:SetScript("OnUpdate", function(_, elapsed)
    cumulCarte = cumulCarte + (elapsed or 0)
    if cumulCarte < 0.25 then return end
    cumulCarte = 0
    if WorldMapFrame and WorldMapFrame.IsShown and WorldMapFrame:IsShown() then
        RafraichirCarteSur()
    end
end)

-- Carré vert au centre de la carte pour vérifier que le cadre choisi est bien visible
local function TesterCarte()
    local canvas = ParentCarte()
    if not canvas then Print("Carte : aucun cadre trouvé.") return end
    if not carteTest then
        carteTest = CreateFrame("Frame", nil, canvas)
        carteTest.tex = carteTest:CreateTexture(nil, "OVERLAY")
        carteTest.tex:SetAllPoints()
        if carteTest.tex.SetColorTexture then carteTest.tex:SetColorTexture(0, 1, 0, 0.8) end
    end
    carteTest:SetParent(canvas)
    carteTest:SetFrameStrata("FULLSCREEN_DIALOG")
    carteTest:SetFrameLevel(300)
    carteTest:SetSize(40, 40)
    carteTest:ClearAllPoints()
    carteTest:SetPoint("CENTER", canvas, "CENTER", 0, 0)
    carteTest:Show()
    if C_Timer and C_Timer.After then
        C_Timer.After(8, function() if carteTest then carteTest:Hide() end end)
    end
    Print("Ouvre la carte du monde : un carré vert doit apparaître au centre pendant 8 secondes.")
end

-- ---------- Plaque de nom du PNJ favori (étoile au-dessus de la tête) ----------
-- Une addon ne peut pas dessiner dans le monde 3D : l'étoile est posée sur la plaque de nom du PNJ.
-- Elle n'apparaît donc que si les plaques de nom des PNJ amicaux sont affichées (voir /cmarch plaques).
local etoilesPlaques = setmetatable({}, { __mode = "k" })
local TAILLE_PLAQUE = 26
local erreursVues = {}

local function SignalerErreur(contexte, err)
    local msg = contexte .. " : erreur (" .. tostring(err) .. ")"
    if not erreursVues[msg] then
        erreursVues[msg] = true
        Print(msg)
    end
end

local function PlaquePourUnite(unit)
    if C_NamePlate and C_NamePlate.GetNamePlateForUnit and unit then
        return C_NamePlate.GetNamePlateForUnit(unit)
    end
    return nil
end

-- Clé du favori correspondant à l'unité (id du PNJ, sinon son nom), nil si ce n'est pas un favori
local function CleFavoriUnite(unit)
    if not (unit and UnitExists(unit)) then return nil end
    if UnitIsPlayer and UnitIsPlayer(unit) then return nil end
    local favs = Favoris()
    local guid = UnitGUID(unit)
    local npcId = guid and LireNpcId(guid)
    if npcId and favs[npcId] then return npcId end
    local nom = UnitName(unit)
    if nom and favs[nom] then return nom end
    if npcId and favs[PREFIXE_PROF .. npcId] then return PREFIXE_PROF .. npcId end
    if nom and favs[PREFIXE_PROF .. nom] then return PREFIXE_PROF .. nom end
    return nil
end

local function EtoilePourPlaque(plaque, fav)
    local e = etoilesPlaques[plaque]
    if not e then
        e = CreateFrame("Frame", nil, plaque)
        e:SetSize(TAILLE_PLAQUE, TAILLE_PLAQUE)
        e:SetFrameLevel((plaque:GetFrameLevel() or 1) + 20)
        e:EnableMouse(false)
        e.tex = e:CreateTexture(nil, "OVERLAY")
        e.tex:SetAllPoints()
        e.tex:SetTexture(TEX_BOURSE)
        etoilesPlaques[plaque] = e
    end
    e.tex:SetTexture(TexFav(fav))
    -- Posée au-dessus du nom du PNJ (ou de la plaque si le nom n'est pas disponible)
    local uf = plaque.UnitFrame
    local ref = (uf and uf.name) or uf or plaque
    e:ClearAllPoints()
    e:SetPoint("BOTTOM", ref, "TOP", 0, 4)
    return e
end

local function MajPlaque(unit)
    local plaque = PlaquePourUnite(unit)
    if not plaque then return end
    local cleFav = CleFavoriUnite(unit)
    if cleFav then
        EtoilePourPlaque(plaque, Favoris()[cleFav]):Show()
    elseif etoilesPlaques[plaque] then
        etoilesPlaques[plaque]:Hide()
    end
end

local function RetirerPlaque(unit)
    local plaque = PlaquePourUnite(unit)
    if plaque and etoilesPlaques[plaque] then etoilesPlaques[plaque]:Hide() end
end

local function MajToutesPlaques()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
    for _, plaque in ipairs(C_NamePlate.GetNamePlates()) do
        local unit = plaque.namePlateUnitToken or (plaque.UnitFrame and plaque.UnitFrame.unit)
        if unit then MajPlaque(unit) end
    end
end

local function Texte(v)
    return tostring(v)
end

local function Nombre(v)
    return type(v) == "number" and tostring(math.floor(v + 0.5)) or "?"
end

-- ---------- Minimap ----------
-- Principe : on travaille dans le repère de la carte de la zone (la même que celle où le favori a été
-- enregistré). Décalage en yards = (position du favori - position du joueur) x taille de la carte en yards.
-- Aucune dépendance à UnitPosition ni à une calibration d'axes.

-- Diamètre visible de la minimap en yards selon le zoom (extérieur)
local TAILLE_MINIMAP = { [0] = 466.6667, [1] = 400, [2] = 333.3333, [3] = 266.6667, [4] = 200, [5] = 133.3333 }
local pinsMini = {}
local tailleCartes = {}   -- mapID -> { w = yards, h = yards, methode = "..." }
local etatMini = {}       -- dernier calcul par favori (pour /cmarch minimap)
local ticksMini = 0
local erreurMini = nil

-- Taille de la carte en yards : API directe, sinon déduite de la conversion carte -> monde
local function TailleCarte(mapID)
    local t = tailleCartes[mapID]
    if t then return t end
    if C_Map and C_Map.GetMapWorldSize then
        local w, h = C_Map.GetMapWorldSize(mapID)
        if type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then
            t = { w = w, h = h, methode = "GetMapWorldSize" }
        end
    end
    if not t and C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D then
        local _, v00 = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 0))
        local _, v10 = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(1, 0))
        local _, v01 = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 1))
        if v00 and v10 and v01 then
            local w = math.sqrt((v10.x - v00.x) ^ 2 + (v10.y - v00.y) ^ 2)
            local h = math.sqrt((v01.x - v00.x) ^ 2 + (v01.y - v00.y) ^ 2)
            if w > 0 and h > 0 then
                t = { w = w, h = h, methode = "GetWorldPosFromMapPos" }
            end
        end
    end
    if t then tailleCartes[mapID] = t end
    return t
end

local function MasquerMinimap()
    for _, p in pairs(pinsMini) do p:Hide() end
end

local function MajMinimap()
    ticksMini = ticksMini + 1
    local favs = Favoris()
    if next(favs) == nil then MasquerMinimap() return end
    if not Minimap then return end
    local mapID, px, py = PositionJoueur()
    if not (mapID and px and py) then
        for cle in pairs(favs) do etatMini[cle] = { raison = "position du joueur indisponible" } end
        MasquerMinimap()
        return
    end

    local zoom = Minimap:GetZoom() or 0
    local diam = TAILLE_MINIMAP[zoom] or TAILLE_MINIMAP[0]
    local largeur = Minimap:GetWidth()
    local rotation = GetCVar and GetCVar("rotateMinimap") == "1"
    local facing = (rotation and GetPlayerFacing and GetPlayerFacing()) or 0
    local cosf, sinf = math.cos(facing), math.sin(facing)

    for cle, fav in pairs(favs) do
        local p = pinsMini[cle]
        local etat = { }
        local visible = false
        if not (fav.x and fav.y) then
            etat.raison = "favori sans position"
        elseif fav.mapID ~= mapID then
            etat.raison = "autre carte (joueur " .. tostring(mapID) .. " / favori " .. tostring(fav.mapID) .. ")"
        else
            local t = TailleCarte(mapID)
            if not t then
                etat.raison = "taille de carte indisponible"
            else
                local sx = (fav.x / 100 - px) * t.w      -- vers l'est = vers la droite
                local sy = -(fav.y / 100 - py) * t.h     -- vers le nord = vers le haut
                if rotation then
                    sx, sy = sx * cosf + sy * sinf, -sx * sinf + sy * cosf
                end
                local dist = math.sqrt(sx * sx + sy * sy)
                etat.sx, etat.sy, etat.dist, etat.diam = sx, sy, dist, diam
                if dist <= diam / 2 * 0.92 then
                    p = p or ObtenirPin(pinsMini, cle, Minimap, 16, false, fav)
                    p:ClearAllPoints()
                    p:SetPoint("CENTER", Minimap, "CENTER", sx / diam * largeur, sy / diam * largeur)
                    p:SetFrameStrata("HIGH")
                    p:SetFrameLevel(Minimap:GetFrameLevel() + 20)
                    p:Show()
                    visible = true
                else
                    etat.raison = "hors de portée de la minimap"
                end
            end
        end
        etat.visible = visible
        etatMini[cle] = etat
        if p and not visible then p:Hide() end
    end
    -- pins de favoris supprimés
    for cle, p in pairs(pinsMini) do
        if not favs[cle] then p:Hide() end
    end
end

local majFrame = CreateFrame("Frame")
local cumul = 0
majFrame:SetScript("OnUpdate", function(_, elapsed)
    cumul = cumul + (elapsed or 0)
    if cumul < 0.1 then return end
    cumul = 0
    local ok, err = pcall(MajMinimap)
    if not ok then
        if erreurMini ~= tostring(err) then
            erreurMini = tostring(err)
            Print("Minimap : erreur (" .. erreurMini .. ")")
        end
    end
end)

local function DiagnosticMinimap()
    local mapID, px, py = PositionJoueur()
    Print(string.format("Joueur : carte %s, position %s / %s", tostring(mapID),
        px and Arrondi(px) or "?", py and Arrondi(py) or "?"))
    local t = mapID and TailleCarte(mapID)
    if t then
        Print(string.format("Taille de la carte : %s x %s yards (méthode : %s)", Nombre(t.w),
            Nombre(t.h), t.methode))
    else
        Print("Taille de la carte : INDISPONIBLE (C_Map.GetMapWorldSize absent ou nul)")
    end
    local zoom = Minimap and Minimap:GetZoom()
    Print(string.format("Minimap : zoom=%s diamètre=%s yards, largeur=%s px, rotation=%s",
        tostring(zoom), tostring(TAILLE_MINIMAP[zoom or 0]), tostring(Minimap and Minimap:GetWidth()),
        tostring(GetCVar and GetCVar("rotateMinimap"))))
    Print(string.format("Rafraîchissements effectués : %d, dernière erreur : %s", ticksMini, tostring(erreurMini)))
    local n = 0
    for cle, fav in pairs(Favoris()) do
        n = n + 1
        local e = etatMini[cle] or {}
        local p = pinsMini[cle]
        Print(string.format("* %s (carte %s, %s / %s) : visible=%s, décalage=%s/%s yards, distance=%s%s, icône créée=%s",
            fav.nom or "?", tostring(fav.mapID), tostring(fav.x), tostring(fav.y), tostring(e.visible),
            e.sx and tostring(math.floor(e.sx + 0.5)) or "?", e.sy and tostring(math.floor(e.sy + 0.5)) or "?",
            e.dist and tostring(math.floor(e.dist + 0.5)) or "?", e.raison and (", raison : " .. e.raison) or "",
            tostring(p ~= nil)))
    end
    if n == 0 then Print("Aucun favori.") end
end

-- ---------- Diagnostics carte du monde et plaques de nom ----------
local function DiagnosticCarte()
    Print("WorldMapFrame : " .. (WorldMapFrame and "présent" or "ABSENT"))
    local canvas, methode = ParentCarte()
    Print("Cadre de la carte : " .. (canvas and methode or "INTROUVABLE"))
    Print(string.format("Carte ouverte : %s, carte affichée : %s",
        Texte(WorldMapFrame and WorldMapFrame.IsShown and WorldMapFrame:IsShown()), Texte(MapIDAffichee())))
    if canvas then
        Print(string.format("Canevas : %s x %s, échelle=%s (interface : %s), niveau=%s",
            Nombre(canvas:GetWidth()), Nombre(canvas:GetHeight()), Texte(canvas:GetEffectiveScale()),
            Texte(UIParent and UIParent:GetEffectiveScale()), Texte(canvas:GetFrameLevel())))
    end
    Print(string.format("Dernier rafraîchissement : %s icône(s) affichée(s), dernière erreur : %s",
        Texte(etatCarte.affiches), Texte(erreurCarte)))
    local n = 0
    for cle, fav in pairs(Favoris()) do
        n = n + 1
        local e = (etatCarte.favs or {})[cle] or {}
        local p = pinsCarte[cle]
        Print(string.format("* %s : carte du favori %s (%s / %s) -> %s%s, icône créée=%s, visible=%s",
            fav.nom or "?", Texte(fav.mapID), Texte(fav.x), Texte(fav.y), e.mode or "non affichée",
            e.raison and (" (" .. e.raison .. ")") or "", Texte(p ~= nil), Texte(p and p:IsVisible())))
    end
    if n == 0 then Print("Aucun favori.") end
    Print("Ouvre la carte avant ce diagnostic. /cmarch carte test affiche un carré vert au centre de la carte.")
end

local function CVarTexte(nom)
    if not GetCVar then return "?" end
    local ok, v = pcall(GetCVar, nom)
    return (ok and v ~= nil) and tostring(v) or "?"
end

local function DiagnosticPlaques()
    local api = C_NamePlate and C_NamePlate.GetNamePlates
    Print("Plaques de nom : API " .. (api and "présente" or "ABSENTE"))
    Print(string.format("Réglages : PNJ amicaux=%s, joueurs amicaux=%s, toutes=%s, distance=%s",
        CVarTexte("nameplateShowFriendlyNPCs"), CVarTexte("nameplateShowFriends"),
        CVarTexte("nameplateShowAll"), CVarTexte("nameplateMaxDistance")))
    local plaques = api and C_NamePlate.GetNamePlates() or {}
    Print(#plaques .. " plaque(s) affichée(s) autour de toi.")
    for _, plaque in ipairs(plaques) do
        local unit = plaque.namePlateUnitToken or (plaque.UnitFrame and plaque.UnitFrame.unit)
        local e = etoilesPlaques[plaque]
        Print(string.format("* %s : favori=%s, étoile visible=%s", unit and UnitName(unit) or "?",
            Texte(unit and CleFavoriUnite(unit) ~= nil), Texte(e and e:IsVisible() or false)))
    end
    Print("Si tes marchands favoris n'ont pas de plaque : /cmarch plaques on active les plaques des PNJ amicaux.")
end

-- Active (ou rétablit) l'affichage des plaques de nom des PNJ amicaux
local function ReglerPlaques(actif)
    CuisineMarchandsDB._reglages = CuisineMarchandsDB._reglages or {}
    local r = CuisineMarchandsDB._reglages
    if actif then
        if r.plaquesAvant == nil then r.plaquesAvant = CVarTexte("nameplateShowFriendlyNPCs") end
        local ok = SetCVar and pcall(SetCVar, "nameplateShowFriendlyNPCs", "1")
        Print(ok and "Plaques des PNJ amicaux activées. Si tu n'en vois toujours pas, vérifie les options d'interface (noms / plaques de nom)."
            or "Impossible de modifier ce réglage maintenant (en combat ?). Réessaie, ou active-le dans les options d'interface.")
    else
        local avant = r.plaquesAvant
        if avant == nil or avant == "?" then avant = "0" end
        local ok = SetCVar and pcall(SetCVar, "nameplateShowFriendlyNPCs", avant)
        r.plaquesAvant = nil
        Print(ok and ("Plaques des PNJ amicaux rétablies (" .. avant .. ").") or "Impossible de modifier ce réglage maintenant.")
    end
    pcall(MajToutesPlaques)
end

-- ---------- Étoile dans la fenêtre du marchand ----------
local etoile

local function MajEtoile()
    if not etoile then return end
    local cle = CleMarchandOuvert()
    local actif = (cle ~= nil) and (Favoris()[cle] ~= nil)
    etoile.actif = actif
    if actif then
        etoile.tex:SetDesaturated(false)
        etoile.tex:SetAlpha(1)
    else
        etoile.tex:SetDesaturated(true)  -- étoile "vide" : grise et translucide
        etoile.tex:SetAlpha(0.5)
    end
end

-- Métier enseigné par le professeur ouvert : lu dans ses services (métier requis, sinon nom du service),
-- comparé aux métiers de ParcoursData ; à défaut, le nom du métier requis tel que le jeu l'affiche.
local function MetierDuProfesseur()
    local n = 0
    if GetNumTrainerServices then n = GetNumTrainerServices() or 0
    elseif C_TrainerUI and C_TrainerUI.GetNumTrainerServices then n = C_TrainerUI.GetNumTrainerServices() or 0 end
    local textes, brut = {}, nil
    for i = 1, math.min(n, 40) do
        local nomService
        if GetTrainerServiceInfo then nomService = GetTrainerServiceInfo(i) end
        if type(nomService) == "table" then nomService = nomService.name end
        if type(nomService) == "string" then textes[#textes + 1] = nomService end
        if GetTrainerServiceSkillReq then
            local okR, skill = pcall(GetTrainerServiceSkillReq, i)
            if okR and type(skill) == "string" and skill ~= "" then
                textes[#textes + 1] = skill
                brut = brut or skill
            end
        end
    end
    local data = ParcoursData
    if data and data.metiers then
        for _, id in ipairs(data.ordre or {}) do
            local m = data.metiers[id]
            if m then
                local mots = m.motsClient or {}
                for _, t in ipairs(textes) do
                    if LigneMentionne(t, mots) then return m.nom or id end
                end
            end
        end
    end
    return brut
end

local livre   -- bouton favori de la fenêtre des professeurs

local function MajLivre()
    if not livre then return end
    local cle = CleMarchandOuvert(true)
    local actif = (cle ~= nil) and (Favoris()[cle] ~= nil)
    livre.actif = actif
    livre.tex:SetDesaturated(not actif)
    livre.tex:SetAlpha(actif and 1 or 0.5)
end

local function BasculerFavori(prof)
    local cle, nom, npcId = CleMarchandOuvert(prof)
    if not cle then return end
    local favs = Favoris()
    if favs[cle] then
        favs[cle] = nil
        Print((prof and "Professeur retiré des favoris : " or "Favori retiré : ") .. (nom or "?"))
    else
        local mapID, x, y = PositionJoueur()
        if not (mapID and x and y) then
            Print("Position indisponible ici : favori non ajouté.")
            return
        end
        favs[cle] = { nom = nom, npcId = npcId, mapID = mapID, x = Arrondi(x), y = Arrondi(y), zone = GetRealZoneText(),
            type = prof and "prof" or nil }
        if prof then
            local ok, metier = pcall(MetierDuProfesseur)
            if ok and metier then favs[cle].metier = metier end
        end
        Print((prof and "Professeur ajouté aux favoris : " or "Favori ajouté : ") .. (nom or "?")
            .. ((prof and favs[cle].metier) and (" (" .. favs[cle].metier .. ")") or ""))
    end
    MajEtoile()
    MajLivre()
    RafraichirCarteSur()
    pcall(MajMinimap)
    pcall(MajToutesPlaques)
end

local function Reglages()
    CuisineMarchandsDB._reglages = CuisineMarchandsDB._reglages or {}
    return CuisineMarchandsDB._reglages
end

-- Deux ancrages possibles : à gauche du bouton fermer ("bouton") ou dans le coin du cadre ("cadre")
local function AppliquerAncre()
    if not etoile then return end
    etoile:ClearAllPoints()
    if Reglages().ancre == "cadre" or not MerchantFrameCloseButton then
        etoile:SetPoint("TOPRIGHT", MerchantFrame, "TOPRIGHT", -70, -14)
    else
        etoile:SetPoint("RIGHT", MerchantFrameCloseButton, "LEFT", 2, 0)
    end
end

local function CreerEtoile()
    if etoile or not MerchantFrame then return end
    etoile = CreateFrame("Button", "CuisineMarchandsEtoile", MerchantFrame)
    etoile:SetSize(22, 22)
    etoile:SetFrameStrata("HIGH")
    etoile:SetFrameLevel(MerchantFrame:GetFrameLevel() + 10)
    etoile.tex = etoile:CreateTexture(nil, "ARTWORK")
    etoile.tex:SetAllPoints()
    etoile.tex:SetTexture(TEX_ETOILE)
    etoile.tex:SetTexCoord(COORD_ETOILE[1], COORD_ETOILE[2], COORD_ETOILE[3], COORD_ETOILE[4])
    etoile:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    etoile:SetScript("OnClick", function()
        local ok, err = pcall(BasculerFavori, false)
        if not ok then Print("Erreur favori : " .. tostring(err)) end
    end)
    etoile:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.actif and "Retirer des favoris" or "Ajouter aux favoris")
        GameTooltip:Show()
    end)
    etoile:SetScript("OnLeave", function() GameTooltip:Hide() end)
    AppliquerAncre()
    etoile:Show()
    MajEtoile()
end

-- Affiche l'état de l'étoile pour comprendre pourquoi elle n'apparaît pas
local function DiagnosticEtoile()
    Print("MerchantFrame : " .. (MerchantFrame and "présent" or "ABSENT"))
    Print("Bouton fermer : " .. (MerchantFrameCloseButton and "présent" or "absent"))
    Print("Ancrage choisi : " .. ((Reglages().ancre == "cadre") and "cadre" or "bouton"))
    if not etoile then
        local ok, err = pcall(CreerEtoile)
        if not ok then Print("Création de l'étoile : ERREUR " .. tostring(err)) end
    end
    if not etoile then
        Print("Étoile : non créée.")
        return
    end
    Print(string.format("Étoile : affichée=%s visible=%s taille=%sx%s gauche=%s haut=%s strate=%s niveau=%s",
        Texte(etoile:IsShown()), Texte(etoile:IsVisible()),
        Nombre(etoile:GetWidth()), Nombre(etoile:GetHeight()),
        Nombre(etoile:GetLeft()), Nombre(etoile:GetTop()),
        Texte(etoile:GetFrameStrata()), Texte(etoile:GetFrameLevel())))
    if MerchantFrame then
        Print(string.format("Fenêtre marchand : visible=%s gauche=%s haut=%s droite=%s",
            Texte(MerchantFrame:IsVisible()), Nombre(MerchantFrame:GetLeft()),
            Nombre(MerchantFrame:GetTop()), Nombre(MerchantFrame:GetRight())))
    end
end

-- Fait apparaître un carré vert derrière l'étoile pendant 6 secondes pour la repérer
local function RepererEtoile()
    if not etoile then pcall(CreerEtoile) end
    if not etoile then Print("Étoile non créée.") return end
    if type(etoile.fond) ~= "table" and etoile.CreateTexture then
        etoile.fond = etoile:CreateTexture(nil, "BACKGROUND")
        etoile.fond:SetAllPoints()
        if etoile.fond.SetColorTexture then etoile.fond:SetColorTexture(0, 1, 0, 0.7) end
    end
    if type(etoile.fond) == "table" then
        etoile.fond:Show()
        if C_Timer and C_Timer.After then
            C_Timer.After(6, function() if type(etoile.fond) == "table" then etoile.fond:Hide() end end)
        end
    end
    Print("Ouvre un marchand : un carré vert doit apparaître derrière l'étoile pendant 6 secondes.")
end

-- ---------- Livre dans la fenêtre du professeur ----------
local CADRES_PROF = { "ClassTrainerFrame", "ProfessionTrainerFrame", "TrainerFrame" }

local function CadreProf()
    for _, nom in ipairs(CADRES_PROF) do
        local fr = _G[nom]
        if fr then return fr, nom end
    end
    return nil
end

local function CreerLivre()
    if livre then return true end
    local cadre, nom = CadreProf()
    if not cadre then return false end
    livre = CreateFrame("Button", "CuisineMarchandsLivre", cadre)
    livre:SetSize(22, 22)
    livre:SetFrameStrata("HIGH")
    livre:SetFrameLevel(cadre:GetFrameLevel() + 10)
    livre.tex = livre:CreateTexture(nil, "ARTWORK")
    livre.tex:SetAllPoints()
    livre.tex:SetTexture(TEX_ETOILE)  -- étoile dans la fenêtre ; le livre reste l'icône des cartes
    livre.tex:SetTexCoord(COORD_ETOILE[1], COORD_ETOILE[2], COORD_ETOILE[3], COORD_ETOILE[4])
    livre:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    -- à gauche du bouton fermer s'il existe, sinon dans le coin du cadre
    local fermer = cadre.CloseButton or _G[nom .. "CloseButton"]
    if fermer then
        livre:SetPoint("RIGHT", fermer, "LEFT", -4, 0)
    else
        livre:SetPoint("TOPRIGHT", cadre, "TOPRIGHT", -34, -6)
    end
    livre:SetScript("OnClick", function()
        local ok, err = pcall(BasculerFavori, true)
        if not ok then Print("Erreur favori : " .. tostring(err)) end
    end)
    livre:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.actif and "Retirer des professeurs favoris" or "Ajouter aux professeurs favoris")
        GameTooltip:Show()
    end)
    livre:SetScript("OnLeave", function() GameTooltip:Hide() end)
    livre:Show()
    MajLivre()
    return true
end

-- La fenêtre du professeur se charge à la demande : on réessaie brièvement
local function PrepareLivre(essai)
    local ok, res = pcall(CreerLivre)
    if not ok then Print("Livre : erreur à la création (" .. tostring(res) .. ")") return end
    if res then
        pcall(MajLivre)
    elseif (essai or 0) < 5 and C_Timer and C_Timer.After then
        C_Timer.After(0.2, function() PrepareLivre((essai or 0) + 1) end)
    end
end

local function DiagnosticLivre()
    local cadre, nom = CadreProf()
    Print("Fenêtre du professeur : " .. (cadre and nom or "ABSENTE (ouvre un professeur d'abord)"))
    if cadre and not livre then pcall(CreerLivre) end
    if livre then
        Print(string.format("Livre : affiché=%s visible=%s gauche=%s haut=%s",
            Texte(livre:IsShown()), Texte(livre:IsVisible()), Nombre(livre:GetLeft()), Nombre(livre:GetTop())))
    else
        Print("Livre : non créé.")
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("MERCHANT_SHOW")
f:RegisterEvent("MERCHANT_UPDATE")
f:RegisterEvent("TRAINER_SHOW")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LOGIN" then
        Print("v0.6 chargé. Commandes : /cmarch (liste), favoris, reset, debug, etoile, minimap, carte, plaques (diagnostics).")
        local okE, errE = pcall(CreerEtoile)
        if not okE then Print("Étoile : erreur à la création (" .. tostring(errE) .. ")") end
        pcall(InstallerHooksCarte)
        RafraichirCarteSur()
        pcall(f.RegisterEvent, f, "NAME_PLATE_UNIT_ADDED")
        pcall(f.RegisterEvent, f, "NAME_PLATE_UNIT_REMOVED")
    elseif event == "MERCHANT_SHOW" then
        if not etoile then
            local okE, errE = pcall(CreerEtoile)
            if not okE then Print("Étoile : erreur à la création (" .. tostring(errE) .. ")") end
        end
        pcall(MajEtoile)
        EnregistrerSur("show")
        -- Les données des objets peuvent arriver avec un léger retard : nouveaux scans
        if C_Timer and C_Timer.After then
            C_Timer.After(0.7, function() EnregistrerSur("t1") end)
            C_Timer.After(2, function() EnregistrerSur("t2") end)
        end
    elseif event == "TRAINER_SHOW" then
        PrepareLivre(0)
    elseif event == "ADDON_LOADED" then
        if arg1 == "Blizzard_TrainerUI" then PrepareLivre(0) end
    elseif event == "MERCHANT_UPDATE" then
        EnregistrerSur("update")
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        local ok, err = pcall(MajPlaque, arg1)
        if not ok then SignalerErreur("Plaques", err) end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local ok, err = pcall(RetirerPlaque, arg1)
        if not ok then SignalerErreur("Plaques", err) end
    end
end)

SLASH_CUISINEMARCHANDS1 = "/cmarch"
SLASH_CUISINEMARCHANDS2 = "/cuisinemarchands"
SlashCmdList["CUISINEMARCHANDS"] = function(arg)
    arg = (arg or ""):lower()
    if arg == "reset" then
        local fav = CuisineMarchandsDB._favoris
        CuisineMarchandsDB = { _favoris = fav }
        Print("Marchands vidés (les favoris sont conservés ; /cmarch reset favoris pour les effacer).")
        return
    end
    if arg == "reset favoris" then
        CuisineMarchandsDB._favoris = {}
        MajEtoile()
        RafraichirCarteSur()
        pcall(MajMinimap)
        pcall(MajToutesPlaques)
        Print("Favoris effacés.")
        return
    end
    if arg == "professeur" or arg == "livre" then
        local ok, err = pcall(DiagnosticLivre)
        if not ok then Print("Diagnostic livre : erreur (" .. tostring(err) .. ")") end
        return
    end
    if arg == "etoile" then
        local ok, err = pcall(DiagnosticEtoile)
        if not ok then Print("Diagnostic : erreur (" .. tostring(err) .. ")") end
        return
    end
    if arg == "minimap" then
        local ok, err = pcall(DiagnosticMinimap)
        if not ok then Print("Diagnostic minimap : erreur (" .. tostring(err) .. ")") end
        return
    end
    if arg == "carte" then
        local ok, err = pcall(DiagnosticCarte)
        if not ok then Print("Diagnostic carte : erreur (" .. tostring(err) .. ")") end
        return
    end
    if arg == "carte test" then
        local ok, err = pcall(TesterCarte)
        if not ok then Print("Test carte : erreur (" .. tostring(err) .. ")") end
        return
    end
    if arg == "plaques" then
        local ok, err = pcall(DiagnosticPlaques)
        if not ok then Print("Diagnostic plaques : erreur (" .. tostring(err) .. ")") end
        return
    end
    if arg == "plaques on" or arg == "plaques off" then
        local ok, err = pcall(ReglerPlaques, arg == "plaques on")
        if not ok then Print("Plaques : erreur (" .. tostring(err) .. ")") end
        return
    end
    if arg == "etoile test" then
        local ok, err = pcall(RepererEtoile)
        if not ok then Print("Repérage : erreur (" .. tostring(err) .. ")") end
        return
    end
    if arg == "etoile ancre" then
        Reglages().ancre = (Reglages().ancre == "cadre") and "bouton" or "cadre"
        AppliquerAncre()
        Print("Ancrage de l'étoile : " .. Reglages().ancre .. ". Rouvre la fenêtre du marchand.")
        return
    end
    if arg == "favoris" then
        local n = 0
        for _, fav in pairs(Favoris()) do
            n = n + 1
            Print(string.format("* %s%s - %s (%s, %s)", EstProf(fav) and ("[Professeur" .. (fav.metier and (" " .. fav.metier) or "") .. "] ") or "", fav.nom or "?", fav.zone or "?", fav.x or "?", fav.y or "?"))
        end
        if n == 0 then Print("Aucun favori.") end
        return
    end
    if arg == "debug" then
        debugActif = not debugActif
        if debugActif then
            Print("Mode debug ACTIVÉ. Ouvre le marchand à tester, puis fais /reload : le détail de ses objets sera dans le fichier de données.")
        else
            Print("Mode debug désactivé.")
        end
        return
    end
    -- /cmarch [métier] : liste des marchands, filtrée par métier si un nom est donné
    local filtre = nil
    if arg ~= "" then
        for _, mt in ipairs(MetiersProduction()) do
            local cand = { mt.id:lower(), (mt.nom or ""):lower() }
            for _, w in ipairs(mt.mots) do cand[#cand + 1] = w:lower() end
            for _, c in ipairs(cand) do
                if c == arg or c:find(arg, 1, true) == 1 then filtre = mt; break end
            end
            if filtre then break end
        end
        if not filtre then
            local noms = {}
            for _, mt in ipairs(MetiersProduction()) do noms[#noms + 1] = mt.id end
            Print("Métier inconnu : " .. arg .. ". Métiers : " .. table.concat(noms, ", "))
            return
        end
    end
    local function NomMetier(id)
        for _, mt in ipairs(MetiersProduction()) do
            if mt.id == id then return mt.nom or id end
        end
        return id
    end
    local n = 0
    for cle, m in pairs(CuisineMarchandsDB) do
        if tostring(cle):sub(1, 1) ~= "_" and type(m) == "table" then
            local noms, rec = {}, {}
            for _, id in ipairs(m.composants or {}) do
                local pc = PlanComposants()[id]
                if not filtre or (pc and pc.metiers[filtre.id]) then
                    noms[#noms + 1] = NomComposant(id)
                end
            end
            for _, r in ipairs(m.recettes or {}) do
                local mid = r.metier or "cuisine"
                if not filtre or mid == filtre.id then
                    rec[#rec + 1] = (r.nom or r.id) .. (filtre and "" or (" [" .. NomMetier(mid) .. "]"))
                end
            end
            if #noms > 0 or #rec > 0 then
                n = n + 1
                Print(string.format("%s - %s (%s, %s)%s", m.nom or "?", m.zone or "?", m.x or "?", m.y or "?",
                    #noms > 0 and (" : " .. table.concat(noms, ", ")) or ""))
                if #rec > 0 then Print("   Recettes : " .. table.concat(rec, ", ")) end
            end
        end
    end
    if n == 0 then
        Print(filtre and ("Aucun marchand enregistré pour " .. NomMetier(filtre.id) .. ".")
            or "Aucun marchand enregistré. Ouvre la fenêtre d'un marchand.")
    end
end
