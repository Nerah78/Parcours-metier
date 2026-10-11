-- Parcours v0.8 : journal de progression par métier (1 à 300), activé selon les métiers appris.
-- Données : Donnees.lua (généré par generer_donnees.py : cuisine depuis le tableur, autres métiers depuis metiers/*.json).
-- Commandes : /parcours (alias /cparcours), niveau N, niveau auto, metier NOM, recolte, tous, etat, suivi, suivi reset, suivi debug,
--             recette connue|inconnue, icone, icone reset

ParcoursDB = ParcoursDB or {}
CuisineParcoursDB = CuisineParcoursDB or {}   -- ancienne variable sauvegardée (migrée au chargement)

local DATA = ParcoursData
local D   -- données du métier en cours de traitement (voir Utiliser)

local function Print(msg)
    print("|cffffd100Parcours|r " .. msg)
end

local COULEURS_RECETTE = {
    Orange = { 1.00, 0.50, 0.25 },
    Jaune  = { 1.00, 0.85, 0.00 },
    Vert   = { 0.35, 0.80, 0.35 },
}
local COULEUR_TERMINEE = { 0.40, 0.80, 0.40 }
local COULEUR_ENCOURS  = { 1.00, 0.82, 0.00 }
local COULEUR_AVENIR   = { 0.60, 0.60, 0.60 }
local COULEUR_OBJECTIF = { 0.90, 0.90, 0.90 }

-- ---------------------------------------------------------------------
-- Métiers : données, détection des métiers appris, base sauvegardée
-- ---------------------------------------------------------------------
local function Utiliser(id)
    D = DATA and DATA.metiers and DATA.metiers[id] or nil
    return D
end

local function DBM()
    ParcoursDB.metiers = ParcoursDB.metiers or {}
    ParcoursDB.metiers[D.id] = ParcoursDB.metiers[D.id] or {}
    return ParcoursDB.metiers[D.id]
end

-- Identifie un métier d'après le nom (localisé) d'une compétence
local function MetierDeNom(nom)
    if type(nom) ~= "string" or not (DATA and DATA.metiers) then return nil end
    nom = nom:lower()
    for _, id in ipairs(DATA.ordre or {}) do
        for _, mot in ipairs(DATA.metiers[id].motsClient or {}) do
            if nom:find(mot, 1, true) then return id end
        end
    end
    return nil
end

local function MetierDeLigne(ligneId)
    if not ligneId then return nil end
    for _, id in ipairs(DATA.ordre or {}) do
        if DATA.metiers[id].ligneId == ligneId then return id end
    end
    return nil
end

-- Retourne une table id -> rang pour les métiers appris, et un booléen « la détection a fonctionné »
local function MetiersAppris()
    local appris, api = {}, false
    if GetNumSkillLines and GetSkillLineInfo then
        local ok = pcall(function()
            for i = 1, GetNumSkillLines() do
                local nom, entete, _, rang = GetSkillLineInfo(i)
                if nom and not entete then
                    api = true
                    local id = MetierDeNom(nom)
                    if id and type(rang) == "number" then appris[id] = rang end
                end
            end
        end)
        if not ok then api = false end
    end
    if GetProfessions and GetProfessionInfo then
        pcall(function()
            local liste = { GetProfessions() }
            for i = 1, 6 do
                local idx = liste[i]
                if idx then
                    api = true
                    local nom, _, rang, _, _, _, ligne = GetProfessionInfo(idx)
                    local id = MetierDeLigne(ligne) or MetierDeNom(nom)
                    if id and type(rang) == "number" then appris[id] = rang end
                end
            end
        end)
    end
    return appris, api
end

-- Métiers de récolte (liste fixe, indépendante des données)
local METIERS_RECOLTE = { herboristerie = true, minage = true, depecage = true, peche = true }

-- Métiers à afficher : appris (ou niveau forcé à la main), sinon tous si la détection est impossible ou demandée
local function MetiersAffiches()
    local appris, api = MetiersAppris()
    local tous = ParcoursDB.afficherTous or not api
    local liste = {}
    for _, id in ipairs(DATA.ordre or {}) do
        local force = ParcoursDB.metiers and ParcoursDB.metiers[id] and ParcoursDB.metiers[id].niveauManuel
        -- métiers de récolte (herboristerie, minage, dépeçage, pêche) : masqués sauf option
        local masque = (DATA.metiers[id].recolte or METIERS_RECOLTE[id]) and not (ParcoursDB.afficherRecolte or ParcoursDB.afficherTous)
        if not masque and (tous or appris[id] or force) then liste[#liste + 1] = id end
    end
    return liste, appris
end

-- Niveau du métier en cours (D). Retourne niveau, origine
local function NiveauMetier()
    local manuel = DBM().niveauManuel
    if manuel then return manuel, "manuel" end
    local appris = MetiersAppris()
    if appris[D.id] then return appris[D.id], "détecté" end
    return nil, nil
end

-- Métier suivi par le suivi de quêtes (par défaut : le premier métier affiché)
local function MetierSuivi()
    local liste = MetiersAffiches()
    if ParcoursDB.metierSuivi then
        for _, id in ipairs(liste) do
            if id == ParcoursDB.metierSuivi then return id end
        end
    end
    return liste[1]
end

-- ---------------------------------------------------------------------
-- Noms localisés (le client est en français ; les données portent le nom anglais)
-- ---------------------------------------------------------------------
local function NomSort(id, defaut)
    if id then
        local ok, n = pcall(function()
            if GetSpellInfo then
                local r = GetSpellInfo(id)
                if type(r) == "table" then return r.name end
                return r
            end
            if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
        end)
        if ok and type(n) == "string" and n ~= "" then return n end
    end
    return defaut
end

local function NomObjet(id, defaut)
    if id then
        local ok, n = pcall(function()
            if GetItemInfo then
                local r = GetItemInfo(id)
                if type(r) == "table" then return r.name end
                return r
            end
            if C_Item and C_Item.GetItemNameByID then return C_Item.GetItemNameByID(id) end
        end)
        if ok and type(n) == "string" and n ~= "" then return n end
    end
    return defaut
end

-- Nom d'affichage de l'étape (recette, sorts de l'étape ou plage de compétence)
local function TitreQuete(q)
    if q.recette and (q.recette.sortId or q.recette.nom) then
        return NomSort(q.recette.sortId, q.recette.nom or q.titre) or "?"
    end
    if q.variantes then
        local noms = {}
        for _, v in ipairs(q.variantes) do
            noms[#noms + 1] = NomSort(v.sortId, v.nom) or "?"
        end
        if #noms > 0 then return table.concat(noms, ", ") end
    end
    return q.titre or "?"
end

-- ---------------------------------------------------------------------
-- Logique du parcours (sans interface, testable)
-- ---------------------------------------------------------------------
local function EtatQuete(q, niveau)
    if not niveau then return "inconnu" end
    if niveau >= q.fin then return "terminee" end
    if niveau >= q.debut then return "encours" end
    return "avenir"
end

local function QueteCourante(niveau)
    if not (D and D.quetes) then return nil end
    if not niveau then return 1 end
    for _, q in ipairs(D.quetes) do
        if EtatQuete(q, niveau) == "encours" then return q.n end
    end
    for _, q in ipairs(D.quetes) do
        if niveau < q.debut then return q.n end
    end
    return #D.quetes
end

-- Nombre de crafts restants (nil si l'étape n'est pas une fabrication)
local function CraftsRestants(q, niveau)
    if not q.crafts then return nil end
    if not niveau or niveau >= q.fin then return 0 end
    local depart = math.max(niveau, q.debut)
    if q.chance then
        return math.ceil((q.fin - depart) / q.chance)
    end
    local plage = q.fin - q.debut
    if plage <= 0 then return q.crafts end
    return math.ceil(q.crafts * (q.fin - depart) / plage)
end

local function CompterObjet(id)
    local fonction = GetItemCount or (C_Item and C_Item.GetItemCount)
    if not fonction or not id then return nil end
    local ok, n = pcall(fonction, id)
    if ok and type(n) == "number" then return n end
    return nil
end

-- ---------------------------------------------------------------------
-- Recettes apprises (lues dans la fenêtre du métier, ou message d'apprentissage). Ensemble commun à tous les métiers.
-- ---------------------------------------------------------------------
local function RecettesConnues()
    ParcoursDB.recettesConnues = ParcoursDB.recettesConnues or {}
    return ParcoursDB.recettesConnues
end

local function MarquerRecette(nom, connue)
    if not nom or nom == "" then return end
    RecettesConnues()[nom:lower()] = connue and true or nil
end

local function RecetteConnue(r)
    if not r then return false end
    local connues = RecettesConnues()
    if r.sortId then
        local n = NomSort(r.sortId, nil)
        if n and connues[n:lower()] then return true end
    end
    if r.nom and connues[r.nom:lower()] then return true end
    return false
end

-- Lit la liste des recettes quand une fenêtre de métier est ouverte. Retourne le nombre de recettes apprises lues.
local function ScannerMetier()
    local lues, idMetier = 0, nil
    if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeInfo then
        local ok, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs)
        if ok and type(ids) == "table" and #ids > 0 then
            local info = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
            if type(info) == "table" then
                idMetier = MetierDeLigne(info.professionID) or MetierDeNom(info.professionName or info.name)
            end
            for _, id in ipairs(ids) do
                local okR, r = pcall(C_TradeSkillUI.GetRecipeInfo, id)
                if okR and type(r) == "table" and r.learned and r.name then
                    MarquerRecette(r.name, true)
                    lues = lues + 1
                end
            end
        end
    end
    if lues == 0 and GetNumTradeSkills and GetTradeSkillInfo then
        local okL, ligne = pcall(function() return GetTradeSkillLine and GetTradeSkillLine() end)
        if okL and ligne then idMetier = MetierDeNom(ligne) end
        local okN, total = pcall(GetNumTradeSkills)
        if okN and type(total) == "number" then
            for i = 1, total do
                local okI, nom, genre = pcall(GetTradeSkillInfo, i)
                if okI and nom and genre ~= "header" then
                    MarquerRecette(nom, true)
                    lues = lues + 1
                end
            end
        end
    end
    if lues > 0 then
        ParcoursDB.metiers = ParcoursDB.metiers or {}
        local ids = idMetier and { idMetier } or (DATA.ordre or {})
        for _, id in ipairs(ids) do
            ParcoursDB.metiers[id] = ParcoursDB.metiers[id] or {}
            ParcoursDB.metiers[id].recettesScannees = true
        end
    end
    return lues
end

-- Message « Vous avez appris ... [Recette] »
local function LireMessageSysteme(texte)
    if type(texte) ~= "string" then return false end
    local modele = ERR_LEARN_RECIPE_S
    if type(modele) ~= "string" then return false end
    local motif = "^" .. modele:gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1"):gsub("%%%%s", "(.+)") .. "$"
    local capture = texte:match(motif)
    if not capture then return false end
    local nom = capture:match("%[(.-)%]") or capture
    MarquerRecette(nom, true)
    return true
end

-- ---------------------------------------------------------------------
-- Maîtres, statut de la recette, sources des ingrédients
-- ---------------------------------------------------------------------
-- Maîtres du métier (données web / QuestieDB, à confirmer en jeu) de la faction du joueur : "Nom (Zone)"
local function MaitresTexte()
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    local noms = {}
    for _, m in ipairs((D and D.maitres) or {}) do
        local bonTitre = (m.titre == nil) or (m.titre == "Maître des cuisiniers")
        if bonTitre and (m.faction == faction or m.faction == "Les deux" or not faction) then
            noms[#noms + 1] = (m.nom or "?") .. " (" .. (m.zone or "?") .. ")"
        end
    end
    if #noms > 4 then
        local reste = #noms - 4
        for _ = 1, reste do table.remove(noms) end
        noms[#noms + 1] = "+" .. reste .. " autres"
    end
    return #noms > 0 and table.concat(noms, ", ") or nil
end

-- Statut d'une étape : aucune (pas de recette), apprise, achetee, maitre, vendeur ou inconnue
local function StatutRecette(q)
    local r = q.recette
    if not r then
        if q.variantes and q.obtention == "Maître" then return "maitre" end
        if q.obtention == "Aucune" or not q.variantes then return "aucune" end
        return "inconnue"
    end
    if RecetteConnue(r) then return "apprise" end
    local achetee = r.objetId and CompterObjet(r.objetId)
    if achetee and achetee > 0 then return "achetee" end
    if r.maitre then return "maitre" end
    if r.vendeur then return "vendeur" end
    return "inconnue"
end

local function TexteStatutRecette(q)
    local statut = StatutRecette(q)
    if statut == "aucune" then
        return q.zones and ("à récolter : " .. table.concat(q.zones, ", ")) or "pas de recette à apprendre"
    end
    if statut == "apprise" then return "apprise" end
    if statut == "achetee" then return "achetée, à apprendre" end
    if statut == "maitre" then
        local maitres = MaitresTexte()
        return "à apprendre chez un maître" .. (maitres and (" : " .. maitres) or "")
    end
    if statut == "vendeur" then
        local v = q.recette.vendeur
        return "à acheter : " .. (v.nom or "?") .. (v.origine == "web" and " (à confirmer)" or "")
    end
    return q.obtention or "source à renseigner"
end

local function ResumeSource(ing)
    local info = D.ingredients and ing.id and D.ingredients[ing.id]
    local s = info and info.sources and info.sources[1]
    if not s then return "source à renseigner" end
    local zone = s.zoneFr or s.zone
    return (s.type or "?") .. (zone and (" - " .. zone) or "")
end

local function MarchandsDe(ing_id)
    local liste, vus = {}, {}
    local function Ajouter(m)
        local cle = (m.nom or "?") .. "|" .. tostring(m.zone)
        if not vus[cle] then vus[cle] = true; liste[#liste + 1] = m end
    end
    for _, m in ipairs((D and D.marchands) or {}) do
        for _, id in ipairs(m.composants or {}) do
            if id == ing_id then Ajouter(m) break end
        end
    end
    -- marchands relevés en jeu par le module Marchands (tous métiers)
    if type(CuisineMarchandsDB) == "table" then
        for cle, m in pairs(CuisineMarchandsDB) do
            if tostring(cle):sub(1, 1) ~= "_" and type(m) == "table" then
                for _, id in ipairs(m.composants or {}) do
                    if id == ing_id then Ajouter(m) break end
                end
            end
        end
    end
    return liste
end

local function RemplirInfoBulle(tip, ing, total, restant)
    tip:SetText(NomObjet(ing.id, ing.nom) or "?")
    if total then
        local ligne = "Besoin pour l'étape : " .. total
        if restant and restant ~= total then ligne = ligne .. " (reste " .. restant .. ")" end
        tip:AddLine(ligne, 1, 1, 1)
    end
    local info = D.ingredients and ing.id and D.ingredients[ing.id]
    if not info or not info.sources or #info.sources == 0 then
        tip:AddLine("Source non renseignée", 0.8, 0.4, 0.4)
    else
    tip:AddLine("Où le trouver :", 1, 0.82, 0)
    for _, s in ipairs(info.sources) do
        local zone = s.zoneFr or s.zone
        local txt = (s.type or "?")
        if s.source and s.type ~= "Vendeur" then txt = txt .. " : " .. s.source end
        if zone then txt = txt .. " (" .. zone .. ")" end
        if s.niveauMin then
            txt = txt .. ", niv. " .. s.niveauMin .. (s.niveauMax and s.niveauMax ~= s.niveauMin and ("-" .. s.niveauMax) or "")
        end
        tip:AddLine(txt, 0.85, 0.85, 0.85, true)
    end
    end
    local marchands = MarchandsDe(ing.id)
    if #marchands > 0 then
        tip:AddLine("Marchands relevés :", 1, 0.82, 0)
        for i, m in ipairs(marchands) do
            if i > 6 then tip:AddLine("...", 0.7, 0.7, 0.7) break end
            tip:AddLine(string.format("%s - %s (%s, %s)", m.nom or "?", m.zone or "?", m.x or "?", m.y or "?"), 0.85, 0.85, 0.85)
        end
    end
end

-- ---------------------------------------------------------------------
-- Interface : journal (onglets par métier, liste d'étapes défilante, détails)
-- ---------------------------------------------------------------------
local fenetre
local metierOnglet          -- id du métier affiché dans le journal
local selections = {}       -- id -> numéro d'étape sélectionnée
local decalages = {}        -- id -> décalage de la liste
local lignesQuetes = {}
local lignesIngredients = {}
local boutonsOnglets = {}
local MAX_INGREDIENTS = 7
local LIGNES_VISIBLES = 10
local suiviDirty = true

local function Texte(parent, gabarit, point, rel, relPoint, x, y, largeur)
    local t = parent:CreateFontString(nil, "OVERLAY", gabarit)
    t:SetPoint(point, rel, relPoint, x, y)
    if largeur then t:SetWidth(largeur) end
    t:SetJustifyH("LEFT")
    return t
end

local function Colorer(t, c)
    t:SetTextColor(c[1], c[2], c[3])
end

local Rafraichir

-- Icônes (sort de la recette, sinon icône du métier ; objet de l'ingrédient)
local ICONE_INCONNUE = "Interface\\Icons\\INV_Misc_QuestionMark"

local function IconeMetier()
    return "Interface\\Icons\\" .. ((D and D.icone) or "INV_Misc_QuestionMark")
end

local function IconeQuete(q)
    local id = q.recette and q.recette.sortId
    if id and GetSpellTexture then
        local ok, t = pcall(GetSpellTexture, id)
        if ok and t then return t end
    end
    return IconeMetier()
end

local function IconeObjet(id)
    if id then
        local ok, t = pcall(function()
            if GetItemIcon then return GetItemIcon(id) end
            if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
        end)
        if ok and t then return t end
    end
    return ICONE_INCONNUE
end

local function Cadre(parent, w, h, x, y)
    -- panneau en retrait : modèle natif si disponible, sinon fond sombre avec filet
    local c
    local ok = pcall(function() c = CreateFrame("Frame", nil, parent, "InsetFrameTemplate") end)
    if not (ok and c) then
        c = CreateFrame("Frame", nil, parent)
        local t = c:CreateTexture(nil, "BACKGROUND")
        t:SetAllPoints()
        t:SetColorTexture(0, 0, 0, 0.35)
    end
    c:SetSize(w, h)
    c:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    return c
end

local function CadreIcone(parent, taille)
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(taille, taille)
    c.tex = c:CreateTexture(nil, "ARTWORK")
    c.tex:SetAllPoints()
    c.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    c.bord = c:CreateTexture(nil, "OVERLAY")
    c.bord:SetPoint("TOPLEFT", c, "TOPLEFT", -2, 2)
    c.bord:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 2, -2)
    c.bord:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    c.bord:SetAlpha(0)  -- le contour natif des cases d'action est trop épais : on reste sur un cadre fin
    c.liseret = c:CreateTexture(nil, "BORDER")
    c.liseret:SetPoint("TOPLEFT", c, "TOPLEFT", -1, 1)
    c.liseret:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 1, -1)
    c.liseret:SetColorTexture(0.45, 0.38, 0.2, 1)
    return c
end

local function CreerFenetre()
    -- cadre natif (même kit d'interface que les fenêtres du jeu) ; repli sur un fond sombre si le modèle manque
    local f
    local natif = pcall(function() f = CreateFrame("Frame", "ParcoursFrame", UIParent, "BasicFrameTemplateWithInset") end)
    if not (natif and f) then
        natif = false
        f = CreateFrame("Frame", "ParcoursFrame", UIParent)
        local fond = f:CreateTexture(nil, "BACKGROUND")
        fond:SetAllPoints()
        fond:SetColorTexture(0.05, 0.05, 0.08, 0.93)
        pcall(function()
            local fermer = CreateFrame("Button", nil, f, "UIPanelCloseButton")
            fermer:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
        end)
    end
    f:SetSize(720, 540)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:EnableMouseWheel(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    if UISpecialFrames then table.insert(UISpecialFrames, "ParcoursFrame") end

    -- titre dans la barre du cadre
    local titreNatif = natif and (f.TitleText or (f.TitleContainer and f.TitleContainer.TitleText)) or nil
    if titreNatif and titreNatif.SetText then
        f.titre = titreNatif
    else
        f.titre = Texte(f, "GameFontNormal", "TOP", f, "TOP", 0, -6)
    end
    f.titre:SetText("Parcours des métiers")

    f.niveau = Texte(f, "GameFontNormal", "TOPLEFT", f, "TOPLEFT", 16, -34, 680)

    -- panneau gauche : liste des étapes (défilement à la molette)
    Cadre(f, 312, 408, 10, -56)
    for i = 1, LIGNES_VISIBLES do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(298, 38)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", 17, -60 - (i - 1) * 40)
        b.fond = b:CreateTexture(nil, "BACKGROUND")
        b.fond:SetAllPoints()
        b.fond:SetColorTexture(1, 0.82, 0, 0)
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight", "ADD")
        b.icone = CadreIcone(b, 30)
        b.icone:SetPoint("LEFT", b, "LEFT", 4, 0)
        b.coche = b:CreateTexture(nil, "OVERLAY")
        b.coche:SetSize(16, 16)
        b.coche:SetPoint("RIGHT", b, "RIGHT", -6, 0)
        b.coche:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        b.l1 = Texte(b, "GameFontNormal", "TOPLEFT", b, "TOPLEFT", 42, -5, 232)
        b.l2 = Texte(b, "GameFontHighlightSmall", "TOPLEFT", b, "TOPLEFT", 42, -21, 232)
        b:SetScript("OnClick", function(self)
            if self.n and metierOnglet then
                selections[metierOnglet] = self.n
                Rafraichir()
            end
        end)
        lignesQuetes[i] = b
    end
    f:SetScript("OnMouseWheel", function(_, delta)
        local m = metierOnglet and DATA.metiers[metierOnglet]
        if not m then return end
        local maxi = math.max(0, #m.quetes - LIGNES_VISIBLES)
        local d = (decalages[metierOnglet] or 0) - delta
        decalages[metierOnglet] = math.max(0, math.min(maxi, d))
        Rafraichir()
    end)
    f.aide = Texte(f, "GameFontDisableSmall", "TOPLEFT", f, "TOPLEFT", 18, -470, 300)

    -- panneau droit : détails de l'étape
    Cadre(f, 380, 408, 330, -56)
    local X = 342
    f.dIcone = CadreIcone(f, 40)
    f.dIcone:SetPoint("TOPLEFT", f, "TOPLEFT", X + 4, -66)
    f.dTitre = Texte(f, "GameFontNormalLarge", "TOPLEFT", f, "TOPLEFT", X + 54, -66, 316)
    f.dInfo = Texte(f, "GameFontHighlightSmall", "TOPLEFT", f, "TOPLEFT", X + 54, -90, 316)

    -- barre de compétence (comme la fenêtre des métiers)
    f.barreFond = CreateFrame("Frame", nil, f)
    f.barreFond:SetSize(360, 16)
    f.barreFond:SetPoint("TOPLEFT", f, "TOPLEFT", X + 4, -116)
    local fondBarre = f.barreFond:CreateTexture(nil, "BACKGROUND")
    fondBarre:SetAllPoints()
    fondBarre:SetColorTexture(0, 0, 0, 0.6)
    f.barre = CreateFrame("StatusBar", nil, f.barreFond)
    f.barre:SetPoint("TOPLEFT", f.barreFond, "TOPLEFT", 1, -1)
    f.barre:SetPoint("BOTTOMRIGHT", f.barreFond, "BOTTOMRIGHT", -1, 1)
    f.barre:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    f.barre:SetMinMaxValues(0, 1)
    f.barre:SetValue(0)
    f.barreTexte = f.barre:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.barreTexte:SetPoint("CENTER", f.barre, "CENTER", 0, 0)

    f.dRecette = Texte(f, "GameFontHighlight", "TOPLEFT", f, "TOPLEFT", X + 4, -140, 360)
    f.dEtat = Texte(f, "GameFontHighlight", "TOPLEFT", f, "TOPLEFT", X + 4, -176, 360)
    f.dIngTitre = Texte(f, "GameFontNormal", "TOPLEFT", f, "TOPLEFT", X + 4, -198, 360)
    for i = 1, MAX_INGREDIENTS do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(362, 32)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", X + 4, -216 - (i - 1) * 34)
        b.fond = b:CreateTexture(nil, "BACKGROUND")
        b.fond:SetAllPoints()
        b.fond:SetColorTexture(1, 1, 1, 0.05)
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight", "ADD")
        b.icone = CadreIcone(b, 26)
        b.icone:SetPoint("LEFT", b, "LEFT", 4, 0)
        b.l1 = Texte(b, "GameFontHighlight", "TOPLEFT", b, "TOPLEFT", 38, -3, 320)
        b.l2 = Texte(b, "GameFontHighlightSmall", "TOPLEFT", b, "TOPLEFT", 38, -17, 320)
        b:SetScript("OnEnter", function(self)
            if not self.ing then return end
            Utiliser(metierOnglet)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            local ok, err = pcall(RemplirInfoBulle, GameTooltip, self.ing, self.total, self.restant)
            if not ok then GameTooltip:SetText("Erreur : " .. tostring(err)) end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        lignesIngredients[i] = b
    end
    f.dNotes = Texte(f, "GameFontDisableSmall", "TOPLEFT", f, "TOPLEFT", X + 4, -456, 360)

    -- option : afficher les métiers de récolte
    local ok, caseRecolte = pcall(CreateFrame, "CheckButton", "ParcoursCaseRecolte", f, "UICheckButtonTemplate")
    if ok and caseRecolte then
        caseRecolte:SetSize(24, 24)
        caseRecolte:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 30)
        local txt = Texte(f, "GameFontHighlightSmall", "LEFT", caseRecolte, "RIGHT", 2, 0)
        txt:SetText("Afficher les métiers de récolte (herboristerie, minage, dépeçage, pêche)")
        caseRecolte:SetScript("OnClick", function(self)
            ParcoursDB.afficherRecolte = self:GetChecked() and true or nil
            suiviDirty = true
            Rafraichir()
        end)
        f.caseRecolte = caseRecolte
    end
    f.pied = Texte(f, "GameFontDisableSmall", "BOTTOMLEFT", f, "BOTTOMLEFT", 16, 12, 690)
    f:Hide()
    return f
end

-- Onglets : colonne d'icônes sur le bord droit de la fenêtre (comme la fenêtre des métiers et le grimoire).
-- Modèle natif des onglets du grimoire si disponible, sinon bouton simple avec cadre doré.
local function InfoBulleOnglet(self)
    if not self.id then return end
    local m = DATA.metiers[self.id]
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(m.nom)
    local precedent = D
    Utiliser(self.id)
    local niveau, origine = NiveauMetier()
    if niveau then GameTooltip:AddLine("Niveau " .. niveau .. " (" .. origine .. ")", 1, 1, 1) end
    GameTooltip:AddLine("Plan : " .. (m.edition or "?"), 0.7, 0.7, 0.7)
    D = precedent
    GameTooltip:Show()
end

local function MajOnglets(liste)
    for _, b in ipairs(boutonsOnglets) do b:Hide() end
    for i, id in ipairs(liste) do
        local b = boutonsOnglets[i]
        if not b then
            local ok
            ok, b = pcall(CreateFrame, "CheckButton", "ParcoursOnglet" .. i, fenetre, "SpellBookSkillLineTabTemplate")
            if ok and b then
                b.natif = true
            else
                b = CreateFrame("CheckButton", nil, fenetre)
                b:SetSize(32, 32)
                b.tex = b:CreateTexture(nil, "ARTWORK")
                b.tex:SetAllPoints()
                b.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                b.cadre = b:CreateTexture(nil, "BACKGROUND")
                b.cadre:SetPoint("TOPLEFT", b, "TOPLEFT", -3, 3)
                b.cadre:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 3, -3)
                b.cadre:SetColorTexture(0.45, 0.38, 0.2, 1)
                b.halo = b:CreateTexture(nil, "OVERLAY")
                b.halo:SetPoint("TOPLEFT", b, "TOPLEFT", -6, 6)
                b.halo:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 6, -6)
                b.halo:SetTexture("Interface\\Buttons\\CheckButtonHilight")
                b.halo:SetBlendMode("ADD")
                b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
            end
            b:SetScript("OnClick", function(self)
                if self.id then
                    metierOnglet = self.id
                    ParcoursDB.metierSuivi = self.id
                    suiviDirty = true
                    Rafraichir()
                end
            end)
            b:SetScript("OnEnter", function(self) pcall(InfoBulleOnglet, self) end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            boutonsOnglets[i] = b
        end
        b.id = id
        local actif = (id == metierOnglet)
        local icone = "Interface\\Icons\\" .. (DATA.metiers[id].icone or "INV_Misc_QuestionMark")
        if b.natif then
            if b.SetNormalTexture then b:SetNormalTexture(icone) end
            if b.SetChecked then b:SetChecked(actif) end
        else
            b.tex:SetTexture(icone)
            b.halo:SetShown(actif)
            if b.tex.SetDesaturated then b.tex:SetDesaturated(not actif) end
        end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", fenetre, "TOPRIGHT", -1, -58 - (i - 1) * 48)
        b:Show()
    end
end

local function AfficherDetails(niveau)
    local sel = selections[D.id] or 1
    local q = D.quetes[sel]
    if not q then return end
    local etat = EtatQuete(q, niveau)
    fenetre.dIcone.tex:SetTexture(IconeQuete(q))
    fenetre.dTitre:SetText(TitreQuete(q))
    Colorer(fenetre.dTitre, COULEURS_RECETTE[q.couleur] or COULEUR_ENCOURS)
    if q.couleur then
        fenetre.dInfo:SetText(string.format("Étape %d  |  %s  |  Rang : %s", q.n, q.couleur, q.rang or "?"))
    else
        fenetre.dInfo:SetText(string.format("Étape %d  |  %s", q.n, D.nom))
    end

    -- barre de compétence de l'étape
    local bas, haut = q.debut, q.fin
    fenetre.barre:SetMinMaxValues(bas, haut)
    local valeur = niveau and math.max(bas, math.min(haut, niveau)) or bas
    fenetre.barre:SetValue(valeur)
    if etat == "terminee" then
        fenetre.barre:SetStatusBarColor(0.25, 0.7, 0.25)
    else
        fenetre.barre:SetStatusBarColor(0.1, 0.45, 0.9)
    end
    fenetre.barreTexte:SetText(string.format("Compétence %s  (%d -> %d)", niveau and tostring(niveau) or "?", q.debut, q.fin))

    local statut = StatutRecette(q)
    fenetre.dRecette:SetText((statut == "aucune" and "" or "Recette : ") .. TexteStatutRecette(q))

    local restants = CraftsRestants(q, niveau)
    local texteEtat
    if etat == "terminee" then
        texteEtat = "Étape terminée."
        Colorer(fenetre.dEtat, COULEUR_TERMINEE)
    elseif etat == "encours" then
        texteEtat = q.crafts and string.format("En cours : environ %d craft(s) restant(s) sur %d.", restants, q.crafts) or "En cours."
        Colorer(fenetre.dEtat, COULEUR_ENCOURS)
    elseif etat == "avenir" then
        texteEtat = q.crafts and string.format("À venir : %d craft(s) prévus.", q.crafts) or "À venir."
        Colorer(fenetre.dEtat, COULEUR_AVENIR)
    else
        texteEtat = q.crafts and string.format("Niveau inconnu : %d craft(s) prévus.", q.crafts) or "Niveau inconnu."
        Colorer(fenetre.dEtat, COULEUR_AVENIR)
    end
    fenetre.dEtat:SetText(texteEtat)
    fenetre.dIngTitre:SetText(q.crafts and "Ingrédients à récolter (survole pour les sources) :" or "À récolter / à utiliser :")

    for i = 1, MAX_INGREDIENTS do
        local b = lignesIngredients[i]
        local ing = q.ingredients and q.ingredients[i]
        if ing then
            local total = (ing.par_craft and q.crafts) and (ing.par_craft * q.crafts) or nil
            local reste = total and ((etat == "encours" and restants) and (ing.par_craft * restants) or total) or nil
            b.ing, b.total, b.restant = ing, total, reste
            b.icone.tex:SetTexture(IconeObjet(ing.id))
            local nom = NomObjet(ing.id, ing.nom) or "?"
            local possede = CompterObjet(ing.id)
            if total then
                b.l1:SetText(string.format("%s  x%d%s", nom, total, (etat == "encours" and reste ~= total) and (" (reste " .. reste .. ")") or ""))
            else
                b.l1:SetText(nom)
            end
            if possede and reste then
                Colorer(b.l1, possede >= reste and COULEUR_TERMINEE or { 1, 1, 1 })
            else
                Colorer(b.l1, { 1, 1, 1 })
            end
            local src = ResumeSource(ing)
            b.l2:SetText(possede and string.format("En sac : %d   -   %s", possede, src) or src)
            b:Show()
        else
            b.ing = nil
            b:Hide()
        end
    end
    fenetre.dNotes:ClearAllPoints()
    fenetre.dNotes:SetPoint("TOPLEFT", fenetre, "TOPLEFT", 346, -216 - math.max(1, #(q.ingredients or {})) * 34 - 8)
    fenetre.dNotes:SetText(q.obtentionDetail or "")
end

Rafraichir = function()
    if not (fenetre and DATA and DATA.metiers) then return end
    if fenetre.caseRecolte and fenetre.caseRecolte.SetChecked then fenetre.caseRecolte:SetChecked(ParcoursDB.afficherRecolte and true or false) end
    local liste = MetiersAffiches()
    if #liste == 0 then
        fenetre.niveau:SetText("Aucun métier appris détecté. /parcours tous affiche tous les métiers.")
        MajOnglets(liste)
        return
    end
    local present = false
    for _, id in ipairs(liste) do if id == metierOnglet then present = true end end
    if not present then metierOnglet = MetierSuivi() or liste[1] end
    Utiliser(metierOnglet)
    MajOnglets(liste)

    local niveau, origine = NiveauMetier()
    if niveau then
        fenetre.niveau:SetText(string.format("%s : niveau %d (%s)", D.nom, niveau, origine))
    else
        fenetre.niveau:SetText(string.format("%s : niveau introuvable. /parcours niveau N pour le renseigner.", D.nom))
    end
    if not selections[D.id] then selections[D.id] = QueteCourante(niveau) end
    local sel = selections[D.id]
    if decalages[D.id] == nil then
        decalages[D.id] = math.max(0, math.min(#D.quetes - LIGNES_VISIBLES, (sel or 1) - 4))
    end
    local dec = decalages[D.id]
    for i = 1, LIGNES_VISIBLES do
        local b = lignesQuetes[i]
        local q = D.quetes[dec + i]
        if q then
            local etatQ = EtatQuete(q, niveau)
            local couleur = (etatQ == "terminee" and COULEUR_TERMINEE) or (etatQ == "encours" and COULEUR_ENCOURS) or COULEUR_AVENIR
            b.n = q.n
            b.icone.tex:SetTexture(IconeQuete(q))
            if b.icone.tex.SetDesaturated then b.icone.tex:SetDesaturated(etatQ == "avenir") end
            b.coche:SetShown(etatQ == "terminee")
            b.l1:SetText(string.format("%d. %s", q.n, TitreQuete(q)))
            Colorer(b.l1, couleur)
            b.l2:SetText(q.crafts and string.format("Compétence %d -> %d  -  %d craft(s)", q.debut, q.fin, q.crafts)
                or string.format("Compétence %d -> %d", q.debut, q.fin))
            b.fond:SetColorTexture(1, 0.82, 0, (sel == q.n) and 0.22 or ((etatQ == "encours") and 0.08 or 0))
            b:Show()
        else
            b.n = nil
            b:Hide()
        end
    end
    fenetre.aide:SetText(#D.quetes > LIGNES_VISIBLES and "Molette de la souris : faire défiler la liste." or "")
    AfficherDetails(niveau)
    local avert = ""
    if D.edition and D.edition:find("Classic") then avert = "  Données Classic Era : à confirmer sur la bêta." end
    fenetre.pied:SetText("Plan indicatif (" .. (D.edition or "?") .. ")." .. avert .. "  /parcours niveau N pour forcer le niveau, niveau auto pour revenir à la détection.")
end

local function OuvrirJournalSur(id, n)
    if not (DATA and DATA.metiers) then
        Print("Données absentes : le fichier Donnees.lua est introuvable ou vide.")
        return
    end
    if not fenetre then fenetre = CreerFenetre() end
    if id and DATA.metiers[id] then
        metierOnglet = id
        if n then
            selections[id] = n
            decalages[id] = nil
        end
    end
    fenetre:Show()
    Rafraichir()
end

local function BasculerFenetre()
    if not (DATA and DATA.metiers) then
        Print("Données absentes : le fichier Donnees.lua est introuvable ou vide.")
        return
    end
    if not fenetre then fenetre = CreerFenetre() end
    if fenetre:IsShown() then
        fenetre:Hide()
    else
        metierOnglet = MetierSuivi()
        selections = {}
        decalages = {}
        fenetre:Show()
        Rafraichir()
    end
end

-- ---------------------------------------------------------------------
-- Icône sur le cercle de la minimap (clic : ouvrir le journal, glisser : déplacer)
-- ---------------------------------------------------------------------
local icone
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local ANGLE_PAR_DEFAUT = 215
local RAYON_SUPPLEMENT = 10

local function PlacerIcone()
    if not (icone and Minimap) then return end
    local rad = math.rad(ParcoursDB.minimapAngle or ANGLE_PAR_DEFAUT)
    local rayon = (Minimap:GetWidth() / 2) + RAYON_SUPPLEMENT
    icone:ClearAllPoints()
    icone:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * rayon, math.sin(rad) * rayon)
end

local function MajVisibiliteIcone()
    if not icone then return end
    if ParcoursDB.iconeMasquee then icone:Hide() else icone:Show() end
end

local function SuivreCurseur()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    if not (mx and my and cx and cy) then return end
    local echelle = Minimap:GetEffectiveScale()
    cx, cy = cx / echelle, cy / echelle
    ParcoursDB.minimapAngle = math.deg(atan2(cy - my, cx - mx)) % 360
    PlacerIcone()
end

local function InfoBulleIcone(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Parcours des métiers")
    local liste = MetiersAffiches()
    if #liste == 0 then
        GameTooltip:AddLine("Aucun métier appris détecté.", 0.7, 0.7, 0.7)
    end
    for _, id in ipairs(liste) do
        Utiliser(id)
        local niveau = NiveauMetier()
        local q = niveau and D.quetes[QueteCourante(niveau)]
        if q then
            GameTooltip:AddLine(string.format("%s %d - étape %d : %s", D.nom, niveau, q.n, TitreQuete(q)), 1, 0.82, 0)
        else
            GameTooltip:AddLine(D.nom, 1, 0.82, 0)
        end
    end
    GameTooltip:AddLine("Clic : ouvrir / fermer le journal", 1, 1, 1)
    GameTooltip:AddLine("Glisser : déplacer l'icône", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

local glisse = false
local finGlisse = nil

local function CreerIcone()
    if icone or not Minimap then return end
    local b = CreateFrame("Button", "ParcoursIcone", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    local fond = b:CreateTexture(nil, "BACKGROUND")
    fond:SetSize(20, 20)
    fond:SetPoint("TOPLEFT", b, "TOPLEFT", 7, -5)
    fond:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    local image = b:CreateTexture(nil, "ARTWORK")
    image:SetSize(17, 17)
    image:SetPoint("TOPLEFT", b, "TOPLEFT", 7, -6)
    image:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    image:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    local bord = b:CreateTexture(nil, "OVERLAY")
    bord:SetSize(53, 53)
    bord:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    bord:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    b:RegisterForClicks("LeftButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function(self)
        glisse = true
        GameTooltip:Hide()
        self:SetScript("OnUpdate", SuivreCurseur)
    end)
    b:SetScript("OnDragStop", function(self)
        glisse = false
        finGlisse = GetTime and GetTime() or nil
        self:SetScript("OnUpdate", nil)
    end)
    b:SetScript("OnClick", function()
        if glisse then return end
        if GetTime and finGlisse and (GetTime() - finGlisse) < 0.25 then return end
        local ok, err = pcall(BasculerFenetre)
        if not ok then Print("Erreur : " .. tostring(err)) end
    end)
    b:SetScript("OnEnter", function(self)
        local ok, err = pcall(InfoBulleIcone, self)
        if not ok then GameTooltip:SetText("Erreur : " .. tostring(err)) GameTooltip:Show() end
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    icone = b
    PlacerIcone()
    MajVisibiliteIcone()
end

-- ---------------------------------------------------------------------
-- Suivi à gauche (comme le suivi de quêtes). Clic sur l'en-tête : réduire / agrandir. Maj + glisser : déplacer.
-- Un bloc par métier appris (5 au plus en pratique) : l'étape en cours, la recette, les ingrédients.
-- ---------------------------------------------------------------------
local evenementsEtat = {}
local compteurEvenements = {}

local suivi, suiviEntete, suiviSigne, suiviTexteEntete
local titresSuivi = {}   -- un titre cliquable par métier
local lignesSuivi = {}
local suiviTimer = 0
local deplace = false
local finDeplacement = nil
local suiviSondage = 0
local derniereSignature = nil
local MAX_LIGNES_SUIVI = 80
local MAX_BLOCS_SUIVI = 8
local LARGEUR_SUIVI = 250
local POS_SUIVI_DEFAUT = { x = 20, y = -240 }

local function PlacerSuivi()
    if not suivi then return end
    local pos = ParcoursDB.suiviPos or POS_SUIVI_DEFAUT
    suivi:ClearAllPoints()
    suivi:SetPoint("TOPLEFT", UIParent, "TOPLEFT", pos.x, pos.y)
end

local function HauteurTexte(fs, defaut)
    local h = fs.GetStringHeight and fs:GetStringHeight()
    return (type(h) == "number" and h > 0) and h or defaut
end

local function LignesRecette(q)
    local statut = StatutRecette(q)
    local r = q.recette
    local l = {}
    if statut == "aucune" then
        if q.zones then l[#l + 1] = { "   " .. table.concat(q.zones, ", "), COULEUR_AVENIR } end
        return l
    end
    if statut == "apprise" then
        l[1] = { "Recette apprise", COULEUR_TERMINEE }
        return l
    end
    if statut == "achetee" then
        l[#l + 1] = { "Acheter la recette : 1/1", COULEUR_TERMINEE }
        l[#l + 1] = { "Apprendre la recette : 0/1 (clic droit dans le sac)", COULEUR_OBJECTIF }
    elseif statut == "vendeur" then
        local v = r.vendeur
        l[#l + 1] = { "Acheter la recette : 0/1", COULEUR_OBJECTIF }
        l[#l + 1] = { string.format("   chez %s (%s %s / %s)%s", v.nom or "?", v.zone or "?", v.x or "?", v.y or "?", v.origine == "web" and " - à confirmer" or ""), COULEUR_AVENIR }
        l[#l + 1] = { "Apprendre la recette : 0/1", COULEUR_OBJECTIF }
    elseif statut == "maitre" then
        l[#l + 1] = { "Apprendre la recette chez un maître : 0/1", COULEUR_OBJECTIF }
        local maitres = MaitresTexte()
        if maitres then l[#l + 1] = { "   " .. maitres, COULEUR_AVENIR } end
    else
        l[#l + 1] = { "Obtenir la recette : 0/1", COULEUR_OBJECTIF }
        l[#l + 1] = { "   " .. (q.obtention or "source à renseigner"), COULEUR_AVENIR }
    end
    if not DBM().recettesScannees then
        l[#l + 1] = { "Ouvre ta fenêtre de " .. D.nom:lower() .. " pour détecter tes recettes.", COULEUR_AVENIR }
    end
    return l
end

-- Lignes d'une étape (recette, compétence, ingrédients) pour le métier D
local function LignesMetier(niveau, q)
    local lignes = {}
    for _, l in ipairs(LignesRecette(q)) do lignes[#lignes + 1] = l end
    if niveau then
        lignes[#lignes + 1] = { string.format("Compétence : %d/%d", niveau, q.fin), COULEUR_OBJECTIF }
    else
        lignes[#lignes + 1] = { "Niveau introuvable (/parcours niveau N)", COULEUR_AVENIR }
    end
    local restants = CraftsRestants(q, niveau)
    for _, ing in ipairs(q.ingredients or {}) do
        local nom = NomObjet(ing.id, ing.nom) or "?"
        local besoin = (ing.par_craft and restants) and (ing.par_craft * restants) or nil
        local possede = CompterObjet(ing.id)
        if besoin and possede then
            lignes[#lignes + 1] = { string.format("%s : %d/%d", nom, possede, besoin),
                                    (possede >= besoin) and COULEUR_TERMINEE or COULEUR_OBJECTIF }
        elseif besoin then
            lignes[#lignes + 1] = { string.format("%s : %d à récolter", nom, besoin), COULEUR_OBJECTIF }
        elseif possede then
            lignes[#lignes + 1] = { string.format("%s : %d en sac", nom, possede), COULEUR_OBJECTIF }
        else
            lignes[#lignes + 1] = { nom, COULEUR_OBJECTIF }
        end
    end
    return lignes
end

-- Un bloc par métier affiché : titre de l'étape en cours (cliquable) puis ses objectifs
local function RafraichirSuivi()
    if not (suivi and DATA and DATA.metiers) then return end
    if ParcoursDB.suiviMasque then suivi:Hide() return end
    local liste = MetiersAffiches()
    if #liste == 0 then suivi:Hide() return end
    suivi:Show()
    local reduit = ParcoursDB.suiviReduit
    suiviSigne:SetTexture(reduit and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")

    local y = 24
    for _, t in ipairs(titresSuivi) do t:Hide() end
    for _, fs in ipairs(lignesSuivi) do fs:Hide() end
    if reduit then
        suivi:SetHeight(y)
        return
    end

    local iLigne = 0
    for iBloc, id in ipairs(liste) do
        if iBloc > MAX_BLOCS_SUIVI then break end
        Utiliser(id)
        local niveau = NiveauMetier()
        local dernier = D.quetes[#D.quetes]
        local titre, lignes, num
        if niveau and niveau >= dernier.fin then
            titre = D.nom .. " : parcours terminé"
            lignes = { { string.format("%s %d atteint.", D.nom, niveau), COULEUR_TERMINEE } }
        else
            num = QueteCourante(niveau)
            local q = D.quetes[num]
            titre = D.nom .. " : " .. TitreQuete(q)
            lignes = LignesMetier(niveau, q)
        end

        local t = titresSuivi[iBloc]
        t.id, t.n = id, num
        t.texte:SetText(titre)
        Colorer(t.texte, COULEUR_ENCOURS)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", suivi, "TOPLEFT", 0, -y)
        local h = HauteurTexte(t.texte, 16)
        t:SetHeight(h)
        t:Show()
        y = y + h + 3
        for _, l in ipairs(lignes) do
            iLigne = iLigne + 1
            local fs = lignesSuivi[iLigne]
            if not fs then break end
            fs:SetText(l[1])
            Colorer(fs, l[2])
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", suivi, "TOPLEFT", 10, -y)
            fs:Show()
            y = y + HauteurTexte(fs, 13) + 2
        end
        y = y + 6
    end
    suivi:SetHeight(y)
end

-- Empreinte de ce que le suivi affiche : si elle change, on rafraîchit
local function SignatureSuivi()
    local parts = {}
    for _, id in ipairs(MetiersAffiches()) do
        Utiliser(id)
        local niveau = NiveauMetier()
        parts[#parts + 1] = id .. "=" .. tostring(niveau)
        local q = niveau and D.quetes[QueteCourante(niveau)]
        if q then
            parts[#parts + 1] = StatutRecette(q)
            parts[#parts + 1] = tostring(DBM().recettesScannees)
            for _, ing in ipairs(q.ingredients or {}) do
                parts[#parts + 1] = tostring(CompterObjet(ing.id))
            end
        end
    end
    return table.concat(parts, ":")
end

local function DiagnosticSuivi()
    Print("Comptage d'objets : GetItemCount=" .. tostring(GetItemCount ~= nil) ..
          ", C_Item.GetItemCount=" .. tostring(C_Item ~= nil and C_Item.GetItemCount ~= nil))
    local ok, ko, recu = {}, {}, {}
    for e, etat in pairs(evenementsEtat) do
        if etat == true then ok[#ok + 1] = e else ko[#ko + 1] = e .. " (" .. tostring(etat) .. ")" end
    end
    table.sort(ok) table.sort(ko)
    for e, n in pairs(compteurEvenements) do recu[#recu + 1] = e .. "=" .. n end
    table.sort(recu)
    Print("Événements enregistrés : " .. (#ok > 0 and table.concat(ok, ", ") or "aucun"))
    if #ko > 0 then Print("Événements REFUSÉS par le jeu : " .. table.concat(ko, " ; ")) end
    Print("Événements reçus : " .. (#recu > 0 and table.concat(recu, ", ") or "aucun pour l'instant"))
    local liste, appris = MetiersAffiches()
    local noms = {}
    for id, rang in pairs(appris) do noms[#noms + 1] = id .. "=" .. rang end
    table.sort(noms)
    Print("Métiers détectés : " .. (#noms > 0 and table.concat(noms, ", ") or "aucun") ..
          ". Affichés : " .. (#liste > 0 and table.concat(liste, ", ") or "aucun"))
    Print(string.format("Suivi : %s%s", ParcoursDB.suiviMasque and "masqué" or "affiché", ParcoursDB.suiviReduit and ", réduit" or ""))
    local id = MetierSuivi()
    if not id then return end
    Utiliser(id)
    local niveau, origine = NiveauMetier()
    Print("Métier suivi : " .. D.nom .. ", niveau " .. (niveau and (niveau .. " (" .. origine .. ")") or "introuvable"))
    local q = niveau and D.quetes[QueteCourante(niveau)]
    if not q then return end
    Print(string.format("Étape suivie : %d. %s (%d -> %d), %s craft(s) restant(s)", q.n, TitreQuete(q), q.debut, q.fin,
        tostring(CraftsRestants(q, niveau))))
    local nbRecettes = 0
    for _ in pairs(RecettesConnues()) do nbRecettes = nbRecettes + 1 end
    Print(string.format("Recette : %s (objet %s). Recettes lues : %d, fenêtre du métier lue : %s. API : C_TradeSkillUI=%s, GetNumTradeSkills=%s",
        StatutRecette(q), tostring(q.recette and q.recette.objetId), nbRecettes,
        DBM().recettesScannees and "oui" or "non", tostring(C_TradeSkillUI ~= nil), tostring(GetNumTradeSkills ~= nil)))
    for _, ing in ipairs(q.ingredients or {}) do
        local n = CompterObjet(ing.id)
        Print(string.format("  objet %s %s : %s en sac", tostring(ing.id), ing.nom or "?", n and tostring(n) or "illisible"))
    end
end

local function CreerSuivi()
    if suivi then return end
    suivi = CreateFrame("Frame", "ParcoursSuivi", UIParent)
    suivi:SetSize(LARGEUR_SUIVI, 40)
    suivi:SetFrameStrata("LOW")
    suivi:SetMovable(true)
    suivi:SetClampedToScreen(true)
    PlacerSuivi()

    suiviEntete = CreateFrame("Button", "ParcoursSuiviEntete", suivi)
    suiviEntete:SetSize(LARGEUR_SUIVI, 20)
    suiviEntete:SetPoint("TOPLEFT", suivi, "TOPLEFT", 0, 0)
    suiviTexteEntete = suiviEntete:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    suiviTexteEntete:SetPoint("LEFT", suiviEntete, "LEFT", 0, 0)
    suiviTexteEntete:SetText("Parcours des métiers")
    suiviSigne = suiviEntete:CreateTexture(nil, "ARTWORK")
    suiviSigne:SetSize(16, 16)
    suiviSigne:SetPoint("RIGHT", suiviEntete, "RIGHT", 0, 0)
    local filet = suiviEntete:CreateTexture(nil, "ARTWORK")
    filet:SetSize(LARGEUR_SUIVI, 1)
    filet:SetPoint("BOTTOMLEFT", suiviEntete, "BOTTOMLEFT", 0, -2)
    filet:SetColorTexture(1, 0.82, 0, 0.45)
    suiviEntete:RegisterForClicks("LeftButtonUp")
    suiviEntete:RegisterForDrag("LeftButton")
    suiviEntete:SetScript("OnClick", function()
        if deplace then return end
        if GetTime and finDeplacement and (GetTime() - finDeplacement) < 0.25 then return end
        if ParcoursDB.suiviReduit then ParcoursDB.suiviReduit = nil else ParcoursDB.suiviReduit = true end
        pcall(RafraichirSuivi)
    end)
    suiviEntete:SetScript("OnDragStart", function()
        if IsShiftKeyDown and IsShiftKeyDown() then
            deplace = true
            suivi:StartMoving()
        end
    end)
    suiviEntete:SetScript("OnDragStop", function()
        if not deplace then return end
        deplace = false
        finDeplacement = GetTime and GetTime() or nil
        suivi:StopMovingOrSizing()
        local g, hautEcran = suivi:GetLeft(), suivi:GetTop()
        if g and hautEcran and UIParent.GetHeight then
            ParcoursDB.suiviPos = { x = g, y = hautEcran - UIParent:GetHeight() }
        end
        PlacerSuivi()
    end)
    suiviEntete:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Parcours des métiers")
        GameTooltip:AddLine("Clic : réduire / agrandir", 1, 1, 1)
        GameTooltip:AddLine("Maj + glisser : déplacer", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    suiviEntete:SetScript("OnLeave", function() GameTooltip:Hide() end)

    for i = 1, MAX_BLOCS_SUIVI do
        local t = CreateFrame("Button", "ParcoursSuiviTitre" .. i, suivi)
        t:SetSize(LARGEUR_SUIVI, 16)
        t.texte = t:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        t.texte:SetPoint("TOPLEFT", t, "TOPLEFT", 0, 0)
        t.texte:SetWidth(LARGEUR_SUIVI - 4)
        t.texte:SetJustifyH("LEFT")
        t:RegisterForClicks("LeftButtonUp")
        t:SetScript("OnClick", function(self)
            if self.id then pcall(OuvrirJournalSur, self.id, self.n) end
        end)
        t:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Ouvrir le journal")
            GameTooltip:Show()
        end)
        t:SetScript("OnLeave", function() GameTooltip:Hide() end)
        t:Hide()
        titresSuivi[i] = t
    end

    for i = 1, MAX_LIGNES_SUIVI do
        local fs = suivi:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetWidth(LARGEUR_SUIVI - 12)
        fs:SetJustifyH("LEFT")
        lignesSuivi[i] = fs
    end

    suivi:SetScript("OnUpdate", function(_, dt)
        suiviSondage = suiviSondage + (dt or 0)
        if suiviSondage >= 1 then
            suiviSondage = 0
            local ok, sig = pcall(SignatureSuivi)
            if ok and sig ~= derniereSignature then
                derniereSignature = sig
                suiviDirty = true
            end
        end
        if not suiviDirty then return end
        suiviTimer = suiviTimer + (dt or 0)
        if suiviTimer < 0.25 then return end
        suiviTimer = 0
        suiviDirty = false
        local ok, err = pcall(RafraichirSuivi)
        if not ok then Print("Suivi : erreur (" .. tostring(err) .. ")") end
    end)
    suiviDirty = true
end

-- ---------------------------------------------------------------------
-- Migration depuis CuisineParcours (variable sauvegardée CuisineParcoursDB)
-- ---------------------------------------------------------------------
local function Migrer()
    local ancien = CuisineParcoursDB
    if ParcoursDB.migre or type(ancien) ~= "table" or next(ancien) == nil then return end
    for _, cle in ipairs({ "suiviPos", "suiviReduit", "suiviMasque", "minimapAngle", "iconeMasquee", "recettesConnues" }) do
        if ancien[cle] ~= nil and ParcoursDB[cle] == nil then ParcoursDB[cle] = ancien[cle] end
    end
    ParcoursDB.metiers = ParcoursDB.metiers or {}
    ParcoursDB.metiers.cuisine = ParcoursDB.metiers.cuisine or {}
    if ancien.niveauManuel then ParcoursDB.metiers.cuisine.niveauManuel = ancien.niveauManuel end
    if ancien.recettesScannees then ParcoursDB.metiers.cuisine.recettesScannees = true end
    ParcoursDB.migre = true
end

-- ---------------------------------------------------------------------
-- Commandes
-- ---------------------------------------------------------------------
local function TrouverMetier(texte)
    texte = (texte or ""):lower()
    if texte == "" then return nil end
    for _, id in ipairs(DATA.ordre or {}) do
        local m = DATA.metiers[id]
        if id == texte or m.nom:lower() == texte then return id end
        for _, mot in ipairs(m.motsClient or {}) do
            if mot == texte then return id end
        end
    end
    return nil
end

local function Commande(arg)
    arg = (arg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if arg == "" then
        local ok, err = pcall(BasculerFenetre)
        if not ok then Print("Erreur : " .. tostring(err)) end
        return
    end
    -- module Marchands : /parcours marchands <commande> équivaut à /cmarch <commande>
    local sousCommande = arg:match("^marchands%s*(.*)$")
    if sousCommande then
        local f = SlashCmdList and SlashCmdList["CUISINEMARCHANDS"]
        if f then f(sousCommande) else Print("Module Marchands non chargé.") end
        return
    end
    if not (DATA and DATA.metiers) then Print("Données absentes : Donnees.lua introuvable ou vide.") return end
    local suiviId = MetierSuivi()
    local n = arg:match("^niveau%s+(%d+)$")
    if n then
        n = tonumber(n)
        if n < 1 or n > 300 then Print("Le niveau doit être compris entre 1 et 300.") return end
        if not suiviId then
            suiviId = DATA.ordre[1]
            ParcoursDB.metierSuivi = suiviId
        end
        Utiliser(suiviId)
        DBM().niveauManuel = n
        selections[suiviId], decalages[suiviId] = nil, nil
        Print(D.nom .. " : niveau forcé à " .. n .. ".")
        suiviDirty = true
        pcall(Rafraichir)
        return
    end
    if arg == "niveau auto" then
        if suiviId then
            Utiliser(suiviId)
            DBM().niveauManuel = nil
            selections[suiviId], decalages[suiviId] = nil, nil
            Print(D.nom .. " : retour à la détection automatique du niveau.")
        end
        suiviDirty = true
        pcall(Rafraichir)
        return
    end
    local nomMetier = arg:match("^metier%s+(.+)$")
    if nomMetier then
        local id = TrouverMetier(nomMetier)
        if not id then Print("Métier inconnu : " .. nomMetier) return end
        ParcoursDB.metierSuivi = id
        suiviDirty = true
        Print("Métier suivi : " .. DATA.metiers[id].nom .. ".")
        if fenetre and fenetre:IsShown() then metierOnglet = id pcall(Rafraichir) end
        return
    end
    if arg == "recolte" then
        ParcoursDB.afficherRecolte = not ParcoursDB.afficherRecolte or nil
        suiviDirty = true
        Print(ParcoursDB.afficherRecolte and "Métiers de récolte affichés (s'ils sont appris)." or "Métiers de récolte masqués.")
        pcall(Rafraichir)
        return
    end
    if arg == "tous" then
        ParcoursDB.afficherTous = not ParcoursDB.afficherTous
        suiviDirty = true
        Print(ParcoursDB.afficherTous and "Tous les métiers sont affichés." or "Seuls les métiers appris sont affichés.")
        pcall(Rafraichir)
        return
    end
    if arg == "suivi" then
        ParcoursDB.suiviMasque = not ParcoursDB.suiviMasque
        suiviDirty = true
        Print(ParcoursDB.suiviMasque and "Suivi masqué (/parcours suivi pour le réafficher)." or "Suivi affiché.")
        return
    end
    if arg == "recette connue" or arg == "recette inconnue" then
        if not suiviId then Print("Aucun métier suivi.") return end
        Utiliser(suiviId)
        local niveau = NiveauMetier()
        local q = D.quetes[QueteCourante(niveau)]
        if not (q and q.recette) then Print("Aucune recette à marquer pour l'étape en cours.") return end
        local nom = NomSort(q.recette.sortId, q.recette.nom)
        MarquerRecette(nom, arg == "recette connue")
        if q.recette.nom then MarquerRecette(q.recette.nom, arg == "recette connue") end
        if arg == "recette connue" then DBM().recettesScannees = true end
        suiviDirty = true
        Print(string.format("Recette « %s » marquée comme %s.", nom or "?", arg == "recette connue" and "apprise" or "non apprise"))
        pcall(Rafraichir)
        return
    end
    if arg == "suivi debug" then
        local ok, err = pcall(DiagnosticSuivi)
        if not ok then Print("Diagnostic : erreur (" .. tostring(err) .. ")") end
        return
    end
    if arg == "suivi reset" then
        ParcoursDB.suiviPos, ParcoursDB.suiviReduit, ParcoursDB.suiviMasque = nil, nil, nil
        PlacerSuivi()
        suiviDirty = true
        Print("Suivi remis à sa place d'origine (à gauche, agrandi).")
        return
    end
    if arg == "icone" then
        ParcoursDB.iconeMasquee = not ParcoursDB.iconeMasquee
        MajVisibiliteIcone()
        Print(ParcoursDB.iconeMasquee and "Icône de la minimap masquée (/parcours icone pour la réafficher)." or "Icône de la minimap affichée.")
        return
    end
    if arg == "icone reset" then
        ParcoursDB.minimapAngle, ParcoursDB.iconeMasquee = nil, nil
        PlacerIcone()
        MajVisibiliteIcone()
        Print("Icône de la minimap remise à sa place d'origine.")
        return
    end
    if arg == "etat" then
        local liste = MetiersAffiches()
        if #liste == 0 then Print("Aucun métier appris détecté (/parcours tous pour tout afficher).") return end
        for _, id in ipairs(liste) do
            Utiliser(id)
            local niveau, origine = NiveauMetier()
            local q = niveau and D.quetes[QueteCourante(niveau)]
            Print(string.format("%s %s%s", D.nom, niveau and (niveau .. " (" .. origine .. ")") or "niveau introuvable",
                q and string.format(" - étape %d : %s (%d -> %d)", q.n, TitreQuete(q), q.debut, q.fin) or ""))
        end
        return
    end
    Print("Commandes : /parcours (journal), niveau N, niveau auto, metier NOM, recolte, tous, etat, suivi (masquer/afficher), suivi reset, suivi debug, recette connue|inconnue, icone, icone reset, marchands (module des marchands favoris)")
end

SLASH_PARCOURS1 = "/parcours"
SLASH_PARCOURS2 = "/cparcours"
SlashCmdList["PARCOURS"] = Commande

-- ---------------------------------------------------------------------
-- Événements
-- ---------------------------------------------------------------------
local f = CreateFrame("Frame")
f:SetScript("OnEvent", function(_, event, texte)
    compteurEvenements[event] = (compteurEvenements[event] or 0) + 1
    if event == "CHAT_MSG_SYSTEM" then
        local ok, appris = pcall(LireMessageSysteme, texte)
        if ok and appris then suiviDirty = true end
        return
    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_UPDATE" or event == "TRADE_SKILL_LIST_UPDATE"
        or event == "NEW_RECIPE_LEARNED" then
        pcall(ScannerMetier)
    end
    if event == "PLAYER_LOGIN" then
        pcall(Migrer)
        local okI, errI = pcall(CreerIcone)
        if not okI then Print("Icône de minimap : erreur (" .. tostring(errI) .. ")") end
        local okS, errS = pcall(CreerSuivi)
        if not okS then Print("Suivi : erreur à la création (" .. tostring(errS) .. ")") end
        if DATA and DATA.metiers then
            Print(string.format("v0.8 chargé (%d métiers). /parcours ou l'icône de la minimap ouvre le journal.", #(DATA.ordre or {})))
        else
            Print("Données absentes : Donnees.lua introuvable ou vide.")
        end
    else
        suiviDirty = true
        if event ~= "BAG_UPDATE" and fenetre and fenetre:IsShown() then pcall(Rafraichir) end
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL", "BAG_UPDATE", "BAG_UPDATE_DELAYED", "CHAT_MSG_LOOT",
                    "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "TRADE_SKILL_LIST_UPDATE", "NEW_RECIPE_LEARNED", "CHAT_MSG_SYSTEM" }) do
    local ok, err = pcall(f.RegisterEvent, f, e)
    evenementsEtat[e] = ok and true or tostring(err)
end
