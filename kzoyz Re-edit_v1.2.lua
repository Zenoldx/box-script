
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
    for attempt = 1, 2 do
        for _, url in ipairs(urls) do
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
                lastError = body
            end
        end
        if attempt < 2 then task.wait(1) end
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
    CustomName = true,          -- watermark nama (selalu aktif, mati hanya saat script ditutup)
    NameText = "Kzoyz x Opus",  -- teks watermark
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
    ["Jeda setelah hancur (ms)"] = "Delay after break (ms)",
    ["Tunggu sebelum lanjut ke tile berikutnya"] = "Wait before moving to the next tile",
    ["Mode Lite"] = "Lite Mode",
    ["Matikan particle & suara (HP low-end)"] = "Turn off particles & sounds (low-end phones)",
    ["Mute suara pukulan"] = "Mute punch sounds",
    ["Pukulan per block (cadangan)"] = "Hits per block (fallback)",
    ["Dipakai kalau 'Pukul: TIDAK'. 0 = otomatis"] = "Used when 'Punch: NO'. 0 = automatic",
    ["Pilih Block"] = "Select Block",
    ["Hanya item yang bisa di-place"] = "Only placeable items",
    ["Refresh daftar"] = "Refresh list",
    ["Lompat di udara (bisa kena rollback)"] = "Jump mid-air (may get rolled back)",
    ["Fly + Tembus Block"] = "Fly + Noclip",
    ["Tembus block, pakai tombol ▲/▼ (bisa kena rollback)"] = "Pass through blocks, use the ▲/▼ buttons (may get rolled back)",
    ["Bahasa / Language"] = "Language / Bahasa",
    ["Titik Drop"] = "Drop Point", ["Atur titik drop"] = "Set drop point", ["Drop otomatis"] = "Auto drop",
    ["Seed sudah banyak: jeda, drop ke titik drop (tab Titik Drop), balik ke posisi farm"] =
        "Too many seeds: pause, drop at the drop point (Drop Point tab), return to farm position",
    ["Seed dari block yang dipilih"] = "Seeds of the selected block",
    ["Drop kalau hampir penuh"] = "Drop when almost full",
    ["Hasil panen (block & seed) dibawa ke titik drop (tab Titik Drop)"] =
        "Harvest items (blocks & seeds) are taken to the drop point (Drop Point tab)",
    ["Drop kalau item sudah"] = "Drop when an item reaches",
    ["Maksimal 200 per item"] = "Max 200 per item",
    ["Sisakan seed tanam"] = "Seeds to keep for planting",
    ["Seed yang dipilih untuk ditanam tidak di-drop semua"] = "The planting seed is not dropped completely",
    ["Ke titik drop (tab Titik Drop)"] = "To the drop point (Drop Point tab)",
    ["Block kurang diproduksi dulu, lalu dipasang dari atas seperti ular (tanpa pijakan)"] =
        "Missing blocks are produced first, then placed from the top like a snake (no scaffolding)",
    ["Gali dulu dari permukaan sampai bawah, lalu pasang baris naik sampai atas (baris jadi jembatan). Block habis: produksi 1 baris"] =
        "Digs from the surface down to the bottom first, then places rows upward to the top (each row is its own bridge). Out of blocks: produces on 1 row",
    ["Baris block paling atas. Baris di bawahnya otomatis sampai di atas bedrock (tanah digali)"] =
        "Top block row. Rows below go automatically down to just above bedrock (dirt is dug out)",
    ["Berdiri di atas block pertama baris paling atas, lalu tekan (tangga kiri di sebelah kirinya)"] =
        "Stand on the first block of the top row, then press (left stairs go to its left)",
    ["Baris block paling atas. Baris di bawahnya dibuat otomatis sampai tanah"] =
        "Top block row. Rows below are made automatically down to the ground",
    ["Ganti bahasa, lalu execute ulang"] = "Change language, then re-execute",
    ["Mode collect"] = "Collect mode", ["Sentuhan"] = "Touch",
    ["Berlaku untuk semua fitur. Sentuhan = seperti main manual. Remote = ambil dari jauh (cara lama, cepat)"] =
        "Applies to all features. Touch = like manual play. Remote = picks up from a distance (old method, fast)",
    ["Ambil drop di semua tile grid (caranya ikut Mode collect)"] = "Pick up drops on all grid tiles (method follows Collect mode)",
    ["Radius collect (mode Remote)"] = "Collect radius (Remote mode)",
    ["Jarak ambil drop di sekitar karakter (tile)"] = "Pickup distance around the character (tiles)",
    ["Animasi aksi"] = "Action animation",
    ["Tangan bergerak saat break / place / tanam / panen + efek place. Matikan untuk hemat FPS"] =
        "Arm moves on break / place / plant / harvest + place effect. Turn off to save FPS",
    ["Jenis item"] = "Item type",
    ["Berlaku untuk isi stock (drop yang dipungut) dan kosongkan (vending yang diambil)"] =
        "Applies to stock (drops picked up) and empty (vendings taken from)",
    ["Block saja"] = "Blocks only", ["Seed saja"] = "Seeds only",
    ["Item yang diambil"] = "Items to take",
    ["Bisa pilih banyak. Kosong = semua item. Daftar: isi vending, tas & drop yang terlihat"] =
        "Multi-select. Empty = all items. List: vending contents, backpack & seen drops",
    ["Muat ulang daftar item"] = "Reload item list",
    ["Pilih item"] = "Pick items",
    ["Tambah item yang dipegang"] = "Add the held item",
    ["Pilih item di tas game (dipegang), lalu tekan. Masuk ke daftar item yang diambil"] =
        "Select an item in the game backpack (held), then press. Adds it to the items to take",
    ["Hapus pilihan item"] = "Clear item selection",
    ["Kembali ke semua item"] = "Back to all items",
    ["Simpan posisi drop vending (posisi karakter)"] = "Save vending drop position (character position)",
    ["Berdiri di tempat drop (boleh di world titik drop), lalu tekan. Dipakai mode isi stock & kosongkan"] =
        "Stand at the drop spot (can be in the drop-point world), then press. Used by stock & empty modes",
    ["Hapus posisi drop vending"] = "Clear vending drop position",
    ["Drop / tunggu di titik kedatangan (pintu) saja"] = "Drop / wait at the arrival point (door) only",
    ["Ambil item dari vending, tas & drop di world ini"] = "Read items from vendings, backpack & drops in this world",
    ["Posisi break produksi = posisi karakter"] = "Production break position = character position",
    ["Berdiri di tempat break lalu tekan. Tekan lagi di tempat yang sama = kembali otomatis"] =
        "Stand at the break spot and press. Press again at the same spot = back to automatic",
    ["Pilih tile break produksi (Grid)"] = "Pick production break tiles (Grid)",
    ["Grid terbuka dalam mode Lahan (terpisah dari Auto Farm & Pabrik)"] =
        "Grid opens in Land mode (separate from Auto Farm & Factory)",
    ["Status Vending"] = "Vending Status",
    ["Jalankan Vending"] = "Run Vending",
    ["Jalankan di world vending milikmu"] = "Run it in your vending world",
    ["Titik drop vending"] = "Vending drop point",
    ["WORLD atau WORLD:ID (kosong = world ini). Isi stock: ambil drop di sini. Kosongkan: drop di sini"] =
        "WORLD or WORLD:ID (empty = this world). Stock: picks up drops here. Empty: drops here",
    ["Isi stock dari drop"] = "Stock from drops",
    ["Kosongkan sampai habis"] = "Empty until done",
    ["Drop di semua tile grid diambil dengan sentuhan badan (melangkah / lompat), tanpa remote"] =
        "Drops on every grid tile are picked up by body touch (step / jump), no remote",
    ["Drop di sekitar disusuri sampai tersentuh badan (tanpa remote)"] =
        "Nearby drops are walked over until the body touches them (no remote)",
    -- Chat
    ["Status Chat"] = "Chat Status",
    ["Daftar pesan"] = "Message list",
    ["Pisahkan dengan |   contoh: halo|jual dirt"] = "Separate with |   example: hi|selling dirt",
    ["pesan 1|pesan 2|pesan 3"] = "message 1|message 2|message 3",
    ["Interval (detik)"] = "Interval (seconds)",
    ["Jeda antar pesan (min 3 detik)"] = "Delay between messages (min 3 seconds)",
    ["Kirim pesan bergantian sesuai urutan"] = "Send messages in order, one after another",
    ["Kirim 1 pesan sekarang"] = "Send 1 message now",
    ["Tes kirim pesan berikutnya"] = "Test sending the next message",
    ["Isi daftar pesan dulu (tekan Enter setelah mengetik)"] = "Fill in the message list first (press Enter after typing)",
    -- Penjaga
    ["Status Penjaga"] = "Guard Status",
    ["Mati"] = "Off",
    ["Aktifkan Penjaga"] = "Enable Guard",
    ["Pantau Mod / Dev / pemain yang masuk world"] = "Watch for Mods / Devs / players entering the world",
    ["Yang dideteksi"] = "Detect",
    ["Semua pemain: yang sudah ada saat dinyalakan diabaikan"] = "All players: those already here when enabled are ignored",
    ["Diam semua aktivitas"] = "Pause all activities",
    ["Keluar world"] = "Leave world",
    ["Langsung keluar world saat terdeteksi"] = "Leave the world immediately when detected",
    ["Lanjut otomatis setelah aman"] = "Auto resume when safe",
    ["Keluar world: masuk lagi, cek, lalu lanjut aktivitas sebelumnya"] = "Leave world: rejoin, check, then resume previous activity",
    ["Masuk world lagi setelah (detik)"] = "Rejoin world after (seconds)",
    ["Untuk mode keluar world"] = "For leave-world mode",
    ["Tunggu aman (detik)"] = "Safe wait (seconds)",
    ["Untuk mode diam: jeda setelah mereka pergi"] = "For pause mode: delay after they leave",
    ["Abaikan pemain yang ada sekarang"] = "Ignore players here now",
    ["Untuk teman / akun sendiri (staff tetap dideteksi)"] = "For friends / alt accounts (staff are still detected)",
    ["Batalkan tunggu / lanjut"] = "Cancel wait / resume",
    ["Hentikan proses keluar-masuk & lanjut otomatis"] = "Stop the leave-rejoin process & auto resume",
    ["Dibatalkan"] = "Cancelled",
    -- Bonus
    ["Klaim hadiah quest yang sudah selesai"] = "Claim rewards for finished quests",
    ["Cek quest sekarang"] = "Check quests now",
    ["Tukar semua code aktif yang belum dipakai"] = "Redeem all active codes not used yet",
    ["Cek code sekarang"] = "Check codes now",
    ["Redeem code manual"] = "Redeem code manually",
    ["Ketik code lalu tekan Enter"] = "Type a code then press Enter",
    ["KODE"] = "CODE",
    -- Growscan
    ["Info World"] = "World Info",
    ["Tekan Scan sekarang"] = "Press Scan now",
    ["Update otomatis tiap 2 detik"] = "Auto update every 2 seconds",
    ["Scan sekarang"] = "Scan now",
    ["Cari item"] = "Search item",
    ["Saring nama item (kosongkan = semua)"] = "Filter item name (empty = all)",
    ["contoh: seed"] = "example: seed",
    ["Daftar"] = "List",
    -- Statistik
    ["Sesi ini"] = "This session",
    ["Reset statistik"] = "Reset stats",
    ["Mulai hitung dari nol"] = "Start counting from zero",
    ["Kirim ke Discord sekarang"] = "Send to Discord now",
    ["Perlu webhook di tab Discord"] = "Needs a webhook in the Discord tab",
    ["Aktifkan webhook Discord dulu"] = "Enable the Discord webhook first",
    ["Direset"] = "Reset",
    ["Masuk antrian kirim"] = "Added to send queue",
    -- Tas
    ["Item yang dipilih di-recycle otomatis"] = "Selected items are recycled automatically",
    ["Item yang di-recycle"] = "Items to recycle",
    ["Bisa pilih banyak. Tool & lock tidak ditampilkan"] = "Multiple allowed. Tools & locks are not shown",
    ["Recycle kalau jumlah >="] = "Recycle when amount >=",
    ["200 = hanya saat penuh 1 slot"] = "200 = only when a slot is full",
    ["Sisakan"] = "Keep",
    ["Jumlah yang tidak ikut di-recycle"] = "Amount not recycled",
    ["Refresh daftar item"] = "Refresh item list",
    ["100 WL -> 1 DL, 100 DL -> 1 BGL (sama seperti game)"] = "100 WL -> 1 DL, 100 DL -> 1 BGL (same as the game)",
    -- Splice
    ["Status Splice"] = "Splice Status",
    ["Tanam Seed A lalu splice Seed B"] = "Plant Seed A then splice Seed B",
    ["Seed A (ditanam)"] = "Seed A (planted)",
    ["Seed B (di-splice)"] = "Seed B (spliced)",
    ["Keliling world (A*)"] = "Roam world (A*)",
    ["Nyala: jalan ke seluruh world. Mati: hanya tile Grid 5x5"] = "On: walk the whole world. Off: only the 5x5 Grid tiles",
    ["Jeda tanam / splice (ms)"] = "Plant / splice delay (ms)",
    -- Lahan
    ["Status Lahan"] = "Land Status",
    ["Bangun Lahan"] = "Build Land",
    ["Hitung block, produksi kalau kurang, lalu pasang dari baris bawah"] = "Count blocks, produce if short, then place from the bottom row",
    ["Block lahan"] = "Land block",
    ["Block padat dari inventori"] = "Solid block from inventory",
    ["X awal"] = "Start X",
    ["Kolom paling kiri"] = "Leftmost column",
    ["X akhir"] = "End X",
    ["Kolom paling kanan (lebih dari lebar world = sampai ujung)"] = "Rightmost column (beyond world width = to the edge)",
    ["Y baris atas"] = "Top row Y",
    ["Baris block paling atas (minimal 1)"] = "Topmost block row (minimum 1)",
    ["Jarak antar baris"] = "Row spacing",
    ["2 = y1, y3, y5.. | 3 = y1, y4, y7.. (maks 3 supaya bisa lompat naik)"] = "2 = y1, y3, y5.. | 3 = y1, y4, y7.. (max 3 so you can jump up)",
    ["Jumlah baris"] = "Number of rows",
    ["Tangga di pojok kiri-kanan"] = "Stairs at left-right corners",
    ["Ujung baris dibuka bergantian, jadi bisa turun-naik zig-zag"] = "Row ends open alternately, so you can go up/down in a zig-zag",
    ["Pakai posisi karakter sebagai pojok kiri-atas"] = "Use character position as top-left corner",
    ["X awal = kolom karakter, Y baris atas = tile di bawah kaki"] = "Start X = character column, top row Y = tile under the feet",
    ["Produksi block kalau kurang"] = "Produce blocks if short",
    ["Tanam & panen seed block itu dulu sampai cukup"] = "Plant & harvest that block's seed first until enough",
    ["Boleh taruh block pijakan"] = "Allow scaffold blocks",
    ["Kalau baris paling bawah tidak terjangkau dari tanah"] = "If the bottom row can't be reached from the ground",
    ["Lanjut Pabrik setelah selesai"] = "Start Factory when finished",
    -- Pabrik
    ["Status Pabrik"] = "Factory Status",
    ["Jalankan Pabrik"] = "Run Factory",
    ["Break -> tanam -> panen -> break lagi, seed lebihan di-drop"] = "Break -> plant -> harvest -> break again, extra seeds are dropped",
    ["Seed pabrik"] = "Factory seed",
    ["Block-nya otomatis (contoh: Dirt Seed -> Dirt)"] = "Block is automatic (example: Dirt Seed -> Dirt)",
    ["Tanam di seluruh world"] = "Plant in the whole world",
    ["Mati = hanya di lahan (tab Lahan)"] = "Off = only on the land (Land tab)",
    ["Pakai posisi sekarang untuk break"] = "Use current position for breaking",
    ["Berdiri di tempat break, lalu tekan"] = "Stand at the break spot, then press",
    ["Pilih tile break (Grid)"] = "Select break tiles (Grid)",
    ["Grid terbuka dalam mode Pabrik (terpisah dari tile Auto Farm)"] = "Grid opens in Factory mode (separate from Auto Farm tiles)",
    ["Lama 1 sesi break (detik)"] = "Break session length (seconds)",
    ["Setelah ini cek pohon siap dulu"] = "After this, check for ready trees first",
    ["Sisakan seed"] = "Seeds to keep",
    ["Untuk ditanam lagi"] = "For replanting",
    ["Drop kalau seed sudah"] = "Drop when seeds reach",
    ["Contoh 200 & sisakan 50 = drop 150"] = "Example 200 & keep 50 = drop 150",
    ["World drop"] = "Drop world",
    ["Kosong = world ini | WORLD | WORLD:ID (masuk lewat pintu ID)"] = "Empty = this world | WORLD | WORLD:ID (enter via door ID)",
    ["Pakai posisi sekarang untuk drop"] = "Use current position for dropping",
    ["Berdiri di tempat drop (boleh di world lain), lalu tekan"] = "Stand at the drop spot (can be another world), then press",
    ["Hapus posisi drop"] = "Clear drop position",
    ["Drop di titik kedatangan (pintu) saja"] = "Drop at the arrival point (door) instead",
    ["Ada block tapi posisi / tile break belum diatur"] = "Has blocks but break position / tiles are not set",
    ["Gagal jalan ke posisi break, dicoba lagi nanti"] = "Failed to walk to break position, retrying later",
    -- Koneksi & config
    ["Referensi game"] = "Game references",
    ["Hubungkan ke game"] = "Connect to game",
    ["Pakai setelah pindah world"] = "Use after changing worlds",
    ["Simpan pengaturan otomatis, dimuat lagi saat execute"] = "Save settings automatically, loaded again on execute",
    ["Simpan config sekarang"] = "Save config now",
    ["Hapus file config, lalu execute ulang"] = "Delete the config file, then re-execute",
    ["Koreksi posisi X"] = "Position correction X",
    ["Isi 1 / -1 kalau tile meleset"] = "Enter 1 / -1 if tiles are off",
    ["Koreksi posisi Y"] = "Position correction Y",
    ["Masuk lagi & lanjut aktivitas kalau terlempar"] = "Rejoin & resume activity if kicked out",
    ["Terlempar dari world"] = "Kicked from world",
    ["World ditutup / di-kick: masuk lagi ke world yang sama"] = "World closed / kicked: rejoin the same world",
    ["Selalu kembali ke world"] = "Always return to world",
    ["Kalau berada di luar world (layar pilih world), masuk lagi otomatis"] = "If outside a world (world select screen), rejoin automatically",
    ["World tujuan"] = "Target world",
    ["Kosongkan = world terakhir yang kamu masuki"] = "Empty = the last world you entered",
    ["NAMAWORLD"] = "WORLDNAME",
    ["Rejoin world sekarang"] = "Rejoin world now",
    ["Keluar lalu masuk lagi, aktivitas dilanjutkan"] = "Leave and rejoin, activity resumes",
    ["Disconnect dari server"] = "Disconnected from server",
    ["Teleport ulang ke game lalu masuk world terakhir"] = "Teleport back to the game and enter the last world",
    ["Jeda sebelum masuk lagi (detik)"] = "Delay before rejoining (seconds)",
    ["URL script (untuk rejoin server)"] = "Script URL (for server rejoin)",
    ["Link raw script ini, supaya jalan lagi setelah teleport. Kosong = pakai autoexec"] =
        "Raw link of this script, so it runs again after teleport. Empty = use autoexec",
    ["Sedang proses masuk world, tunggu dulu"] = "Already entering a world, please wait",
    ["World tujuan belum ada. Isi 'World tujuan' atau masuk world dulu"] = "No target world yet. Fill in 'Target world' or enter a world first",
    -- Discord
    ["Notifikasi Discord"] = "Discord Notifications",
    ["Kirim kabar penting ke channel Discord kamu"] = "Send important updates to your Discord channel",
    ["URL Webhook"] = "Webhook URL",
    ["Channel Discord > Edit > Integrasi > Webhook > Salin URL"] = "Discord channel > Edit > Integrations > Webhook > Copy URL",
    ["Tes kirim"] = "Test send",
    ["Laporan statistik (menit)"] = "Stats report (minutes)",
    ["Kirim statistik sesi tiap X menit. 0 = mati"] = "Send session stats every X minutes. 0 = off",
    ["Mod / Dev / pemain masuk world"] = "Mod / Dev / player entered world",
    ["Aktivitas berhenti (block habis / error)"] = "Activity stopped (out of blocks / error)",
    ["Quest diklaim / redeem berhasil"] = "Quest claimed / redeem successful",
    ["Terlempar / disconnect / masuk lagi"] = "Kicked / disconnected / rejoined",
    ["Pabrik drop seed / lahan selesai / berhenti"] = "Factory dropped seeds / land done / stopped",
    ["Isi URL webhook dulu"] = "Fill in the webhook URL first",
    ["Pesan tes masuk antrian"] = "Test message queued",
    ["URL webhook tidak valid"] = "Invalid webhook URL",
    ["Tes notifikasi dari Kzoyz x Opus"] = "Test notification from Kzoyz x Opus",
    -- pilihan dropdown
    ["Kiri → Kanan"] = "Left → Right", ["Semua pemain"] = "All players", ["Semua"] = "All",
    ["Depan"] = "Front", ["Break saja"] = "Break only", ["Place saja"] = "Place only",
    ["(memuat...)"] = "(loading...)", ["(inventori kosong)"] = "(inventory empty)",
    ["(inventori belum terbaca)"] = "(inventory not read yet)",
    ["(inventori kosong / belum terbaca)"] = "(inventory empty / not read yet)",
    ["Channel chat world belum ada (masuk world dulu)"] = "World chat channel not found (enter a world first)",
    ["Daftar pesan kosong"] = "Message list is empty",
    ["Inventori penuh"] = "Inventory full",
    ["Tanya bahasa saat execute"] = "Ask language on execute",
    ["Execute ulang untuk ganti bahasa / Re-execute to apply"] = "Re-execute to apply the new language",
    ["Munculkan pilihan bahasa tiap execute"] = "Show the language choice on every execute",
    -- Grid
    ["Grid Tile"] = "Tile Grid", ["Bersihkan pilihan"] = "Clear selection",
    ["Tile Break Pabrik"] = "Factory Break Tiles", ["START PABRIK"] = "START FACTORY", ["STOP PABRIK"] = "STOP FACTORY",
}

-- Frasa untuk teks yang berubah-ubah (status, notifikasi, pesan Discord)
I18N.PH = {
    { "Data world belum ketemu", "World data not found" }, { "Data drop belum ketemu", "Drop data not found" },
    { "Data pohon belum ketemu", "Tree data not found" }, { "Data pohon tidak ketemu", "Tree data not found" },
    { "Tekan 'Hubungkan ke game'", "Press 'Connect to game'" }, { "Hubungkan ke game", "Connect to game" },
    { "Kamu belum masuk world", "You are not in a world yet" }, { "belum masuk world", "not in a world yet" },
    { "tidak di world", "not in a world" },
    { "Menunggu karakter / world...", "Waiting for character / world..." },
    { "Menunggu pohon siap", "Waiting for trees to be ready" }, { "Menunggu", "Waiting" },
    { "Dihentikan karena", "Stopped because" }, { "Dihentikan", "Stopped" }, { "dimulai", "started" },
    { "hubungkan ulang ke game", "reconnecting to game" },
    { "Dijeda Penjaga", "Paused by Guard" }, { "Dijeda", "Paused" }, { "Waspada", "Alert" }, { "Ada:", "Present:" },
    { "Aman", "Safe" }, { "Pemain di world", "Players in world" }, { "Staff online di server", "Staff online on server" },
    { "Terdeteksi", "Detected" }, { "kali", "times" }, { "tidak ada", "none" },
    { "pemain diabaikan", "players ignored" },
    { "Masuk world", "Entered world" }, { "Keluar world", "Leave world" },
    { "Masuk lagi dalam", "Rejoining in" }, { "Masuk lagi ke", "Rejoining" }, { "Masuk lagi berhasil", "Rejoined" },
    { "Masuk lagi", "Rejoin" }, { "Masuk ke", "Entering" }, { "Masih ada", "Still here:" }, { "Keluar lagi", "Leaving again" },
    { "Sudah keluar world", "Already left the world" }, { "lanjut otomatis mati", "auto resume off" },
    { "Di luar world", "Outside the world" }, { "Mereka sudah pergi", "They left" }, { "Lanjut dalam", "Resuming in" },
    { "Sudah aman", "Safe now" }, { "World aman", "World is safe" }, { "World sudah beda", "Different world" },
    { "aktivitas tidak dilanjutkan", "activity not resumed" }, { "aktivitas dilanjutkan", "activity resumed" },
    { "aktivitas hanya dijeda", "activity only paused" },
    { "lanjut aktivitas", "resuming activity" }, { "Lanjut aktivitas", "Resuming activity" },
    { "Gagal balik ke posisi farm", "Failed to return to farm position" },
    { "Auto Farm tidak dilanjutkan", "Auto Farm not resumed" },
    { "Jalan balik ke posisi farm", "Walking back to farm position" },
    { "Jalan ke posisi break", "Walking to break position" }, { "Jalan ke posisi drop", "Walking to drop position" },
    { "Cari jalan A* ke", "Finding A* path to" }, { "Jalan ke", "Walking to" }, { "Lompati lubang ke", "Jumping gap to" },
    { "Lompat ke", "Jumping to" }, { "Turun ke", "Dropping down to" }, { "Naik pakai block ke", "Climbing with block to" },
    { "Taruh block pijakan", "Placing scaffold block" },
    { "di bawahnya berbahaya", "dangerous below" }, { "di bawahnya jurang", "pit below" },
    { "Lewati pijakan", "Skip foothold" }, { "Lewati", "Skip" },
    { "Pukul", "Hit" }, { "Pecah", "Broke" }, { "Panen", "Harvest" }, { "Tanam", "Plant" },
    { "Pasang lahan: sisa", "Placing land: remaining" }, { "Pasang", "Place" },
    { "Gali: sisa", "Digging: remaining" }, { "Gali", "Dig" }, { "Pukul", "Punch" },
    { "Tile Break Lahan", "Land Break Tiles" }, { "START LAHAN", "START LAND" }, { "STOP LAHAN", "STOP LAND" },
    { "Semua vending item terpilih sudah kosong", "All vendings of the selected items are empty" },
    { "semua item yang bisa dijual", "all sellable items" },
    { " - coba lagi", " - retrying" }, { "Tambah stock gagal:", "Adding stock failed:" },
    { "Menjauh dari drop sendiri supaya bisa dipungut", "Stepping away from own drops so they can be picked up" },
    { "Item terpilih sudah habis. Tidak diambil (bukan item terpilih):", "Selected items are empty. Not taken (not selected):" },
    { "Hapus pilihan item untuk ambil semua", "Clear the item selection to take everything" }, { "Cek ulang isi vending...", "Re-checking vending contents..." },
    { "Daftar item gagal dimuat:", "Item list failed to load:" }, { "tidak terbaca", "not readable" },
    { "Vending milikmu di", "Your vendings in" },
    { "Jalan ke posisi drop vending", "Walking to the vending drop position" },
    { "Tidak bisa jalan ke posisi drop vending", "Can't reach the vending drop position" },
    { "Tas penuh: atur titik drop vending (WORLD / WORLD:ID / simpan posisi XY)", "Backpack full: set the vending drop point (WORLD / WORLD:ID / save XY position)" },
    { "Daftar item:", "Item list:" }, { "Item dipilih:", "Item selected:" },
    { "Pegang dulu block / seed di tas game (bukan tool)", "Hold a block / seed in the game backpack first (not a tool)" },
    { "Pilihan item dihapus: semua item", "Item selection cleared: all items" },
    { "Posisi drop vending", "Vending drop position" }, { "Posisi drop vending dihapus", "Vending drop position cleared" },
    { "(titik kedatangan)", "(arrival point)" }, { "dropdown belum dibuat", "dropdown not created yet" },
    { "refresh gagal", "refresh failed" }, { "tas", "bag" },
    { "Vending item terpilih penuh / belum ada yang menjual item terpilih", "Vendings of the selected items are full / none sells them yet" },
    { "Fungsi animasi game tidak ketemu (tekan 'Hubungkan ke game')", "Game animation function not found (press 'Connect to game')" },
    { "Animasi", "Animation" }, { "(belum ada item)", "(no items yet)" }, { "| jenis:", "| type:" },
    { ": semua |", ": all |" }, { "jenis: Semua", "type: All" },
    { "Block saja", "Blocks only" }, { "Seed saja", "Seeds only" },
    { "Posisi break produksi", "Production break position" }, { "otomatis", "automatic" },
    { "kanan karakter, dekat ujung baris", "right of the character, near the row end" },
    { "grid lahan", "land grid" }, { "posisi break lahan", "land break position" },
    { "Ke vending", "To vending" }, { "): tambah", "): add" }, { "): ambil", "): take" },
    { "Gagal tambah stock di", "Failed to add stock at" }, { "Tidak bisa ke vending", "Can't reach vending" },
    { "Semua vending penuh / belum ada vending yang menjual item", "All vendings full / none sells an item yet" },
    { "Menunggu drop baru di", "Waiting for new drops in" }, { "untuk isi stock", "to restock" },
    { "Pergi ke titik drop", "Going to drop point" }, { "Gagal ke titik drop", "Failed to reach drop point" },
    { "Semua vending sudah kosong", "All vendings are empty" }, { "Ambil", "Take" },
    { "Selesai, ada vending yang gagal diambil", "Done, some vendings could not be emptied" },
    { "Vending kosong, tapi drop gagal", "Vendings empty, but dropping failed" },
    { "Tas penuh oleh item lain, kosongkan tas dulu", "Backpack is full of other items, clear it first" },
    { "Drop gagal", "Drop failed" }, { "Tambah stock gagal terus", "Adding stock keeps failing" },
    { "Gagal pulang ke world vending", "Failed to return to the vending world" },
    { "ambil drop", "to pick drops" },
    { "Tas penuh: atur titik drop vending (WORLD atau WORLD:ID)", "Backpack full: set the vending drop point (WORLD or WORLD:ID)" },
    { "Tidak ada vending milikmu di world ini (jalankan di world vending)", "No vending of yours in this world (run it in the vending world)" },
    { "Fungsi vending game tidak ketemu", "Game vending function not found" },
    { "milikmu di world ini | isi", "yours in this world | stocked" }, { "kosong", "empty" },
    { "diambil", "taken" },
    { "tile gali belum terjangkau, dicoba lagi", "dig tiles not reachable yet, retrying" },
    { "tile gali dilewati", "dig tiles skipped" }, { "Bersihkan drop di lahan", "Cleaning up drops on the land" },
    { "Ambil drop block sisa galian", "Picking up leftover dug blocks" },
    { "Bersihkan drop sisa galian (per baris)", "Cleaning up leftover dug drops (row by row)" },
    { "Ambil drop sisa di lahan (per baris)", "Picking up leftover drops on the land (row by row)" },
    { "Bersihkan drop di lahan (per baris)", "Cleaning up drops on the land (row by row)" },
    { "Bersihkan drop baris y", "Cleaning drops on row y" },
    { "Block habis, produksi 1 baris dulu", "Out of blocks, producing on 1 row first" },
    { "lanjut pasang", "resuming placing" }, { "sisakan", "keep" }, { "baris y", "row y" },
    { "Jalan ke posisi pasang-pecah", "Walking to the place-break spot" },
    { "Naik tangga ke", "Climbing stairs to" }, { "belum terjangkau, dilewati sebentar", "not reachable yet, skipped for a while" },
    { "Tidak ada baris lahan (cek X awal / X akhir / Y baris atas)", "No land rows (check start X / end X / top row Y)" },
    { "Belum ada baris lengkap", "No complete row yet" }, { "seed-nya tidak ketemu", "its seed was not found" },
    { "celah, tangga, background", "gaps, stairs, background" }, { "selesai", "done" },
    { "Produksi block", "Producing blocks" }, { "total butuh", "total needed" },
    { "Lahan selesai", "Land finished" }, { "Block cukup", "Enough blocks" }, { "mulai pasang", "starting to place" },
    { "Block habis, masih kurang", "Out of blocks, still short" }, { "Seed & block habis", "Seeds & blocks used up" },
    { "tidak ada pohon tumbuh", "no trees growing" }, { "Butuh", "Need" }, { "Seed habis", "Out of seeds" },
    { "seed-nya tidak ketemu", "its seed was not found" }, { "Block kurang", "Blocks short" },
    { "Sisa tile belum terjangkau / terhalang, dicoba lagi", "Remaining tiles unreachable / blocked, retrying" },
    { "Lahan penuh, menunggu", "Land is full, waiting" }, { "Bukan di world pabrik", "Not in the factory world" },
    { "menunggu...", "waiting..." }, { "Pergi ke", "Going to" }, { "untuk drop", "to drop" }, { "Pulang ke", "Returning to" },
    { "Gagal pulang ke world pabrik", "Failed to return to factory world" }, { "Drop gagal", "Drop failed" },
    { "tidak bisa drop di posisi ini", "can't drop at this position" },
    { "tidak bisa jalan ke posisi drop", "can't walk to the drop position" },
    { "Posisi drop belum diatur", "Drop position not set" }, { "drop dilewati", "drop skipped" },
    { "Posisi drop dihapus", "Drop position cleared" }, { "Posisi drop", "Drop position" }, { "Posisi break", "Break position" },
    { "di posisi pabrik", "at the factory position" }, { "Pabrik berhenti", "Factory stopped" },
    { "Bangun Lahan", "Build Land" }, { "Pabrik", "Factory" }, { "Penjaga", "Guard" }, { "Lahan", "Land" },
    { "Gagal masuk lagi ke", "Failed to rejoin" }, { "Gagal masuk", "Failed to enter" }, { "Gagal keluar world", "Failed to leave world" },
    { "Dicoba lagi nanti", "Will retry later" }, { "dicoba lagi", "retrying" },
    { "Gagal splice", "Splice failed" }, { "ditolak server", "rejected by server" }, { "Splice jadi", "Spliced into" },
    { "Menunggu tile Grid kosong (panen dulu pohonnya)", "Waiting for empty Grid tiles (harvest the trees first)" },
    { "Seed A habis, tidak ada pohon A yang bisa di-splice", "Seed A used up, no A trees to splice" },
    { "tidak ada tempat tanam / pohon untuk di-splice", "no planting spot / tree to splice" },
    { "Karakter tidak ditemukan (keluar world?)", "Character not found (left the world?)" },
    { "di inventori habis", "in inventory is used up" }, { "Auto Farm berhenti", "Auto Farm stopped" },
    { "Auto Clear berhenti", "Auto Clear stopped" }, { "Farmer berhenti", "Farmer stopped" },
    { "Inventori penuh", "Inventory full" }, { "tidak bisa diambil lagi", "can't be picked up anymore" },
    { "Laporan statistik", "Stats report" }, { "Quest diklaim", "Quest claimed" }, { "Redeem berhasil", "Redeem successful" },
    { "Redeem gagal", "Redeem failed" }, { "Terlempar dari world", "Kicked from world" }, { "Terlempar dari", "Kicked from" },
    { "Kembali otomatis", "Auto return" }, { "berhasil", "succeeded" },
    { "Rejoin: menunggu masuk", "Rejoin: waiting to enter" }, { "Rejoin: gagal masuk", "Rejoin: failed to enter" },
    { "Disconnect dari server", "Disconnected from server" }, { "script tidak di-queue", "script not queued" },
    { "Berhasil masuk lagi", "Rejoined" }, { "World tujuan", "Target world" },
    { "Mode diganti, nyalakan lagi", "Mode changed, turn it on again" }, { "World sudah bersih!", "World is clean!" },
    { "Block pijakan belum dipilih / habis: jalan tanpa block pijakan", "Scaffold block not selected / empty: moving without scaffold" },
    { "Auto Harvest tidak bisa cek pohon siap", "Auto Harvest can't check ready trees" },
    { "Aktifkan Auto Harvest atau Auto Plant", "Enable Auto Harvest or Auto Plant" },
    { "Pilih seed dulu untuk Auto Plant", "Select a seed for Auto Plant first" },
    { "Pilih seed pabrik dulu", "Select a factory seed first" }, { "Block dari seed ini tidak ketemu", "Block for this seed not found" },
    { "Atur lahan dulu", "Set up the land first" }, { "Pilih block padat untuk lahan", "Select a solid block for the land" },
    { "Pilih Seed A dan Seed B dulu", "Select Seed A and Seed B first" }, { "Seed A dan Seed B harus beda", "Seed A and Seed B must differ" },
    { "Kombinasi ini tidak bisa di-splice", "This combination can't be spliced" },
    { "Pilih tile dulu di Grid Tile", "Select tiles in the Tile Grid first" }, { "Pilih block dari inventori", "Select a block from inventory" },
    { "Hentikan Auto Farm / Clear / Farmer dulu", "Stop Auto Farm / Clear / Farmer first" },
    { "atau nyalakan Keliling world", "or turn on Roam world" },
    { "Kontrol gerak game (WorldMenu.isDown) tidak ketemu", "Game movement control (WorldMenu.isDown) not found" },
    { "Fungsi pukul game belum ketemu", "Game punch function not found" },
    { "Seed habis: atur posisi & tile break di tab Pabrik supaya bisa dapat seed", "Out of seeds: set break position & tiles in the Factory tab to get seeds" },
    { "Config dihapus. Execute ulang untuk default", "Config deleted. Re-execute for defaults" },
    { "Config dimuat", "Config loaded" }, { "Belum ada config", "No config yet" }, { "Tersimpan", "Saved" },
    { "Executor tidak bisa simpan file", "Executor can't save files" }, { "Executor tidak bisa hapus file", "Executor can't delete files" },
    { "Executor tidak punya fungsi request", "Executor has no request function" },
    { "Gagal simpan file", "Failed to save file" }, { "Gagal hapus file", "Failed to delete file" },
    { "Gagal kirim", "Failed to send" }, { "Terkirim", "Sent" }, { "Antrian", "Queue" },
    { "Gagal buka", "Failed to open" }, { "Gagal", "Failed" },
    -- label status
    { "BERHENTI", "STOPPED" }, { "JALAN", "RUNNING" }, { "fase", "phase" }, { "PANEN", "HARVEST" }, { "TANAM", "PLANT" },
    { "TUNGGU", "WAIT" }, { "TIDAK terbaca (harvest mati)", "NOT readable (harvest off)" }, { "terbaca", "readable" },
    { "TIDAK", "NO" }, { "cadangan", "fallback" }, { "Inventori", "Inventory" }, { "Posisi", "Position" },
    { "Karakter", "Character" }, { "Aksi", "Action" }, { "Baris", "Row" }, { "Pohon", "Trees" }, { "Pijakan", "Scaffold" },
    { "Pemain", "Players" }, { "belum dipilih", "not selected" }, { "belum diatur", "not set" }, { "ditolak", "rejected" },
    { "Bentuk", "Shape" }, { "baris", "rows" }, { "jarak", "spacing" }, { "tangga", "stairs" }, { "punya", "have" },
    { "butuh", "need" }, { "kurang", "short" }, { "cukup", "enough" }, { "Terpasang", "Placed" },
    { "terhalang block lain", "blocked by other blocks" }, { "Celah tanam terisi block", "Planting gaps filled with blocks" },
    { "bersihkan dulu", "clear it first" }, { "Celah tanam: bersih", "Planting gaps: clear" }, { "Seed block", "Block seed" },
    { "Hasil", "Result" }, { "panen", "harvest" }, { "tanam", "plant" }, { "di-drop", "dropped" }, { "sisakan", "keep" },
    { "drop saat", "drop at" }, { "world ini", "this world" }, { "pintu", "door" }, { "Lama sesi", "Session time" },
    { "Block pecah", "Blocks broken" }, { "Block di-place", "Blocks placed" }, { "Drop diambil", "Drops collected" },
    { "Item terbanyak", "Top items" }, { "Selesai", "Done" }, { "diklaim script", "claimed by script" },
    { "Quest baru dalam", "New quests in" }, { "Quest belum bisa diambil", "Quests not available yet" },
    { "Gagal ambil quest", "Failed to get quests" }, { "Gagal ambil daftar code", "Failed to get code list" },
    { "Pesan terakhir", "Last message" }, { "Cek lagi dalam", "Checking again in" }, { "detik", "seconds" },
    { "Auto klaim mati", "Auto claim off" }, { "Code aktif", "Active codes" }, { "sudah ditukar", "redeemed" },
    { "ditukar script", "redeemed by script" }, { "Auto redeem mati", "Auto redeem off" },
    { "Redeem sedang ditutup", "Redeem is closed" }, { "Block depan", "Front blocks" }, { "tumpukan", "piles" },
    { "siap panen", "ready" }, { "tumbuh", "growing" }, { "Scan terakhir", "Last scan" }, { "siap", "ready" },
    { "berikut", "next" }, { "Tidak ada yang cocok", "No matches" }, { "Kosong", "Empty" }, { "Tidak ada pohon", "No trees" },
    { "item lain", "more items" }, { "jenis lain", "more types" }, { "pakai Cari item", "use Search item" },
    { "(pohon)", "(tree)" }, { "Di-recycle", "Recycled" }, { "Item dipilih", "Items selected" }, { "Ditanam", "Planted" },
    { "tidak bisa di-splice", "can't be spliced" }, { "Pilih Seed A dan Seed B", "Select Seed A and Seed B" },
    { "Menghitung...", "Calculating..." }, { "Mulai...", "Starting..." }, { "Lanjut aktivitas...", "Resuming activity..." },
    { "data pemain belum ketemu", "player data not found" }, { "belum ketemu", "not found" },
    { "tidak ketemu", "not found" }, { "ketemu", "found" }, { "tekan", "press" },
    { "tidak ada block padat di inventori", "no solid blocks in inventory" },
    { "tidak ada seed di inventori", "no seeds in inventory" }, { "tidak ada pohon", "no trees" },
    { "tidak ada tempat tanam", "no planting spot" },
    { "Y baris atas", "top row Y" }, { "baris atas", "top row" }, { "Y awal", "start Y" }, { "X awal", "start X" },
    { "jumlah baris", "row count" }, { "masuk lagi dalam", "rejoining in" }, { "masuk ke", "entering" },
    { "dalam", "in" }, { "Executor tidak punya", "Executor has no" },
    { "tidak bisa dijangkau / dipecah", "can't be reached / broken" }, { "Sisa", "Remaining" },
    { "dilewati, coba ulang", "skipped, retrying" }, { "Gagal membaca pengaturan", "Failed to read settings" },
    { "balasan kosong", "empty reply" }, { "fungsi drop game tidak ketemu", "game drop function not found" },
    { "fungsi masuk world tidak ketemu", "game enter-world function not found" },
    { "fungsi splice game tidak ketemu", "game splice function not found" },
    { "gagal masuk", "failed to enter" }, { "nama world tidak diketahui", "unknown world name" },
    { "tidak bisa ke server", "can't reach the server" }, { "tunggu", "wait" },
    { "world penuh / dikunci / gagal", "world full / locked / failed" }, { "aman", "safe" }, { "Fase", "Phase" },
    { "Titik drop belum diatur (tab Titik Drop), drop dilewati", "Drop point not set (Drop Point tab), drop skipped" },
    { "Ambil hasil panen...", "Picking up harvest..." }, { "Lanjut Auto Farm", "Resuming Auto Farm" },
    { "Auto Farm dihentikan", "Auto Farm stopped" }, { "Gagal pulang ke world farmer", "Failed to return to farmer world" },
    { "Gagal pulang ke world farm", "Failed to return to farm world" },
    { "Sesi break tanpa aksi: cek posisi & tile break (dicoba lagi 1 menit)",
        "Break session had no action: check break position & tiles (retry in 1 minute)" },
    { "pohon siap belum terjangkau, dicoba lagi", "ready trees not reachable yet, retrying" },
    { "Seed hampir penuh", "Seeds almost full" },
    { "atur titik drop & nyalakan Auto drop seed", "set a drop point & turn on Auto drop seed" },
    { "Pasang & pecah", "Place & break" }, { "untuk dapat seed", "to get seeds" },
    { "Seed habis & tidak ada tempat pasang-pecah di samping karakter",
        "Out of seeds & no spot beside the character to place and break" },
    { "Tidak ada tempat tanam, menunggu", "No planting spot, waiting" },
    { "drop di titik ini tidak di-collect lagi", "drops at this point are not collected again" },
    { "titik kedatangan", "arrival point" }, { "hasil panen", "harvest" }, { "sisakan seed", "keep seeds" },
    { "Dipakai", "Used by" }, { "Di-drop", "Dropped" }, { "Catatan", "Note" }, { "Titik", "Point" },
    { "Produksi", "Production" }, { "Drop seed", "Seed drop" },
    { "Tidak ada baris yang muat (Y atas terlalu bawah). Berdiri di pojok kiri-ATAS lahan lalu tekan 'Pakai posisi karakter'",
        "No rows fit (top Y too low). Stand at the TOP-LEFT corner of the land, then press 'Use character position'" },
    { "tidak ada baris yang muat (Y atas terlalu bawah)", "no rows fit (top Y too low)" },
    { "berdiri di pojok kiri-atas lalu tekan 'Pakai posisi karakter'", "stand at the top-left corner, then press 'Use character position'" },
    { "Tidak bisa ke awal lahan", "Can't reach the land start" }, { "Pecah anak tangga", "Breaking stair step" },
    { "Pasang anak tangga", "Placing stair step" }, { "Turun ke anak tangga", "Stepping down to stair step" },
    { "Bersihkan tile lahan", "Clearing land tile" }, { "Ambil drop", "Picking up drop" },
    { "1 kosong per baris, tangga kiri & kanan", "1 gap per row, stairs on left & right" },
    { "titik drop belum diatur", "drop point not set" }, { "otomatis saat", "automatic at" },
    { "Dipakai: Pabrik (seed), Farmer & Auto Farm (otomatis saat item ~190)",
        "Used by: Factory (seeds), Farmer & Auto Farm (automatic when an item reaches ~190)" },
    { "saat", "at" },
    { "Mati", "Off" }, { "mati", "off" }, { "pohon siap", "trees ready" }, { "pohon", "trees" },
    { "di-recycle", "recycled" }, { "di-splice", "spliced" }, { "di-place", "placed" }, { "di-queue", "queued" }, { "habis", "used up" }, { "dan", "and" }, { "atau", "or" }, { "dari", "from" }, { "untuk", "for" },
    { "sudah", "already" }, { "belum", "not yet" }, { "lagi", "again" }, { "di", "at" }, { "ke", "to" },
}

-- Pola tambahan (format waktu "1j 2m 3d" -> "1h 2m 3s", "/jam" -> "/hour")
I18N.RAW = {
    { "(%d+)j (%d+)m (%d+)d", "%1h %2m %3s" },
    { "(%d+)m (%d+)d", "%1m %2s" },
    { "(%d+)j (%d+)m", "%1h %2m" },
    { "/jam", "/hour" },
    { "(%d+) dtk", "%1 s" },
}

function I18N.prep()
    local list = {}
    for _, p in ipairs(I18N.PH) do
        if p[1] ~= p[2] then
            local pat = p[1]:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
            if p[1]:match("^%w") then pat = "%f[%w]" .. pat end
            if p[1]:match("%w$") then pat = pat .. "%f[%W]" end
            list[#list + 1] = { pat, (p[2]:gsub("%%", "%%%%")), #p[1] }
        end
    end
    table.sort(list, function(a, b) return a[3] > b[3] end)
    I18N.list = list
end

-- Terjemahkan teks (kalau bahasa = English)
function I18N.T(s)
    if I18N.Lang ~= "en" or type(s) ~= "string" or s == "" then return s end
    local e = I18N.EN[s]
    if e then return e end
    if not I18N.list then I18N.prep() end
    for _, r in ipairs(I18N.list) do s = s:gsub(r[1], r[2]) end
    for _, r in ipairs(I18N.RAW) do s = s:gsub(r[1], r[2]) end
    return s
end

-- Teks pilihan dropdown: hanya terjemahan utuh (nama item game tidak diubah)
function I18N.V(s)
    if I18N.Lang ~= "en" or type(s) ~= "string" then return s end
    return I18N.EN[s] or s
end

-- Bungkus objek WindUI: judul, deskripsi, pilihan dropdown & isi status ikut diterjemahkan
I18N.Backs = setmetatable({}, { __mode = "k" })

local function mapList(list, back)
    local out = {}
    for i, val in ipairs(list) do
        local tr = I18N.V(val)
        out[i] = tr
        if type(tr) == "string" then back[tr] = val end
    end
    return out
end

function I18N.wrap(obj)
    if I18N.Lang ~= "en" or type(obj) ~= "table" then return obj end
    return setmetatable({}, {
        __index = function(_, k)
            local v = obj[k]
            if type(v) ~= "function" then return v end
            return function(_, cfg, ...)
                local back
                if k == "Dropdown" and type(cfg) == "table" then
                    back = {}
                    if type(cfg.Values) == "table" then cfg.Values = mapList(cfg.Values, back) end
                    if type(cfg.Value) == "string" then
                        cfg.Value = I18N.V(cfg.Value)
                    elseif type(cfg.Value) == "table" then
                        cfg.Value = mapList(cfg.Value, back)
                    end
                    local cb = cfg.Callback
                    if cb then
                        -- tampil dalam English, callback tetap terima teks asli
                        cfg.Callback = function(opt, ...)
                            if type(opt) == "string" then
                                opt = back[opt] or opt
                            elseif type(opt) == "table" then
                                local o2 = {}
                                for i, x in ipairs(opt) do o2[i] = back[x] or x end
                                opt = o2
                            end
                            return cb(opt, ...)
                        end
                    end
                elseif (k == "Refresh" or k == "Select") and I18N.Backs[obj] then
                    local b = I18N.Backs[obj]
                    if type(cfg) == "table" then
                        cfg = mapList(cfg, b)
                    elseif type(cfg) == "string" then
                        cfg = I18N.V(cfg)
                    end
                end
                if type(cfg) == "table" and k ~= "Refresh" and k ~= "Select" and cfg[1] == nil then
                    for _, f in ipairs({ "Title", "Desc", "Placeholder", "Content" }) do
                        if type(cfg[f]) == "string" then cfg[f] = I18N.T(cfg[f]) end
                    end
                elseif type(cfg) == "string" and (k == "SetDesc" or k == "SetTitle") then
                    cfg = I18N.T(cfg)
                end
                local r = v(obj, cfg, ...)
                if back and type(r) == "table" then I18N.Backs[r] = back end
                if type(r) == "table" and r ~= obj then return I18N.wrap(r) end
                return r
            end
        end,
    })
end
end)() end

local function notify(title, content, dur)
    task.defer(function()
        pcall(function()
            WindUI:Notify({ Title = I18N.T(title), Content = I18N.T(content), Duration = dur or 3, Icon = "info" })
        end)
    end)
end

-------------------------------------------------------
