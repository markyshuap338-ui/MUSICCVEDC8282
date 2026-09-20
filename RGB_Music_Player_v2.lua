-- ╔══════════════════════════════════════════════════╗
-- ║  NEON MUSIC PLAYER v3 · Gray Edition · Delta     ║
-- ║  LocalScript · работает только для тебя          ║
-- ╚══════════════════════════════════════════════════╝

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Защита от дублей
for _, name in ipairs({"RGBMusicPlayer", "RGBMusic"}) do
    local old = playerGui:FindFirstChild(name)
    if old then old:Destroy() end
end

-- ═════════════ НАСТРОЙКИ ═════════════
local CONFIG = {
    DefaultId = "74612331354602",
    DefaultVolume = 0.5,      -- 0..1
    MaxVolume = 10,           -- множитель Sound.Volume
    LoadTimeout = 8,          -- секунд ожидания загрузки
    BarCount = 24,            -- столбиков эквалайзера
    Effects = true,           -- неоновые точки + 3D-кубы (можно выключить кнопкой ✨)
    DotCount = 34,            -- неоновых точек
    CubeCount = 15,           -- вращающихся 3D-кубов
    Playlist = {              -- {название, id}
        {"Трек 1", "74612331354602"},
    },
}

-- ═════════════ УТИЛИТЫ ═════════════
local rng = Random.new()
local connections = {}
local blockedInputs = setmetatable({}, {__mode = "k"})

local function connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(connections, c)
    return c
end

local function tween(obj, time, props, style, dir)
    local t = TweenService:Create(
        obj,
        TweenInfo.new(time, style or Enum.EasingStyle.Quart, dir or Enum.EasingDirection.Out),
        props
    )
    t:Play()
    return t
end

local function create(class, props, children)
    local inst = Instance.new(class)
    for k, v in pairs(props or {}) do
        inst[k] = v
    end
    for _, child in ipairs(children or {}) do
        child.Parent = inst
    end
    return inst
end

local function corner(r)
    return create("UICorner", {CornerRadius = UDim.new(0, r)})
end

local function fmtTime(s)
    s = math.max(0, math.floor(s or 0))
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local function normalizeId(text)
    text = tostring(text or ""):gsub("%s+", "")
    if text == "" then return nil end
    local digits = text:match("%d+")
    if not digits then return nil end
    return "rbxassetid://" .. digits, digits
end

-- Элемент не должен начинать перетаскивание окна
local function blockDragOn(obj)
    connect(obj.InputBegan, function(input)
        blockedInputs[input] = true
    end)
end

-- ═════════════ ПАЛИТРА (серая тема) ═════════════
local WHITE = Color3.new(1, 1, 1)
local C = {
    panel = Color3.fromRGB(38, 38, 45),
    panel2 = Color3.fromRGB(52, 52, 61),
    panelHover = Color3.fromRGB(70, 70, 82),
    text = Color3.fromRGB(238, 238, 244),
    sub = Color3.fromRGB(150, 150, 164),
    dim = Color3.fromRGB(105, 105, 118),
    track = Color3.fromRGB(20, 20, 25),
}

local COLORS = {
    ok = Color3.fromRGB(120, 255, 170),
    warn = Color3.fromRGB(255, 205, 110),
    err = Color3.fromRGB(255, 120, 130),
    idle = Color3.fromRGB(190, 190, 205),
}

-- Радужный градиент для вращающихся обводок
local RAINBOW = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 60, 60)),
    ColorSequenceKeypoint.new(1 / 6, Color3.fromRGB(255, 220, 60)),
    ColorSequenceKeypoint.new(2 / 6, Color3.fromRGB(60, 255, 120)),
    ColorSequenceKeypoint.new(3 / 6, Color3.fromRGB(60, 240, 255)),
    ColorSequenceKeypoint.new(4 / 6, Color3.fromRGB(90, 110, 255)),
    ColorSequenceKeypoint.new(5 / 6, Color3.fromRGB(255, 70, 240)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 60, 60)),
})

local spinners = {}

local function rainbowGradient(parent, offset)
    local g = create("UIGradient", {Color = RAINBOW, Parent = parent})
    table.insert(spinners, {g = g, off = offset or 0})
    return g
end

-- UIStroke с вращающимся радужным градиентом
local function neonStroke(parent, thickness, offset, transparency)
    local s = create("UIStroke", {
        Color = WHITE,
        Thickness = thickness,
        Transparency = transparency or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = parent,
    })
    rainbowGradient(s, offset)
    return s
end

-- ═════════════ ЗВУК ═════════════
local sound = create("Sound", {
    Name = "RGBMusic",
    Volume = CONFIG.DefaultVolume * CONFIG.MaxVolume,
    Looped = true,
    Parent = playerGui,
})

local state = {
    loop = true,
    volume = CONFIG.DefaultVolume,
    playlistIndex = 1,
    loadToken = 0,
    minimized = false,
    closed = false,
    fx = CONFIG.Effects,
    fit = 1,
}

-- ═════════════ 3D-КУБЫ (ViewportFrame) ═════════════
local function makeCubeScene(parent, cfg)
    local ok, result = pcall(function()
        local vpf = create("ViewportFrame", {
            Name = "Cubes",
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ZIndex = cfg.zindex or 1,
            Ambient = WHITE,
            LightColor = WHITE,
            Parent = parent,
        })
        local cam = create("Camera", {
            FieldOfView = cfg.fov or 50,
            CFrame = CFrame.lookAt(Vector3.new(0, 0, cfg.dist or 10), Vector3.new(0, 0, 0)),
            Parent = vpf,
        })
        vpf.CurrentCamera = cam

        local function randSpeed()
            local v = rng:NextNumber(0.4, 1.4)
            if rng:NextInteger(0, 1) == 1 then v = -v end
            return v
        end

        local count = cfg.count or 12
        local cols = cfg.cols or 3
        local rows = math.max(1, math.ceil(count / cols))
        local jit = cfg.jitter or 0.4
        local cubes = {}

        for i = 1, count do
            local col = (i - 1) % cols
            local row = math.floor((i - 1) / cols)
            local x = ((col + 0.5) / cols * 2 - 1) * (cfg.xr or 3) + rng:NextNumber(-jit, jit)
            local y = ((row + 0.5) / rows * 2 - 1) * (cfg.yr or 4.2) + rng:NextNumber(-jit, jit)
            local z = rng:NextNumber(cfg.zmin or -3, cfg.zmax or 1)
            local size = rng:NextNumber(cfg.minSize or 0.35, cfg.maxSize or 0.8)

            local core = create("Part", {
                Anchored = true,
                CanCollide = false,
                CastShadow = false,
                Material = Enum.Material.Neon,
                Transparency = 0.3,
                Size = Vector3.new(size, size, size),
                Parent = vpf,
            })
            local halo = create("Part", {
                Anchored = true,
                CanCollide = false,
                CastShadow = false,
                Material = Enum.Material.Neon,
                Transparency = 0.82,
                Size = Vector3.new(size * 1.4, size * 1.4, size * 1.4),
                Parent = vpf,
            })

            cubes[i] = {
                core = core,
                halo = halo,
                base = Vector3.new(x, y, z),
                size = size,
                ang = Vector3.new(rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28)),
                spd = Vector3.new(randSpeed(), randSpeed(), randSpeed()),
                ph = rng:NextNumber(0, 6.28),
                off = rng:NextNumber(0, 1),
            }
        end

        local t = 0
        local function update(dt, hueValue, energy)
            t += dt
            local boost = 1 + energy * 3
            local pulse = 1 + energy * 0.35
            for _, c in ipairs(cubes) do
                c.ang += c.spd * dt * boost
                local pos = c.base + Vector3.new(
                    math.sin(t * 0.6 + c.ph) * 0.25,
                    math.cos(t * 0.5 + c.ph) * 0.3,
                    0
                )
                local cf = CFrame.new(pos) * CFrame.fromEulerAnglesXYZ(c.ang.X, c.ang.Y, c.ang.Z)
                local s = c.size * pulse
                local col = Color3.fromHSV((hueValue + c.off * 0.5) % 1, 0.85, 1)

                c.core.CFrame = cf
                c.core.Size = Vector3.new(s, s, s)
                c.core.Color = col
                c.halo.CFrame = cf
                c.halo.Size = Vector3.new(s * 1.4, s * 1.4, s * 1.4)
                c.halo.Color = col
            end
        end

        update(0, 0, 0)
        return {gui = vpf, update = update}
    end)
    if ok then return result end
    return nil
end

-- ═════════════ GUI: КОРЕНЬ ═════════════
local gui = create("ScreenGui", {
    Name = "RGBMusicPlayer",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 999,
    Parent = playerGui,
})

local FULL_W, FULL_H = 360, 530
local HEADER_H = 54

local function fitScale()
    local vp = gui.AbsoluteSize
    if vp.X <= 0 or vp.Y <= 0 then
        local cam = workspace.CurrentCamera
        vp = cam and cam.ViewportSize or Vector2.new(800, 600)
    end
    return math.clamp(math.min((vp.X - 16) / FULL_W, (vp.Y - 16) / FULL_H, 1), 0.4, 1)
end
state.fit = fitScale()

-- root двигается при перетаскивании, размер = размер окна с учётом масштаба
local root = create("Frame", {
    Name = "Root",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.5, 0),
    Size = UDim2.fromOffset(FULL_W * state.fit, FULL_H * state.fit),
    BackgroundTransparency = 1,
    Parent = gui,
})

local glow = create("ImageLabel", {
    Name = "Glow",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.5, 0),
    Size = UDim2.fromOffset(0, 0),
    BackgroundTransparency = 1,
    Image = "rbxassetid://5028857472",
    ImageColor3 = Color3.fromRGB(120, 120, 255),
    ImageTransparency = 0.6,
    ScaleType = Enum.ScaleType.Slice,
    SliceCenter = Rect.new(24, 24, 276, 276),
    ZIndex = 0,
    Parent = root,
})

local frame = create("Frame", {
    Name = "Main",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.5, 0),
    Size = UDim2.fromOffset(FULL_W, FULL_H),
    BackgroundColor3 = WHITE,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    Active = true,
    ZIndex = 1,
    Parent = root,
}, {
    corner(18),
})

local uiScale = create("UIScale", {Scale = 0, Parent = frame})

create("UIGradient", {
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(44, 44, 52)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(26, 26, 31)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(38, 38, 45)),
    }),
    Rotation = 60,
    Parent = frame,
})

neonStroke(frame, 2.5, 0)

-- ═════════════ ФОН: ТОЧКИ И КУБЫ ═════════════
local mainScene = makeCubeScene(frame, {
    zindex = 1,
    count = CONFIG.CubeCount,
    cols = 3,
    xr = 2.9,
    yr = 4.2,
    zmin = -3,
    zmax = 1,
    minSize = 0.35,
    maxSize = 0.85,
    dist = 10,
    fov = 50,
})
if mainScene then
    create("UICorner", {CornerRadius = UDim.new(0, 18), Parent = mainScene.gui})
end

local dotsLayer = create("Frame", {
    Name = "Dots",
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    ZIndex = 2,
    Parent = frame,
})

local dots = {}
for i = 1, CONFIG.DotCount do
    local size = rng:NextInteger(2, 5)
    local f = create("Frame", {
        Size = UDim2.fromOffset(size, size),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = WHITE,
        BorderSizePixel = 0,
        Parent = dotsLayer,
    }, {
        create("UICorner", {CornerRadius = UDim.new(1, 0)}),
    })
    local halo = create("UIStroke", {
        Color = WHITE,
        Thickness = size,
        Transparency = 0.75,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = f,
    })
    dots[i] = {
        f = f,
        s = halo,
        x = rng:NextNumber(0.02, 0.98),
        y = rng:NextNumber(0.02, 0.98),
        vx = rng:NextNumber(-0.03, 0.03),
        vy = rng:NextNumber(0.015, 0.05) * (rng:NextInteger(0, 1) == 1 and 1 or -1),
        ph = rng:NextNumber(0, 6.28),
        off = rng:NextNumber(0, 1),
    }
end

-- ═════════════ КНОПКИ (фабрика) ═════════════
local function ripple(btn, rs)
    local r = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(0, 0),
        BackgroundColor3 = WHITE,
        BackgroundTransparency = 0.55,
        BorderSizePixel = 0,
        ZIndex = btn.ZIndex + 1,
        Parent = btn,
    }, {
        create("UICorner", {CornerRadius = UDim.new(1, 0)}),
    })
    tween(r, 0.45, {Size = UDim2.fromOffset(rs, rs), BackgroundTransparency = 1})
    task.delay(0.5, function() r:Destroy() end)
end

local function styledButton(parent, pos, size, text, textSize, cornerR, thick, off)
    local cpos = UDim2.new(
        pos.X.Scale + size.X.Scale / 2, pos.X.Offset + size.X.Offset / 2,
        pos.Y.Scale + size.Y.Scale / 2, pos.Y.Offset + size.Y.Offset / 2
    )
    local b = create("TextButton", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = cpos,
        Size = size,
        BackgroundColor3 = C.panel2,
        Text = text,
        TextColor3 = C.text,
        Font = Enum.Font.GothamBold,
        TextSize = textSize,
        AutoButtonColor = false,
        Parent = parent,
    }, {
        corner(cornerR),
    })
    local stroke = neonStroke(b, thick, off or 0)
    local sc = create("UIScale", {Parent = b})
    local rs = math.min(size.X.Offset, size.Y.Offset)
    if rs <= 0 then rs = 30 end

    blockDragOn(b)

    connect(b.MouseEnter, function()
        tween(b, 0.15, {BackgroundColor3 = C.panelHover})
        tween(stroke, 0.15, {Thickness = thick + 1})
    end)
    local function release()
        tween(sc, 0.2, {Scale = 1}, Enum.EasingStyle.Back)
    end
    connect(b.MouseLeave, function()
        tween(b, 0.15, {BackgroundColor3 = C.panel2})
        tween(stroke, 0.15, {Thickness = thick})
        release()
    end)
    connect(b.MouseButton1Down, function()
        tween(sc, 0.08, {Scale = 0.92})
        ripple(b, rs)
    end)
    connect(b.MouseButton1Up, release)

    return b, stroke
end

-- ═════════════ ЗАГОЛОВОК ═════════════
local header = create("Frame", {
    Name = "Header",
    Size = UDim2.new(1, 0, 0, HEADER_H),
    BackgroundColor3 = C.panel,
    BackgroundTransparency = 0.25,
    BorderSizePixel = 0,
    ZIndex = 3,
    Parent = frame,
})

local headerLine = create("Frame", {
    Size = UDim2.new(1, 0, 0, 2),
    Position = UDim2.new(0, 0, 1, -2),
    BackgroundColor3 = WHITE,
    BorderSizePixel = 0,
    Parent = header,
})
local headerLineGradient = create("UIGradient", {
    Color = ColorSequence.new(WHITE),
    Parent = headerLine,
})

local disc = create("Frame", {
    Size = UDim2.fromOffset(38, 38),
    Position = UDim2.new(0, 12, 0.5, -19),
    BackgroundColor3 = C.panel2,
    BorderSizePixel = 0,
    Parent = header,
}, {
    corner(19),
})
neonStroke(disc, 2, 0)
local iconLabel = create("TextLabel", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Text = "🎵",
    TextSize = 20,
    Font = Enum.Font.GothamBold,
    TextColor3 = C.text,
    Parent = disc,
})

local title = create("TextLabel", {
    Size = UDim2.new(1, -190, 0, 24),
    Position = UDim2.new(0, 60, 0, 7),
    BackgroundTransparency = 1,
    Text = "NEON MUSIC",
    TextColor3 = WHITE,
    Font = Enum.Font.GothamBlack,
    TextSize = 18,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = header,
})
rainbowGradient(title, 0)

create("TextLabel", {
    Size = UDim2.new(1, -190, 0, 14),
    Position = UDim2.new(0, 60, 0, 32),
    BackgroundTransparency = 1,
    Text = "Gray Edition · v3",
    TextColor3 = C.sub,
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = header,
})

local fxBtn, fxStroke = styledButton(header, UDim2.new(1, -114, 0, 11), UDim2.fromOffset(32, 32), "✨", 15, 9, 1.5, 60)
local minimizeBtn = styledButton(header, UDim2.new(1, -78, 0, 11), UDim2.fromOffset(32, 32), "—", 15, 9, 1.5, 120)
local closeBtn = styledButton(header, UDim2.new(1, -42, 0, 11), UDim2.fromOffset(32, 32), "✕", 14, 9, 1.5, 180)

-- ═════════════ КОНТЕНТ ═════════════
local content = create("Frame", {
    Name = "Content",
    Size = UDim2.new(1, 0, 1, -HEADER_H),
    Position = UDim2.new(0, 0, 0, HEADER_H),
    BackgroundTransparency = 1,
    ZIndex = 3,
    Parent = frame,
})

local trackLabel = create("TextLabel", {
    Size = UDim2.new(1, -30, 0, 22),
    Position = UDim2.new(0, 15, 0, 10),
    BackgroundTransparency = 1,
    Text = "Ничего не играет",
    TextColor3 = C.text,
    Font = Enum.Font.GothamBold,
    TextSize = 15,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
    Parent = content,
})

-- ─── Визуализатор ───
local vizFrame = create("Frame", {
    Size = UDim2.new(1, -30, 0, 64),
    Position = UDim2.new(0, 15, 0, 38),
    BackgroundColor3 = C.track,
    BackgroundTransparency = 0.35,
    BorderSizePixel = 0,
    Parent = content,
}, {
    corner(12),
})
neonStroke(vizFrame, 1.5, 40)

local bars = {}
create("Frame", {
    Size = UDim2.new(1, -16, 1, -12),
    Position = UDim2.new(0, 8, 0, 6),
    BackgroundTransparency = 1,
    Parent = vizFrame,
}, {
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Bottom,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        Padding = UDim.new(0, 3),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }),
})
local barsHolder = vizFrame:FindFirstChildOfClass("Frame")
for i = 1, CONFIG.BarCount do
    bars[i] = create("Frame", {
        Size = UDim2.new(1 / CONFIG.BarCount, -3, 0.08, 0),
        BackgroundColor3 = WHITE,
        BorderSizePixel = 0,
        LayoutOrder = i,
        Parent = barsHolder,
    }, {
        corner(3),
    })
end

-- ─── Поле ID ───
create("TextLabel", {
    Size = UDim2.new(1, -30, 0, 16),
    Position = UDim2.new(0, 15, 0, 112),
    BackgroundTransparency = 1,
    Text = "MUSIC ID",
    TextColor3 = C.sub,
    Font = Enum.Font.GothamBold,
    TextSize = 10,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = content,
})

local idBox = create("TextBox", {
    Size = UDim2.new(1, -108, 0, 38),
    Position = UDim2.new(0, 15, 0, 130),
    PlaceholderText = "ID или rbxassetid://...",
    Text = CONFIG.DefaultId,
    BackgroundColor3 = C.panel,
    BackgroundTransparency = 0.15,
    TextColor3 = C.text,
    PlaceholderColor3 = C.dim,
    Font = Enum.Font.Gotham,
    TextSize = 14,
    ClearTextOnFocus = false,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = content,
}, {
    corner(10),
    create("UIPadding", {PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 8)}),
})
local idStroke = neonStroke(idBox, 1.5, 200, 0.2)
blockDragOn(idBox)
connect(idBox.Focused, function() tween(idStroke, 0.2, {Transparency = 0, Thickness = 2.5}) end)
connect(idBox.FocusLost, function() tween(idStroke, 0.2, {Transparency = 0.2, Thickness = 1.5}) end)

local addBtn = styledButton(content, UDim2.new(1, -87, 0, 130), UDim2.fromOffset(38, 38), "＋", 20, 10, 1.5, 240)
local clearBtn = styledButton(content, UDim2.new(1, -47, 0, 130), UDim2.fromOffset(38, 38), "⌫", 16, 10, 1.5, 300)

-- ─── Прогресс-бар (кликабельный) ───
local timeLeft = create("TextLabel", {
    Size = UDim2.new(0, 50, 0, 14),
    Position = UDim2.new(0, 15, 0, 180),
    BackgroundTransparency = 1,
    Text = "0:00",
    TextColor3 = C.sub,
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = content,
})
local timeRight = create("TextLabel", {
    Size = UDim2.new(0, 50, 0, 14),
    Position = UDim2.new(1, -65, 0, 180),
    BackgroundTransparency = 1,
    Text = "0:00",
    TextColor3 = C.sub,
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = header,
})

local fxBtn, fxStroke = styledButton(header, UDim2.new(1, -114, 0, 11), UDim2.fromOffset(32, 32), "✨", 15, 9, 1.5, 60)
local minimizeBtn = styledButton(header, UDim2.new(1, -78, 0, 11), UDim2.fromOffset(32, 32), "—", 15, 9, 1.5, 120)
local closeBtn = styledButton(header, UDim2.new(1, -42, 0, 11), UDim2.fromOffset(32, 32), "✕", 14, 9, 1.5, 180)

-- ═════════════ КОНТЕНТ ═════════════
local content = create("Frame", {
    Name = "Content",
    Size = UDim2.new(1, 0, 1, -HEADER_H),
    Position = UDim2.new(0, 0, 0, HEADER_H),
    BackgroundTransparency = 1,
    ZIndex = 3,
    Parent = frame,
})

local trackLabel = create("TextLabel", {
    Size = UDim2.new(1, -30, 0, 22),
    Position = UDim2.new(0, 15, 0, 10),
    BackgroundTransparency = 1,
    Text = "Ничего не играет",
    TextColor3 = C.text,
    Font = Enum.Font.GothamBold,
    TextSize = 15,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
    Parent = content,
})

-- ─── Визуализатор ───
local vizFrame = create("Frame", {
    Size = UDim2.new(1, -30, 0, 64),
    Position = UDim2.new(0, 15, 0, 38),
    BackgroundColor3 = C.track,
    BackgroundTransparency = 0.35,
    BorderSizePixel = 0,
    Parent = content,
}, {
    corner(12),
})
neonStroke(vizFrame, 1.5, 40)

local bars = {}
create("Frame", {
    Size = UDim2.new(1, -16, 1, -12),
    Position = UDim2.new(0, 8, 0, 6),
    BackgroundTransparency = 1,
    Parent = vizFrame,
}, {
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Bottom,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        Padding = UDim.new(0, 3),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }),
})
local barsHolder = vizFrame:FindFirstChildOfClass("Frame")
for i = 1, CONFIG.BarCount do
    bars[i] = create("Frame", {
        Size = UDim2.new(1 / CONFIG.BarCount, -3, 0.08, 0),
        BackgroundColor3 = WHITE,
        BorderSizePixel = 0,
        LayoutOrder = i,
        Parent = barsHolder,
    }, {
        corner(3),
    })
end

-- ─── Поле ID ───
create("TextLabel", {
    Size = UDim2.new(1, -30, 0, 16),
    Position = UDim2.new(0, 15, 0, 112),
    BackgroundTransparency = 1,
    Text = "MUSIC ID",
    TextColor3 = C.sub,
    Font = Enum.Font.GothamBold,
    TextSize = 10,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = content,
})

local idBox = create("TextBox", {
    Size = UDim2.new(1, -108, 0, 38),
    Position = UDim2.new(0, 15, 0, 130),
    PlaceholderText = "ID или rbxassetid://...",
    Text = CONFIG.DefaultId,
    BackgroundColor3 = C.panel,
    BackgroundTransparency = 0.15,
    TextColor3 = C.text,
    PlaceholderColor3 = C.dim,
    Font = Enum.Font.Gotham,
    TextSize = 14,
    ClearTextOnFocus = false,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = content,
}, {
    corner(10),
    create("UIPadding", {PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 8)}),
})
local idStroke = neonStroke(idBox, 1.5, 200, 0.2)
blockDragOn(idBox)
connect(idBox.Focused, function() tween(idStroke, 0.2, {Transparency = 0, Thickness = 2.5}) end)
connect(idBox.FocusLost, function() tween(idStroke, 0.2, {Transparency = 0.2, Thickness = 1.5}) end)

local addBtn = styledButton(content, UDim2.new(1, -87, 0, 130), UDim2.fromOffset(38, 38), "＋", 20, 10, 1.5, 240)
local clearBtn = styledButton(content, UDim2.new(1, -47, 0, 130), UDim2.fromOffset(38, 38), "⌫", 16, 10, 1.5, 300)

-- ─── Прогресс-бар (кликабельный) ───
local timeLeft = create("TextLabel", {
    Size = UDim2.new(0, 50, 0, 14),
    Position = UDim2.new(0, 15, 0, 180),
    BackgroundTransparency = 1,
    Text = "0:00",
    TextColor3 = C.sub,
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = content,
})
local timeRight = create("TextLabel", {
    Size = UDim2.new(0, 50, 0, 14),
    Position = UDim2.new(1, -65, 0, 180),
    BackgroundTransparency = 1,
    Text = "0:00",
    TextColor3 = C.sub,
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Right,
    Parent = content,
})

local barHit = create("TextButton", {
    Size = UDim2.new(1, -30, 0, 24),
    Position = UDim2.new(0, 15, 0, 196),
    BackgroundTransparency = 1,
    Text = "",
    AutoButtonColor = false,
    Parent = content,
})
local barBg = create("Frame", {
    Size = UDim2.new(1, 0, 0, 8),
    Position = UDim2.new(0, 0, 0.5, -4),
    BackgroundColor3 = C.track,
    BorderSizePixel = 0,
    Parent = barHit,
}, {
    corner(8),
})
local bar = create("Frame", {
    Size = UDim2.new(0, 0, 1, 0),
    BackgroundColor3 = WHITE,
    BorderSizePixel = 0,
    Parent = barBg,
}, {
    corner(8),
})
local barGradient = create("UIGradient", {Color = ColorSequence.new(WHITE), Parent = bar})
local knob = create("Frame", {
    Size = UDim2.fromOffset(14, 14),
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0, 0, 0.5, 0),
    BackgroundColor3 = WHITE,
    BorderSizePixel = 0,
    ZIndex = 3,
    Parent = barBg,
}, {
    corner(14),
})
local knobStroke = create("UIStroke", {
    Thickness = 2,
    Color = WHITE,
    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    Parent = knob,
})

-- ─── Кнопки управления ───
local controls = create("Frame", {
    Size = UDim2.new(1, -30, 0, 56),
    Position = UDim2.new(0, 15, 0, 228),
    BackgroundTransparency = 1,
    Parent = content,
})

local prevBtn = styledButton(controls, UDim2.fromOffset(20, 6), UDim2.fromOffset(44, 44), "⏮", 16, 22, 2, 0)
local playBtn = styledButton(controls, UDim2.fromOffset(80, 0), UDim2.fromOffset(56, 56), "▶", 22, 28, 3, 60)
local stopBtn = styledButton(controls, UDim2.fromOffset(152, 6), UDim2.fromOffset(44, 44), "⏹", 16, 22, 2, 120)
local nextBtn = styledButton(controls, UDim2.fromOffset(212, 6), UDim2.fromOffset(44, 44), "⏭", 16, 22, 2, 180)
local loopBtn, loopStroke = styledButton(controls, UDim2.fromOffset(272, 6), UDim2.fromOffset(44, 44), "🔁", 16, 22, 2, 240)

-- ─── Громкость ───
create("TextLabel", {
    Size = UDim2.new(0, 30, 0, 20),
    Position = UDim2.new(0, 15, 0, 296),
    BackgroundTransparency = 1,
    Text = "🔊",
    TextSize = 16,
    Font = Enum.Font.GothamBold,
    TextColor3 = C.text,
    Parent = content,
})

local volHit = create("TextButton", {
    Size = UDim2.new(1, -110, 0, 24),
    Position = UDim2.new(0, 48, 0, 294),
    BackgroundTransparency = 1,
    Text = "",
    AutoButtonColor = false,
    Parent = content,
})
local volBg = create("Frame", {
    Size = UDim2.new(1, 0, 0, 6),
    Position = UDim2.new(0, 0, 0.5, -3),
    BackgroundColor3 = C.track,
    BorderSizePixel = 0,
    Parent = volHit,
}, {
    corner(6),
})
local volFill = create("Frame", {
    Size = UDim2.new(state.volume, 0, 1, 0),
    BackgroundColor3 = WHITE,
    BorderSizePixel = 0,
    Parent = volBg,
}, {
    corner(6),
})
local volGradient = create("UIGradient", {Color = ColorSequence.new(WHITE), Parent = volFill})
local volKnob = create("Frame", {
    Size = UDim2.fromOffset(14, 14),
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(state.volume, 0, 0.5, 0),
    BackgroundColor3 = WHITE,
    BorderSizePixel = 0,
    ZIndex = 3,
    Parent = volBg,
}, {
    corner(14),
})
local volKnobStroke = create("UIStroke", {
    Thickness = 2,
    Color = WHITE,
    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    Parent = volKnob,
})
local volLabel = create("TextLabel", {
    Size = UDim2.new(0, 50, 0, 20),
    Position = UDim2.new(1, -65, 0, 296),
    BackgroundTransparency = 1,
    Text = math.floor(state.volume * 100) .. "%",
    TextColor3 = C.sub,
    Font = Enum.Font.GothamBold,
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Right,
    Parent = content,
})

-- ─── Плейлист ───
create("TextLabel", {
    Size = UDim2.new(1, -30, 0, 16),
    Position = UDim2.new(0, 15, 0, 326),
    BackgroundTransparency = 1,
    Text = "ПЛЕЙЛИСТ",
    TextColor3 = C.sub,
    Font = Enum.Font.GothamBold,
    TextSize = 10,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = content,
})

local listFrame = create("ScrollingFrame", {
    Size = UDim2.new(1, -30, 0, 84),
    Position = UDim2.new(0, 15, 0, 344),
    BackgroundColor3 = C.track,
    BackgroundTransparency = 0.35,
    BorderSizePixel = 0,
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = C.sub,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    Parent = content,
}, {
    corner(10),
    create("UIListLayout", {Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder}),
    create("UIPadding", {
        PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4),
        PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 6),
    }),
})
neonStroke(listFrame, 1.5, 100)
blockDragOn(listFrame)

-- ─── Статус ───
local status = create("TextLabel", {
    Size = UDim2.new(1, -30, 0, 20),
    Position = UDim2.new(0, 15, 0, 436),
    BackgroundTransparency = 1,
    Text = "💤  Готово к запуску",
    TextColor3 = C.sub,
    Font = Enum.Font.Gotham,
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
    Parent = content,
})

create("TextLabel", {
    Size = UDim2.new(1, 0, 0, 14),
    Position = UDim2.new(0, 0, 1, -18),
    BackgroundTransparency = 1,
    Text = "by CVEDC · Neon Gray v3",
    TextColor3 = C.dim,
    Font = Enum.Font.Gotham,
    TextSize = 10,
    Parent = content,
})

local function setStatus(text, color)
    status.Text = text
    status.TextColor3 = color or C.sub
end

-- ═════════════ ПЛАВАЮЩАЯ КНОПКА (свёрнутый режим) ═════════════
local floatBtn = create("TextButton", {
    Name = "FloatButton",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0, 60, 0.5, 0),
    Size = UDim2.fromOffset(0, 0),
    BackgroundColor3 = C.panel,
    Text = "",
    AutoButtonColor = false,
    Visible = false,
    ZIndex = 5,
    Parent = gui,
}, {
    corner(28),
})
neonStroke(floatBtn, 2.5, 90)
local floatScene = makeCubeScene(floatBtn, {
    zindex = 1,
    count = 1,
    cols = 1,
    xr = 0,
    yr = 0,
    jitter = 0,
    zmin = 0,
    zmax = 0,
    minSize = 1.5,
    maxSize = 1.5,
    dist = 5.5,
    fov = 45,
})
if floatScene then
    create("UICorner", {CornerRadius = UDim.new(1, 0), Parent = floatScene.gui})
else
    floatBtn.Text = "🎵"
    floatBtn.TextSize = 26
end

-- ═════════════ ПЕРЕТАСКИВАНИЕ (за любое место, мышь + тач) ═════════════
local function makeDraggable(areas, target, onClick)
    local dragging, activeInput, dragStart, startPos, moved = false, nil, nil, nil, false

    local function begin(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        if dragging then return end
        dragging = true
        activeInput = input
        moved = false
        dragStart = input.Position
        startPos = target.Position
        -- если на этом же нажатии сработала кнопка/слайдер — отменяем drag
        task.defer(function()
            if blockedInputs[input] then
                dragging = false
            end
            blockedInputs[input] = nil
        end)
    end

    for _, area in ipairs(areas) do
        connect(area.InputBegan, begin)
    end

    connect(UIS.InputChanged, function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        local d = input.Position - dragStart
        if d.Magnitude > 4 then moved = true end
        if not moved then return end

        local vp = gui.AbsoluteSize
        local half = target.AbsoluteSize / 2
        local cx = startPos.X.Scale * vp.X + startPos.X.Offset + d.X
        local cy = startPos.Y.Scale * vp.Y + startPos.Y.Offset + d.Y
        cx = math.clamp(cx, half.X, math.max(half.X, vp.X - half.X))
        cy = math.clamp(cy, half.Y, math.max(half.Y, vp.Y - half.Y))
        target.Position = UDim2.new(
            startPos.X.Scale, cx - startPos.X.Scale * vp.X,
            startPos.Y.Scale, cy - startPos.Y.Scale * vp.Y
        )
    end)

    connect(UIS.InputEnded, function(input)
        blockedInputs[input] = nil
        if dragging and activeInput and input.UserInputType == activeInput.UserInputType then
            dragging = false
            if not moved and onClick then onClick() end
        end
    end)
end

-- окно тянется за заголовок, фон и любые панели
makeDraggable({frame, header, content, vizFrame}, root)

-- ═════════════ СВОРАЧИВАНИЕ / ОТКРЫТИЕ ═════════════
local function openWindow()
    root.Visible = true
    local t = tween(uiScale, 0.5, {Scale = state.fit}, Enum.EasingStyle.Back)
    t.Completed:Connect(function()
        if not state.minimized and not state.closed then
            uiScale.Scale = state.fit
        end
    end)
end

local function setMinimized(min)
    state.minimized = min
    if min then
        tween(uiScale, 0.3, {Scale = 0}, Enum.EasingStyle.Back, Enum.EasingDirection.In)
        task.delay(0.3, function()
            if state.minimized and not state.closed then
                root.Visible = false
                floatBtn.Visible = true
                tween(floatBtn, 0.35, {Size = UDim2.fromOffset(56, 56)}, Enum.EasingStyle.Back)
            end
        end)
    else
        floatBtn.Visible = false
        floatBtn.Size = UDim2.fromOffset(0, 0)
        openWindow()
    end
end

makeDraggable({floatBtn}, floatBtn, function() setMinimized(false) end)
connect(minimizeBtn.MouseButton1Click, function() setMinimized(true) end)

-- Подгон под размер экрана (телефон в альбомной ориентации и т.п.)
connect(gui:GetPropertyChangedSignal("AbsoluteSize"), function()
    state.fit = fitScale()
    root.Size = UDim2.fromOffset(FULL_W * state.fit, FULL_H * state.fit)
    if not state.minimized and not state.closed then
        uiScale.Scale = state.fit
    end
end)

-- ═════════════ ЭФФЕКТЫ ВКЛ/ВЫКЛ ═════════════
local function setFx(on)
    state.fx = on
    dotsLayer.Visible = on
    if mainScene then mainScene.gui.Visible = on end
    fxStroke.Transparency = on and 0 or 0.7
    fxBtn.TextTransparency = on and 0 or 0.5
end
setFx(state.fx)

connect(fxBtn.MouseButton1Click, function()
    setFx(not state.fx)
    setStatus(state.fx and "✨  Эффекты включены" or "✨  Эффекты выключены (экономия FPS)", COLORS.idle)
end)

-- ═════════════ ПЛЕЙЛИСТ (логика) ═════════════
local playlistItems = {}
local renderPlaylist

local function playId(assetUrl, digits, displayName)
    state.loadToken += 1
    local token = state.loadToken

    sound:Stop()
    sound.SoundId = assetUrl
    sound.Looped = state.loop
    trackLabel.Text = displayName or ("ID " .. digits)
    setStatus("⏳  Загрузка...", COLORS.warn)

    task.spawn(function()
        local t0 = os.clock()
        while not sound.IsLoaded and os.clock() - t0 < CONFIG.LoadTimeout do
            if token ~= state.loadToken or state.closed then return end
            task.wait(0.1)
        end
        if token ~= state.loadToken or state.closed then return end

        if sound.IsLoaded and sound.TimeLength > 0 then
            sound.TimePosition = 0
            sound:Play()
            playBtn.Text = "⏸"
        else
            playBtn.Text = "▶"
            setStatus("❌  Не загрузилось. Проверь ID", COLORS.err)
        end
    end)
end

local function playFromBox()
    local url, digits = normalizeId(idBox.Text)
    if not url then
        setStatus("❌  Введи корректный ID музыки", COLORS.err)
        return
    end
    local name
    for i, item in ipairs(CONFIG.Playlist) do
        if item[2] == digits then
            state.playlistIndex = i
            name = item[1]
            break
        end
    end
    playId(url, digits, name)
    if renderPlaylist then renderPlaylist() end
end

local function playIndex(i)
    local item = CONFIG.Playlist[i]
    if not item then return end
    state.playlistIndex = i
    idBox.Text = item[2]
    local url, digits = normalizeId(item[2])
    playId(url, digits, item[1])
    renderPlaylist()
end

local function step(dir)
    local n = #CONFIG.Playlist
    if n == 0 then
        setStatus("📭  Плейлист пуст", COLORS.warn)
        return
    end
    playIndex(((state.playlistIndex - 1 + dir) % n) + 1)
end

renderPlaylist = function()
    for _, it in ipairs(playlistItems) do it:Destroy() end
    playlistItems = {}

    for i, item in ipairs(CONFIG.Playlist) do
        local active = (i == state.playlistIndex)
        local row = create("Frame", {
            Size = UDim2.new(1, 0, 0, 30),
            BackgroundColor3 = active and C.panelHover or C.panel2,
            BackgroundTransparency = active and 0.1 or 0.35,
            BorderSizePixel = 0,
            LayoutOrder = i,
            Parent = listFrame,
        }, {
            corner(8),
        })
        if active then
            neonStroke(row, 1.5, i * 40)
        end

        local pick = create("TextButton", {
            Size = UDim2.new(1, -34, 1, 0),
            BackgroundTransparency = 1,
            Text = string.format("%s%d. %s", active and "▶ " or "", i, item[1]),
            TextColor3 = C.text,
            Font = active and Enum.Font.GothamBold or Enum.Font.Gotham,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            AutoButtonColor = false,
            Parent = row,
        }, {
            create("UIPadding", {PaddingLeft = UDim.new(0, 10)}),
        })

        local del = create("TextButton", {
            Size = UDim2.fromOffset(26, 22),
            Position = UDim2.new(1, -30, 0.5, -11),
            BackgroundColor3 = Color3.fromRGB(150, 55, 75),
            Text = "✕",
            TextColor3 = WHITE,
            Font = Enum.Font.GothamBold,
            TextSize = 11,
            AutoButtonColor = false,
            Parent = row,
        }, {
            corner(6),
        })

        blockDragOn(pick)
        blockDragOn(del)
        connect(pick.MouseButton1Click, function() playIndex(i) end)
        connect(del.MouseButton1Click, function()
            table.remove(CONFIG.Playlist, i)
            if state.playlistIndex > #CONFIG.Playlist then
                state.playlistIndex = math.max(1, #CONFIG.Playlist)
            end
            renderPlaylist()
        end)

        table.insert(playlistItems, row)
    end
end
renderPlaylist()

-- ═════════════ ОБРАБОТЧИКИ КНОПОК ═════════════
connect(playBtn.MouseButton1Click, function()
    if sound.IsPlaying then
        sound:Pause()
        playBtn.Text = "▶"
        setStatus("⏸  Пауза", COLORS.idle)
    elseif sound.IsPaused then
        sound:Resume()
        playBtn.Text = "⏸"
    else
        playFromBox()
    end
end)

connect(stopBtn.MouseButton1Click, function()
    state.loadToken += 1
    sound:Stop()
    sound.TimePosition = 0
    playBtn.Text = "▶"
    bar.Size = UDim2.new(0, 0, 1, 0)
    knob.Position = UDim2.new(0, 0, 0.5, 0)
    timeLeft.Text = "0:00"
    setStatus("⏹  Остановлено", COLORS.idle)
end)

connect(nextBtn.MouseButton1Click, function() step(1) end)
connect(prevBtn.MouseButton1Click, function() step(-1) end)

local function refreshLoopButton()
    if state.loop then
        loopBtn.TextTransparency = 0
        loopStroke.Transparency = 0
    else
        loopBtn.TextTransparency = 0.55
        loopStroke.Transparency = 0.75
    end
end
connect(loopBtn.MouseButton1Click, function()
    state.loop = not state.loop
    sound.Looped = state.loop
    refreshLoopButton()
end)
refreshLoopButton()

connect(clearBtn.MouseButton1Click, function()
    idBox.Text = ""
    idBox:CaptureFocus()
end)

connect(addBtn.MouseButton1Click, function()
    local url, digits = normalizeId(idBox.Text)
    if not url then
        setStatus("❌  Нельзя добавить: неверный ID", COLORS.err)
        return
    end
    for _, item in ipairs(CONFIG.Playlist) do
        if item[2] == digits then
            setStatus("ℹ️  Этот ID уже в плейлисте", COLORS.warn)
            return
        end
    end
    table.insert(CONFIG.Playlist, {"Трек " .. (#CONFIG.Playlist + 1), digits})
    renderPlaylist()
    setStatus("✅  Добавлено в плейлист", COLORS.ok)
end)

connect(idBox.FocusLost, function(enterPressed)
    if enterPressed then playFromBox() end
end)

-- ═════════════ СЛАЙДЕРЫ: ПЕРЕМОТКА И ГРОМКОСТЬ ═════════════
local function makeSlider(hit, track, onChange)
    local dragging = false
    local function update(x)
        local rel = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
        onChange(rel)
    end
    connect(hit.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            blockedInputs[input] = true
            dragging = true
            update(input.Position.X)
        end
    end)
    connect(UIS.InputChanged, function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            update(input.Position.X)
        end
    end)
    connect(UIS.InputEnded, function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch) then
            dragging = false
        end
    end)
    return function() return dragging end
end

makeSlider(volHit, volBg, function(rel)
    state.volume = rel
    sound.Volume = rel * CONFIG.MaxVolume
    volFill.Size = UDim2.new(rel, 0, 1, 0)
    volKnob.Position = UDim2.new(rel, 0, 0.5, 0)
    volLabel.Text = math.floor(rel * 100) .. "%"
end)

local seeking = makeSlider(barHit, barBg, function(rel)
    bar.Size = UDim2.new(rel, 0, 1, 0)
    knob.Position = UDim2.new(rel, 0, 0.5, 0)
    if sound.TimeLength > 0 then
        sound.TimePosition = rel * sound.TimeLength
        timeLeft.Text = fmtTime(sound.TimePosition)
    end
end)

-- ═════════════ АВТОПЕРЕХОД ═════════════
connect(sound.Ended, function()
    if not state.loop and not state.closed then
        if #CONFIG.Playlist > 1 then
            step(1)
        else
            playBtn.Text = "▶"
            setStatus("✔️  Трек закончился", COLORS.idle)
        end
    end
end)

-- ═════════════ ГЛАВНЫЙ ЦИКЛ АНИМАЦИЙ ═════════════
local hue, spin = 0, 0
local smoothLoud = 0
local barLevels = table.create(CONFIG.BarCount, 0.08)
local clock = 0

connect(RunService.RenderStepped, function(dt)
    if state.closed then return end
    dt = math.min(dt, 0.1)
    clock += dt
    hue = (hue + dt * 0.12) % 1
    spin = (spin + dt * 90) % 360

    local c1 = Color3.fromHSV(hue, 0.75, 1)
    local c2 = Color3.fromHSV((hue + 0.3) % 1, 0.75, 1)
    local c3 = Color3.fromHSV((hue + 0.6) % 1, 0.75, 1)
    local seq = ColorSequence.new({
        ColorSequenceKeypoint.new(0, c1),
        ColorSequenceKeypoint.new(0.5, c2),
        ColorSequenceKeypoint.new(1, c3),
    })

    -- вращение радужных обводок
    for i = #spinners, 1, -1 do
        local sp = spinners[i]
        if sp.g.Parent and sp.g:IsDescendantOf(gui) then
            sp.g.Rotation = (spin + sp.off) % 360
        else
            table.remove(spinners, i)
        end
    end

    headerLineGradient.Color = seq
    barGradient.Color = seq
    volGradient.Color = seq
    knobStroke.Color = c1
    volKnobStroke.Color = c2
    glow.ImageColor3 = c1

    -- громкость музыки → энергия
    local playing = sound.IsPlaying
    local target = playing and math.clamp(sound.PlaybackLoudness / 450, 0, 1) or 0
    smoothLoud += (target - smoothLoud) * math.min(dt * 12, 1)

    -- свечение окна
    local a = frame.AbsoluteSize
    glow.Size = UDim2.fromOffset(a.X + 60, a.Y + 60)
    glow.ImageTransparency = 0.62 - smoothLoud * 0.35

    -- вращающийся диск
    if playing then
        iconLabel.Rotation = (iconLabel.Rotation + dt * 140) % 360
    end

    -- эквалайзер
    for i = 1, CONFIG.BarCount do
        local wave = playing and (0.55 + 0.45 * math.sin(clock * 5 + i * 0.7)) or 0
        local want = 0.08 + smoothLoud * wave * 0.92
        barLevels[i] += (want - barLevels[i]) * math.min(dt * 14, 1)
        bars[i].Size = UDim2.new(1 / CONFIG.BarCount, -3, barLevels[i], 0)
        bars[i].BackgroundColor3 = Color3.fromHSV((hue + i / CONFIG.BarCount * 0.6) % 1, 0.7, 1)
    end

    -- неоновые точки и 3D-кубы
    if state.fx and not state.minimized then
        local speedBoost = 1 + smoothLoud * 4
        for _, d in ipairs(dots) do
            d.x += d.vx * dt * speedBoost
            d.y += d.vy * dt * speedBoost
            if d.x < 0.02 then d.x = 0.98 elseif d.x > 0.98 then d.x = 0.02 end
            if d.y < 0.02 then d.y = 0.98 elseif d.y > 0.98 then d.y = 0.02 end

            local col = Color3.fromHSV((hue + d.off) % 1, 0.8, 1)
            local twinkle = 0.5 + 0.5 * math.sin(clock * 2 + d.ph)
            d.f.Position = UDim2.new(d.x, 0, d.y, 0)
            d.f.BackgroundColor3 = col
            d.f.BackgroundTransparency = 0.05 + 0.5 * (1 - twinkle) - smoothLoud * 0.1
            d.s.Color = col
            d.s.Transparency = 0.7 + 0.25 * (1 - twinkle)
        end
        if mainScene then
            mainScene.update(dt, hue, smoothLoud)
        end
    end

    if floatBtn.Visible and floatScene then
        floatScene.update(dt, hue, smoothLoud)
    end

    -- прогресс
    if sound.TimeLength > 0 then
        timeRight.Text = fmtTime(sound.TimeLength)
        if not seeking() then
            local rel = math.clamp(sound.TimePosition / sound.TimeLength, 0, 1)
            bar.Size = UDim2.new(rel, 0, 1, 0)
            knob.Position = UDim2.new(rel, 0, 0.5, 0)
            timeLeft.Text = fmtTime(sound.TimePosition)
        end
    end
end)

-- Статус «Играет» раз в полсекунды (не перебивает ошибки и загрузку)
task.spawn(function()
    while not state.closed do
        if sound.IsPlaying then
            setStatus("▶  Играет" .. (state.loop and " · 🔁" or ""), COLORS.ok)
            if playBtn.Text ~= "⏸" then playBtn.Text = "⏸" end
        end
        task.wait(0.5)
    end
end)

-- ═════════════ ЗАКРЫТИЕ ═════════════
local function shutdown()
    if state.closed then return end
    state.closed = true
    state.loadToken += 1
    sound:Stop()
    tween(uiScale, 0.25, {Scale = 0}, Enum.EasingStyle.Back, Enum.EasingDirection.In)
    task.delay(0.3, function()
        for _, c in ipairs(connections) do
            pcall(function() c:Disconnect() end)
        end
        gui:Destroy()
        sound:Destroy()
    end)
end
connect(closeBtn.MouseButton1Click, shutdown)

-- ═════════════ ПОЯВЛЕНИЕ ═════════════
openWindow()
