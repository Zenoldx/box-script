
local G = (getgenv and getgenv()) or _G
for _, key in ipairs({ "__KzoyzOpus", "__GTFarm" }) do -- __GTFarm = nama versi lama
    if G[key] and G[key].Cleanup then pcall(G[key].Cleanup) end
    G[key] = nil
end
local Session = {}
G.__KzoyzOpus = Session
local function alive()
    return G.__KzoyzOpus == Session
end

do
    local getId = getthreadidentity or get_thread_identity or getidentity or (syn and syn.get_thread_identity)
    if type(getId) == "function" then pcall(function() Session.Ident = getId() end) end
    Session.Exec = coroutine.create(function(job)
        while true do
            local ok, err = pcall(job)
            job = coroutine.yield(ok, err)
        end
    end)
end

---------------------------------------------------------------------
-- SERVICES & MODULE GAME
---------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldRemotes = ReplicatedStorage:WaitForChild("WorldRemotes")
-- Remote lama (versi game sebelum ByteNet). Hanya dipakai kalau fungsi baru tidak ada.
local SetTileRemote = WorldRemotes:FindFirstChild("SetTile")

local ItemDB = require(Shared.ItemDB)
local InventoryModule = require(Shared.Inventory)
local NetOk, Net = pcall(require, Shared.Net)

local GameGui = PlayerGui:WaitForChild("GameGui")
local ParticlesOk, ParticlesModule = pcall(require, GameGui:WaitForChild("Particles"))
local MenuModOk, MenuModule = pcall(require, GameGui:WaitForChild("WorldMenu"))
local RolesOk, RolesModule = pcall(require, Shared:FindFirstChild("Roles"))
local SfxOk, SfxModule = pcall(require, Shared:FindFirstChild("Sfx"))

local WindUI = (function()
    local urls = {
        "https://raw.githubusercontent.com/Footagesus/WindUI/1.6.66/dist/main.lua",
        "https://cdn.jsdelivr.net/gh/Footagesus/WindUI@1.6.66/dist/main.lua",
    }
    local lastError
    local maxAttempts = 4
    for attempt = 1, maxAttempts do
        for _, url in ipairs(urls) do
            -- Jika satu host timeout / HTTP 504, langsung coba host cadangan.
            local ok, body = pcall(function() return game:HttpGet(url) end)
            if ok and type(body) == "string" and #body > 0 then
                local compileOk, factory, compileError = pcall(loadstring, body)
                if compileOk and type(factory) == "function" then
                    -- Jalankan hanya sekali; error runtime tidak diulang lewat mirror lain.
                    local runOk, library = pcall(factory)
                    if not runOk then error("WindUI runtime: " .. tostring(library), 0) end
                    if type(library) ~= "table" then error("WindUI tidak mengembalikan library", 0) end
                    return library
                end
                lastError = compileOk and compileError or factory
            else
                lastError = tostring(url) .. ": " .. tostring(body)
            end
        end
        if attempt < maxAttempts then
            local delaySec = math.min(2 ^ attempt, 8)
            warn("[Kzoyz x Opus] Unduhan WindUI gagal; coba lagi dalam " .. delaySec .. " detik: " .. tostring(lastError))
            task.wait(delaySec)
        end
    end
    error("WindUI gagal diunduh: " .. tostring(lastError), 0)
end)()

---------------------------------------------------------------------
-- PENGATURAN & DATA
---------------------------------------------------------------------
local State = {
    Running = false,
    Mode = "Place + Break",       -- "Place + Break" | "Break saja" | "Place saja"
    PlaceMs = 250,                -- jeda setelah tiap place
    BreakMs = 220,                -- jeda tiap pukulan (normal 220)
    AfterBreakMs = 300,           -- jeda setelah block hancur
    HitsOverride = 0,             -- jumlah pukulan manual (0 = otomatis)
    BreakBackground = true,       -- selalu ikut pecah background (tanpa tombol)
    MultiTarget = 1,              -- jumlah tile dipukul bergantian (1 = biasa)
    SelectedId = nil,
    Offsets = {},                 -- tile yang dipilih di Grid
    CalibX = 0,
    CalibY = 0,
    AntiAfk = true,
    MutePunch = true,
    Visual = true,                -- animasi tangan saat break / place / tanam / panen (tampilan saja)
    LiteMode = false,
    AutoCollect = true,           -- ambil drop di tile yang dipilih
    CollectAround = false,        -- ambil drop di sekitar karakter (radius) kapan saja
    CollectRadius = 3,            -- jari-jari collect (tile), dipakai mode Remote
    CollectMode = "Sentuhan",     -- "Sentuhan" (badan, seperti main manual) / "Remote" (ambil dari jauh, cara lama)
    Override = nil,               -- Pabrik memakai tile & block sendiri
    Quiet = false,                -- tanpa notifikasi (dipakai Pabrik)
    Cycles = 0,
    Placed = 0,
    Broken = 0,
    Collected = 0,                -- jumlah drop yang diambil
    CollectFail = 0,              -- jumlah drop yang ditolak server
    LastAction = "-",
    SeedDrop = false,             -- seed hasil break sudah banyak -> drop ke titik drop
    SeedDropAt = 190,             -- drop kalau seed sudah sebanyak ini
    SeedKeep = 0,                 -- seed yang disisakan
    Dropped = 0,
    DropPause = false,            -- Auto Farm dijeda sementara (sedang pergi drop)
}

local Misc = {
    Speed = 100,      -- walkspeed % (100 = normal)
    InfJump = false,
    Ghost = false,    -- fly + tembus block
    UpHeld = false,   -- tombol ▲ di layar ditahan
    DownHeld = false, -- tombol ▼ di layar ditahan
    CustomName = true,          -- sembunyikan nickname lokal sampai script ditutup
    NameText = "",               -- nickname kosong / invisible (hanya di layar sendiri)
}

-- Auto Clear World
local Clear = {
    Running = false,
    IncludeBg = true,         -- ikut pecah background
    UseBlock = true,          -- taruh block kalau tidak ada pijakan
    ScaffoldId = nil,         -- block yang dipakai untuk pijakan
    Collect = true,           -- ambil drop tiap habis pecah
    Sweep = "Kiri → Kanan",   -- "Kiri → Kanan" atau "Zig-zag"
    Skip = {},                -- tile yang dilewati sementara
    TopRow = -1,              -- baris yang sedang dibersihkan
    DirRow = nil,             -- arah zig-zag untuk baris ini
    Dir = nil,
    Broken = 0,
    Remaining = -1,
    Status = "-",
}

-- Auto Splice: tanam Seed A lalu splice Seed B
local Splice = {
    Running = false,
    Roam = true,        -- keliling world pakai A* (false = hanya tile Grid)
    Roaming = false,
    A = nil,
    B = nil,
    Ms = 300,
    Made = 0,
    Planted = 0,
    Fail = {},
    Skip = {},
    Status = "-",
    Row = {},           -- baris yang sedang dikerjakan (rapi per baris)
}

-- Lahan (farm world): baris block dari atas ke bawah
local Land = {
    X0 = 0, X1 = 99,  -- kolom awal & akhir
    Y0 = 2,           -- baris block paling atas
    Gap = 2,          -- jarak antar baris (2 = ada 1 tile kosong untuk pohon)
    Rows = 10,        -- jumlah baris
    Stairs = true,    -- ujung baris dibuka bergantian kiri/kanan (jalan naik-turun seperti tangga)
}

-- Bangun Lahan
local Build = {
    Running = false,
    BlockId = nil,
    UseBlock = true,     -- boleh taruh block pijakan kalau baris pertama tidak terjangkau
    Produce = true,      -- block kurang -> produksi dulu (tanam & panen) sampai cukup
    ThenPabrik = false,  -- selesai -> langsung jalankan Pabrik
    Placed = 0,
    Phase = "-",
    Status = "-",
    Skip = {},
    FieldSkip = {},      -- tile panen / tanam yang dilewati sementara (produksi block)
    Row = {},            -- baris tanam produksi yang sedang dikerjakan
    Harvested = 0,
    Planted = 0,
    Dug = 0,             -- tile yang digali (block + background)
    Carved = {},         -- [idx] = true: block-nya digali Bangun Lahan (background ikut dipecah)
    Surface = nil,       -- y permukaan tanah asli (di bawahnya background ikut dipecah)
    Under = {},          -- [baris] = waktu: sementara pasang dari bawah (tidak bisa naik ke baris itu)
    BreakTimes = {},     -- tile yang terus balik lagi setelah digali
    Reserve = 0,         -- block yang tidak boleh dipasang (disisakan untuk bikin seed)
    RESERVE = 10,        -- sisakan block segini saat produksi
    BreakX = -1, BreakY = -1, -- posisi break produksi (belum diatur = otomatis di ujung kanan baris)
    Tiles = {},          -- tile break produksi, relatif ke posisi break ("dx,dy") (Grid mode Lahan)
}

-- Vending: isi stock dari drop / kosongkan sampai habis
local Vend = {
    Running = false,
    Mode = "Isi stock dari drop",  -- atau "Kosongkan sampai habis"
    Point = "",                    -- titik drop vending: "WORLD" / "WORLD:ID" (kosong = world ini)
    Status = "-",
    Stocked = 0, Taken = 0, Dropped = 0,
    Picked = {},                   -- [id] = jumlah hasil pungut yang belum masuk vending
    Items = {},                    -- item yang boleh diambil / di-stock / dikosongkan (kosong = semua)
    Kind = "Semua",                -- "Semua" / "Block saja" / "Seed saja"
    Seen = {},                     -- item yang pernah terlihat (vending, tas, drop) untuk daftar pilihan
    DropX = -1, DropY = -1,        -- posisi berdiri di titik drop vending (-1 = titik kedatangan)
    Carry = {},                    -- [id] = jumlah yang diambil dari vending (mode kosongkan)
}

-- Pabrik: break block -> tanam seed -> panen -> break lagi, seed lebihan di-drop
local Pabrik = {
    Running = false,
    SeedId = nil,
    BlockId = nil,
    WholeWorld = false,  -- tanam & panen di seluruh world (bukan hanya lahan)
    Tiles = {},          -- tile break, relatif ke posisi break ("dx,dy")
    BreakX = -1, BreakY = -1,
    BreakSec = 60,       -- lama 1 sesi break sebelum cek pohon lagi
    Drop = true,
    Keep = 50,           -- seed yang disisakan untuk ditanam lagi
    DropAt = 200,        -- drop kalau seed sudah sebanyak ini
    DropWorld = "",      -- "" = world ini | "WORLD" | "WORLD:ID"
    DropX = -1, DropY = -1,
    Harvested = 0,
    Planted = 0,
    Dropped = 0,
    Skip = {},
    Status = "-",
    Traveling = false,
    Home = "",
    Zone = nil,          -- tempat drop (tidak ikut di-collect), dipakai semua fitur drop
    Row = {},            -- baris tanam yang sedang dikerjakan
    Exit = "-",          -- kategori keluar world: "-" | "penjaga" | "otomatis"
    ExitWhy = nil,       -- alasan singkat (untuk status)
}

local Guard = {
    On = false,
    Who = "Staff (Mod/Dev)",   -- "Staff (Mod/Dev)" | "Semua pemain"
    StopAll = true,            -- diam semua aktivitas
    Leave = false,             -- keluar world
    AutoBack = true,           -- lanjut lagi setelah aman
    BackSec = 60,              -- (keluar world) tunggu sebelum masuk lagi
    CalmSec = 5,               -- (diam) tunggu sepi dulu sebelum lanjut
    Mode = "idle",             -- idle | pause | away | out | back
    Allow = {},                -- pemain biasa yang sudah ada saat Penjaga dinyalakan (diabaikan)
    Alerted = {},              -- sudah diberi peringatan
    Saved = nil,               -- aktivitas sebelum dihentikan
    Token = 0,
    BackAt = 0,
    CalmAt = nil,
    LeftFg = nil,
    BackText = nil,
    Status = "Mati",
    Detected = 0,
}

-- Farmer: panen & tanam otomatis
local Farmer = {
    Running = false,
    Harvest = true,
    Plant = true,
    Collect = true,
    UseBlock = false,   -- taruh block kalau tidak ada jalan
    ScaffoldId = nil,
    HarvestMs = 250,    -- jeda setelah tiap panen
    PlantMs = 250,      -- jeda setelah tiap tanam
    SeedId = nil,
    Skip = {},
    Harvested = 0,
    Planted = 0,
    Status = "-",
    Drop = false,       -- inventori hampir penuh -> drop hasil panen ke titik drop
    DropAt = 190,       -- drop kalau item hasil panen sudah sebanyak ini
    Keep = 50,          -- seed tanam yang disisakan
    Dropped = 0,
    Got = {},           -- seed pohon yang pernah dipanen (untuk cari item hasil panen)
    Row = {},           -- baris tanam yang sedang dikerjakan (tanam rapi per baris)
}

-- Tombol gerak buatan (dipakai Clear & Farmer)
local AutoInput = { active = false, left = false, right = false, jump = false, down = false }

-- Auto Chat
local Spam = {
    On = false,
    Texts = {},         -- daftar pesan, dikirim bergantian
    IntervalSec = 6,
    Index = 1,
    Sent = 0,
    Last = "-",
}

local Refs = {
    World = nil,      -- data world (fg, bg, ukuran)
    Inv = nil,        -- inventori
    SetTile = nil,    -- fungsi place game
    State = nil,      -- posisi karakter
    Punch = nil,      -- fungsi pukul game
    Particles = {},   -- particle (untuk mode Lite)
    Menu = nil,       -- menu game (keluar / masuk world)
    Gems = nil,       -- update angka gems
    Hud = nil,        -- jangkauan pukul & place
    Trees = nil,      -- data pohon (waktu tanam)
    Others = nil,     -- daftar pemain lain di world (untuk Penjaga)
}

-- Daftar drop di world (diambil dari game)
local Drops = { list = nil, update = nil, brokeAt = {} }
-- Animasi aksi: fungsi gambar tangan game + nomor upvalue "aksi terakhir" (diisi saat hubungkan)
local Anim = { fn = nil, idx = nil, set = nil }
local DropFailUntil = {}   -- drop yang ditolak, dicoba lagi nanti

local UI = {}

-- Jalankan fn dengan izin penuh. Hasil: ok, err (seperti pcall)
function UI.ident()
    local getId = getthreadidentity or get_thread_identity or getidentity or (syn and syn.get_thread_identity)
    if type(getId) ~= "function" then return nil end
    local ok, v = pcall(getId)
    return ok and v or nil
end
function UI.exec(fn)
    local setId = setthreadidentity or set_thread_identity or setidentity or (syn and syn.set_thread_identity)
    local function elevate()
        if Session.Ident and type(setId) == "function" then pcall(setId, Session.Ident) end
    end
    local err1 = nil
    local co = Session.Exec
    if co and coroutine.status(co) == "suspended" then
        local okR, ok, err = coroutine.resume(co, function()
            elevate()
            fn()
        end)
        if okR and ok ~= false then return true end
        err1 = okR and err or ok
    end
    -- cadangan: jalankan di thread ini (setelah identitasnya dikembalikan)
    elevate()
    local ok2, err2 = pcall(fn)
    if ok2 then return true end
    return false, tostring(err2 or err1)
end
UI.Jobs = {}
function UI.later(key, fn, delay)
    UI.Jobs[key] = { fn = fn, at = os.clock() + (delay or 0) }
end
-- Jalankan pekerjaan UI yang sudah waktunya (dipanggil oleh thread INIT, lihat bagian INIT)
function UI.runJobs()
    local now = os.clock()
    local due = {}
    for key, job in pairs(UI.Jobs) do
        if now >= job.at then due[#due + 1] = key end
    end
    for _, key in ipairs(due) do
        local job = UI.Jobs[key]
        if job and now >= job.at then
            UI.Jobs[key] = nil
            local ok, err = pcall(job.fn)
            if not ok then warn("[Kzoyz x Opus] UI job " .. tostring(key) .. ": " .. tostring(err)) end
        end
    end
end
local Connections = {}
local HitCount = {}   -- hitung pukulan (cadangan)
local PlacedAt = {}   -- kapan tile di-place

---------------------------------------------------------------------
-- BAHASA (Indonesia / English)
---------------------------------------------------------------------
-- Cara kerja:
--   - Semua teks script ditulis dalam Bahasa Indonesia.
--   - Kalau English dipilih, I18N.T(teks) menerjemahkan:
--       1. teks utuh (judul & deskripsi menu) dari daftar EN
--       2. teks yang berubah-ubah (status, notifikasi) per frasa dari daftar PH
--   - Menu WindUI dibungkus (I18N.wrap) supaya judul, deskripsi & isi status ikut diterjemahkan.
local I18N = { Lang = "id", Saved = "id", Ask = true }

do (function() -- fungsi sendiri: variabel di dalam tidak ikut batas 200 local

I18N.EN = {
    -- grup sidebar & tab
    ["Fitur"] = "Features", ["Keamanan"] = "Security", ["Setelan"] = "Setup",
    ["Pengaturan"] = "Settings", ["Penjaga"] = "Guard", ["Statistik"] = "Stats", ["Tas"] = "Bag",
    ["Lahan"] = "Land", ["Pabrik"] = "Factory", ["Koneksi"] = "Connection",
    -- kotak
    ["Kontrol"] = "Controls", ["Mode & Kecepatan"] = "Mode & Speed", ["Kecepatan"] = "Speed",
    ["Karakter"] = "Character", ["Opsi"] = "Options", ["Pesan"] = "Messages",
    ["Aksi saat terdeteksi"] = "Action when detected", ["Waktu"] = "Timing", ["Lainnya"] = "Other",
    ["Quest Harian"] = "Daily Quests", ["Pohon (siap panen)"] = "Trees (ready to harvest)",
    ["Auto Recycle (buang item)"] = "Auto Recycle (trash items)", ["Bentuk lahan"] = "Land shape",
    ["Pilihan"] = "Options", ["Posisi & tile break"] = "Break position & tiles",
    ["Koreksi posisi"] = "Position correction", ["Yang dikirim"] = "What to send",
    -- Farm
    ["Bisa juga lewat tombol START di Grid"] = "Can also use the START button in the Grid",
    ["Ambil drop di tile yang dipilih"] = "Pick up drops on the selected tiles",
    ["Collect di sekitar karakter"] = "Collect around character",
    ["Ambil semua drop dalam radius, kapan saja"] = "Pick up all drops within the radius, anytime",
    ["Radius collect (tile)"] = "Collect radius (tiles)",
    ["Dipakai juga Clear, Farmer, Splice & Pabrik. Terlalu jauh bisa ditolak server"] =
        "Also used by Clear, Farmer, Splice & Factory. Too far may be rejected by the server",
    ["Buka Grid Tile"] = "Open Tile Grid",
    ["Kotak 5x5, tengah = karakter"] = "5x5 grid, center = character",
    -- Clear
    ["Status Clear"] = "Clear Status",
    ["Bersihkan dari baris atas ke bawah"] = "Clear from the top row down",
    ["Arah sapu"] = "Sweep direction",
    ["Zig-zag lebih cepat (tidak balik ke kiri)"] = "Zig-zag is faster (no going back left)",
    ["Pakai block pijakan"] = "Use scaffold blocks",
    ["Taruh block untuk lewat jurang / naik ke block melayang"] = "Place blocks to cross gaps / reach floating blocks",
    ["Block pijakan"] = "Scaffold block",
    ["Block yang dipakai untuk pijakan"] = "Block used as scaffold",
    ["Auto collect tiap habis pecah"] = "Auto collect after each break",
    ["Ambil drop di sekitar karakter"] = "Pick up drops around the character",
    ["Reset tile yang dilewati"] = "Reset skipped tiles",
    ["Coba lagi tile yang tadi gagal"] = "Retry tiles that failed",
    -- Farmer
    ["Status Farmer"] = "Farmer Status",
    ["Jalankan Farmer"] = "Run Farmer",
    ["Panen pohon siap & tanam seed otomatis"] = "Harvest ready trees & plant seeds automatically",
    ["Seed untuk ditanam"] = "Seed to plant",
    ["Hanya seed yang ada di inventori"] = "Only seeds in your inventory",
    ["Refresh daftar seed"] = "Refresh seed list",
    ["Hanya pohon yang sudah siap"] = "Only trees that are ready",
    ["Tanam di atas block yang kosong"] = "Plant on top of empty blocks",
    ["Ambil hasil panen di sekitar karakter"] = "Pick up harvest drops around the character",
    ["Jeda setelah tiap panen"] = "Delay after each harvest",
    ["Jeda setelah tiap tanam seed"] = "Delay after each seed planted",
    ["Taruh block kalau tidak ada jalan (block tetap tertinggal)"] = "Place blocks when there is no path (blocks stay behind)",
    -- Speed & opsi
    ["Place semua tile dulu, lalu break"] = "Place all tiles first, then break",
    ["Jeda setelah tiap place"] = "Delay after each place",
    ["Jeda tiap pukulan (normal 220). Dipakai juga Clear"] = "Delay per hit (normal 220). Also used by Clear",
    ["Auto Farm: tile dipukul bergantian (seperti 2 jari). Pakai Rayman's Fist = 2-3 tile segaris sekali pukul"] =
        "Auto Farm: tiles are hit in turns (like 2 fingers). With Rayman's Fist = 2-3 tiles in a line per punch",
    ["Jeda setelah hancur 
