-- ╔══════════════════════════════════════════════╗
-- ║  RGB MUSIC PLAYER v2 · Delta Edition         ║
-- ║  LocalScript · работает только для тебя      ║
-- ╚══════════════════════════════════════════════╝

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Защита от дублей: удаляем старую версию, если запущена
local OLD = playerGui:FindFirstChild("RGBMusicPlayer")
if OLD then OLD:Destroy() end
local OLD_SOUND = playerGui:FindFirstChild("RGBMusic")
if OLD_SOUND then OLD_SOUND:Destroy() end

-- ═════════════ НАСТРОЙКИ ═════════════
local CONFIG = {
    DefaultId = "74612331354602",
    DefaultVolume = 0.5,      -- 0..1
    MaxVolume = 10,           -- множитель Sound.Volume
    LoadTimeout = 8,          -- секунд ожидания загрузки
    BarCount = 24,            -- столбиков эквалайзера
    Playlist = {              -- {название, id}
        {"Трек 1", "74612331354602"},
    },
}

-- ═════════════ УТИЛИТЫ ═════════════
local connections = {}
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
}

-- ═════════════ GUI ═════════════
local gui = create("ScreenGui", {
    Name = "RGBMusicPlayer",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 999,
    Parent = playerGui,
})

local FULL_SIZE = UDim2.new(0, 360, 0, 500)
local HEADER_H = 54

-- Внешнее свечение (вне frame, чтобы не обрезалось ClipsDescendants)
local glow = create("ImageLabel", {
    Name = "Glow",
    Size = UDim2.new(0, 0, 0, 0),
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.5, 0),
    BackgroundTransparency = 1,
    Image = "rbxassetid://5028857472",
    ImageColor3 = Color3.fromRGB(120, 80, 255),
    ImageTransparency = 0.55,
    ScaleType = Enum.ScaleType.Slice,
    SliceCenter = Rect.new(24, 24, 276, 276),
    ZIndex = 0,
    Parent = gui,
})

local frame = create("Frame", {
    Name = "Main",
    Size = UDim2.new(0, 0, 0, 0),
    Position = UDim2.new(0.5, 0, 0.5, 0),
    AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundColor3 = Color3.fromRGB(14, 14, 22),
    BorderSizePixel = 0,
    ClipsDescendants = true,
    ZIndex = 1,
    Parent = gui,
}, {
    corner(18),
})

local stroke = create("UIStroke", {
    Thickness = 2,
    Color = Color3.fromRGB(120, 80, 255),
    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    Parent = frame,
})

create("UIGradient", {
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(26, 22, 48)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(14, 14, 24)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(32, 16, 42)),
    }),
    Rotation = 45,
    Parent = frame,
})

-- ═════════════ ЗАГОЛОВОК ═════════════
local header = create("Frame", {
    Name = "Header",
    Size = UDim2.new(1, 0, 0, HEADER_H),
    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
    BorderSizePixel = 0,
    Parent = frame,
})
local headerGradient = create("UIGradient", {
    Color = ColorSequence.new(Color3.fromRGB(120, 80, 255)),
    Rotation = 0,
    Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.15),
        NumberSequenceKeypoint.new(1, 0.45),
    }),
    Parent = header,
})

create("TextLabel", {
    Size = UDim2.new(0, 40, 1, 0),
    Position = UDim2.new(0, 12, 0, 0),
    BackgroundTransparency = 1,
    Text = "🎵",
    TextSize = 26,
    Font = Enum.Font.GothamBold,
    Parent = header,
})

create("TextLabel", {
    Size = UDim2.new(1, -150, 0, 24),
    Position = UDim2.new(0, 54, 0, 8),
    BackgroundTransparency = 1,
    Text = "RGB MUSIC",
    TextColor3 = Color3.fromRGB(255, 255, 255),
    Font = Enum.Font.GothamBlack,
    TextSize = 17,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = header,
})

create("TextLabel", {
    Size = UDim2.new(1, -150, 0, 14),
    Position = UDim2.new(0, 54, 0, 31),
    BackgroundTransparency = 1,
    Text = "Delta Edition · v2",
    TextColor3 = Color3.fromRGB(235, 225, 255),
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = header,
})

local function headerButton(text, xOffset, color)
    local b = create("TextButton", {
        Size = UDim2.new(0, 32, 0, 32),
        Position = UDim2.new(1, xOffset, 0, 11),
        BackgroundColor3 = color,
        Text = text,
        TextColor3 = Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.GothamBold,
        TextSize = 15,
        AutoButtonColor = false,
        Parent = header,
    }, { corner(9) })
    connect(b.MouseEnter, function() tween(b, 0.15, {BackgroundTransparency = 0.25}) end)
    connect(b.MouseLeave, function() tween(b, 0.15, {BackgroundTransparency = 0}) end)
    return b
end

local minimizeBtn = headerButton("—", -78, Color3.fromRGB(70, 62, 110))
local closeBtn = headerButton("✕", -42, Color3.fromRGB(200, 60, 80))

-- ═════════════ ПЕРЕТАСКИВАНИЕ (мышь + тач) ═════════════
local function makeDraggable(handle, target, onClick)
    local dragging, dragStart, startPos, moved
    connect(handle.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            moved = false
            dragStart = input.Position
            startPos = target.Position
            local c
            c = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if c then c:Disconnect() end
                    if not moved and onClick then onClick() end
                end
            end)
        end
    end)
    connect(UIS.InputChanged, function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            if d.Magnitude > 4 then moved = true end
            target.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y
            )
        end
    end)
end
makeDraggable(header, frame)

-- Свечение следует за окном
connect(RunService.RenderStepped, function()
    if frame.Visible then
        glow.Visible = true
        glow.Position = frame.Position
        glow.Size = UDim2.new(0, frame.AbsoluteSize.X + 50, 0, frame.AbsoluteSize.Y + 50)
    else
        glow.Visible = false
    end
end)

-- ═════════════ КОНТЕНТ ═════════════
local content = create("Frame", {
    Name = "Content",
    Size = UDim2.new(1, 0, 1, -HEADER_H),
    Position = UDim2.new(0, 0, 0, HEADER_H),
    BackgroundTransparency = 1,
    Parent = frame,
})

-- Название трека
local trackLabel = create("TextLabel", {
    Size = UDim2.new(1, -30, 0, 22),
    Position = UDim2.new(0, 15, 0, 10),
    BackgroundTransparency = 1,
    Text = "Ничего не играет",
    TextColor3 = Color3.fromRGB(255, 255, 255),
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
    BackgroundColor3 = Color3.fromRGB(22, 19, 38),
    BorderSizePixel = 0,
    Parent = content,
}, { corner(12) })

local bars = {}
local barsHolder = create("Frame", {
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
for i = 1, CONFIG.BarCount do
    bars[i] = create("Frame", {
        Size = UDim2.new(1 / CONFIG.BarCount, -3, 0.08, 0),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
        LayoutOrder = i,
        Parent = barsHolder,
    }, { corner(3) })
end

-- ─── Поле ID ───
create("TextLabel", {
    Size = UDim2.new(1, -30, 0, 16),
    Position = UDim2.new(0, 15, 0, 112),
    BackgroundTransparency = 1,
    Text = "MUSIC ID",
    TextColor3 = Color3.fromRGB(150, 140, 200),
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
    BackgroundColor3 = Color3.fromRGB(28, 24, 48),
    TextColor3 = Color3.fromRGB(255, 255, 255),
    PlaceholderColor3 = Color3.fromRGB(120, 110, 160),
    Font = Enum.Font.Gotham,
    TextSize = 14,
    ClearTextOnFocus = false,
    Parent = content,
}, { corner(10) })

local idStroke = create("UIStroke", {
    Color = Color3.fromRGB(120, 80, 255),
    Thickness = 1.5,
    Transparency = 0.4,
    Parent = idBox,
})
connect(idBox.Focused, function() tween(idStroke, 0.2, {Transparency = 0, Thickness = 2}) end)
connect(idBox.FocusLost, function() tween(idStroke, 0.2, {Transparency = 0.4, Thickness = 1.5}) end)

-- Кнопка «добавить в плейлист»
local addBtn = create("TextButton", {
    Size = UDim2.new(0, 38, 0, 38),
    Position = UDim2.new(1, -87, 0, 130),
    BackgroundColor3 = Color3.fromRGB(60, 130, 200),
    Text = "＋",
    TextColor3 = Color3.fromRGB(255, 255, 255),
    Font = Enum.Font.GothamBold,
    TextSize = 20,
    AutoButtonColor = false,
    Parent = content,
}, { corner(10) })

-- Кнопка «вставить/очистить»
local clearBtn = create("TextButton", {
    Size = UDim2.new(0, 38, 0, 38),
    Position = UDim2.new(1, -47, 0, 130),
    BackgroundColor3 = Color3.fromRGB(90, 80, 130),
    Text = "⌫",
    TextColor3 = Color3.fromRGB(255, 255, 255),
    Font = Enum.Font.GothamBold,
    TextSize = 16,
    AutoButtonColor = false,
    Parent = content,
}, { corner(10) })

-- ─── Прогресс-бар (кликабельный) ───
local timeLeft = create("TextLabel", {
    Size = UDim2.new(0, 50, 0, 14),
    Position = UDim2.new(0, 15, 0, 180),
    BackgroundTransparency = 1,
    Text = "0:00",
    TextColor3 = Color3.fromRGB(170, 160, 210),
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
    TextColor3 = Color3.fromRGB(170, 160, 210),
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Right,
    Parent = content,
})

-- увеличенная невидимая зона нажатия для тач-экрана
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
    BackgroundColor3 = Color3.fromRGB(35, 30, 55),
    BorderSizePixel = 0,
    Parent = barHit,
}, { corner(8) })
local bar = create("Frame", {
    Size = UDim2.new(0, 0, 1, 0),
    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
    BorderSizePixel = 0,
    Parent = barBg,
}, { corner(8) })
local barGradient = create("UIGradient", {
    Color = ColorSequence.new(Color3.fromRGB(200, 80, 220)),
    Parent = bar,
})
local knob = create("Frame", {
    Size = UDim2.new(0, 14, 0, 14),
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0, 0, 0.5, 0),
    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
    BorderSizePixel = 0,
    ZIndex = 3,
    Parent = barBg,
}, { corner(14) })

-- ─── Кнопки управления ───
local controls = create("Frame", {
    Size = UDim2.new(1, -30, 0, 56),
    Position = UDim2.new(0, 15, 0, 228),
    BackgroundTransparency = 1,
    Parent = content,
})

local function ctrlButton(text, size, x, colorTop, colorBottom, textSize)
    local b = create("TextButton", {
        Size = UDim2.new(0, size, 0, size),
        Position = UDim2.new(0, x, 0.5, -size / 2),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        Text = text,
        TextColor3 = Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.GothamBold,
        TextSize = textSize or 18,
        AutoButtonColor = false,
        Parent = controls,
    }, {
        corner(size / 2),
        create("UIGradient", {
            Color = ColorSequence.new(colorTop, colorBottom),
            Rotation = 90,
        }),
    })
    local base = b.Size
    connect(b.MouseButton1Down, function()
        tween(b, 0.08, {Size = UDim2.new(0, size - 6, 0, size - 6),
            Position = UDim2.new(0, x + 3, 0.5, -(size - 6) / 2)})
    end)
    local function release()
        tween(b, 0.15, {Size = base, Position = UDim2.new(0, x, 0.5, -size / 2)},
            Enum.EasingStyle.Back)
    end
    connect(b.MouseButton1Up, release)
    connect(b.MouseLeave, release)
    return b
end

-- Ширина controls = 330 (при окне 360): центрируем 5 кнопок
local prevBtn  = ctrlButton("⏮", 44, 20,  Color3.fromRGB(110, 100, 170), Color3.fromRGB(70, 62, 120), 16)
local playBtn  = ctrlButton("▶", 56, 80,  Color3.fromRGB(100, 230, 140), Color3.fromRGB(50, 170, 90), 22)
local stopBtn  = ctrlButton("⏹", 44, 152, Color3.fromRGB(230, 90, 110),  Color3.fromRGB(170, 50, 70), 16)
local nextBtn  = ctrlButton("⏭", 44, 212, Color3.fromRGB(110, 100, 170), Color3.fromRGB(70, 62, 120), 16)
local loopBtn  = ctrlButton("🔁", 44, 272, Color3.fromRGB(80, 150, 220),  Color3.fromRGB(60, 100, 180), 16)

-- ─── Громкость ───
create("TextLabel", {
    Size = UDim2.new(0, 30, 0, 20),
    Position = UDim2.new(0, 15, 0, 296),
    BackgroundTransparency = 1,
    Text = "🔊",
    TextSize = 16,
    Font = Enum.Font.GothamBold,
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
    BackgroundColor3 = Color3.fromRGB(35, 30, 55),
    BorderSizePixel = 0,
    Parent = volHit,
}, { corner(6) })
local volFill = create("Frame", {
    Size = UDim2.new(state.volume, 0, 1, 0),
    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
    BorderSizePixel = 0,
    Parent = volBg,
}, { corner(6) })
local volGradient = create("UIGradient", {
    Color = ColorSequence.new(Color3.fromRGB(80, 220, 200)),
    Parent = volFill,
})
local volKnob = create("Frame", {
    Size = UDim2.new(0, 14, 0, 14),
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(state.volume, 0, 0.5, 0),
    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
    BorderSizePixel = 0,
    ZIndex = 3,
    Parent = volBg,
}, { corner(14) })
local volLabel = create("TextLabel", {
    Size = UDim2.new(0, 50, 0, 20),
    Position = UDim2.new(1, -65, 0, 296),
    BackgroundTransparency = 1,
    Text = math.floor(state.volume * 100) .. "%",
    TextColor3 = Color3.fromRGB(170, 160, 210),
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
    TextColor3 = Color3.fromRGB(150, 140, 200),
    Font = Enum.Font.GothamBold,
    TextSize = 10,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = content,
})

local listFrame = create("ScrollingFrame", {
    Size = UDim2.new(1, -30, 0, 84),
    Position = UDim2.new(0, 15, 0, 344),
    BackgroundColor3 = Color3.fromRGB(22, 19, 38),
    BorderSizePixel = 0,
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = Color3.fromRGB(140, 100, 255),
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

-- ─── Статус ───
local status = create("TextLabel", {
    Size = UDim2.new(1, -30, 0, 20),
    Position = UDim2.new(0, 15, 0, 436),
    BackgroundTransparency = 1,
    Text = "💤  Готово к запуску",
    TextColor3 = Color3.fromRGB(160, 150, 200),
    Font = Enum.Font.Gotham,
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
    Parent = content,
})

create("TextLabel", {
    Size = UDim2.new(1, 0, 0, 14),
    Position = UDim2.new(0, 0, 1, -16),
    BackgroundTransparency = 1,
    Text = "by CVEDC · RGB Edition v2",
    TextColor3 = Color3.fromRGB(90, 80, 130),
    Font = Enum.Font.Gotham,
    TextSize = 10,
    Parent = content,
})

-- ═════════════ СВОРАЧИВАНИЕ В ПЛАВАЮЩУЮ КНОПКУ ═════════════
local floatBtn = create("TextButton", {
    Name = "FloatButton",
    Size = UDim2.new(0, 0, 0, 0),
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0, 60, 0.5, 0),
    BackgroundColor3 = Color3.fromRGB(30, 25, 50),
    Text = "🎵",
    TextSize = 26,
    Font = Enum.Font.GothamBold,
    AutoButtonColor = false,
    Visible = false,
    ZIndex = 5,
    Parent = gui,
}, { corner(28) })
local floatStroke = create("UIStroke", {
    Thickness = 2.5,
    Color = Color3.fromRGB(120, 80, 255),
    Parent = floatBtn,
})

local function setMinimized(min)
    state.minimized = min
    if min then
        tween(frame, 0.3, {Size = UDim2.new(0, 0, 0, 0)}, Enum.EasingStyle.Back, Enum.EasingDirection.In)
        task.delay(0.3, function()
            if state.minimized and not state.closed then
                frame.Visible = false
                floatBtn.Visible = true
                tween(floatBtn, 0.3, {Size = UDim2.new(0, 56, 0, 56)}, Enum.EasingStyle.Back)
            end
        end)
    else
        floatBtn.Visible = false
        floatBtn.Size = UDim2.new(0, 0, 0, 0)
        frame.Visible = true
        frame.Position = UDim2.new(0.5, 0, 0.5, 0)
        tween(frame, 0.4, {Size = FULL_SIZE}, Enum.EasingStyle.Back)
    end
end

makeDraggable(floatBtn, floatBtn, function() setMinimized(false) end)
connect(minimizeBtn.MouseButton1Click, function() setMinimized(true) end)

-- ═════════════ ПЛЕЙЛИСТ (логика) ═════════════
local playlistItems = {}
local renderPlaylist

local function setStatus(text, color)
    status.Text = text
    status.TextColor3 = color or Color3.fromRGB(160, 150, 200)
end

local COLORS = {
    ok = Color3.fromRGB(120, 255, 160),
    warn = Color3.fromRGB(255, 200, 100),
    err = Color3.fromRGB(255, 120, 120),
    idle = Color3.fromRGB(200, 200, 220),
}

local function currentTrackName()
    local item = CONFIG.Playlist[state.playlistIndex]
    return item and item[1] or "Трек"
end

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
    -- если ID есть в плейлисте — берём название
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
            BackgroundColor3 = active and Color3.fromRGB(60, 50, 110) or Color3.fromRGB(32, 28, 54),
            BorderSizePixel = 0,
            LayoutOrder = i,
            Parent = listFrame,
        }, { corner(8) })

        local pick = create("TextButton", {
            Size = UDim2.new(1, -34, 1, 0),
            BackgroundTransparency = 1,
            Text = string.format("%s%d. %s", active and "▶ " or "", i, item[1]),
            TextColor3 = Color3.fromRGB(240, 235, 255),
            Font = active and Enum.Font.GothamBold or Enum.Font.Gotham,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            AutoButtonColor = false,
            Parent = row,
        }, { create("UIPadding", {PaddingLeft = UDim.new(0, 10)}) })

        local del = create("TextButton", {
            Size = UDim2.new(0, 26, 0, 22),
            Position = UDim2.new(1, -30, 0.5, -11),
            BackgroundColor3 = Color3.fromRGB(150, 50, 70),
            Text = "✕",
            TextColor3 = Color3.fromRGB(255, 255, 255),
            Font = Enum.Font.GothamBold,
            TextSize = 11,
            AutoButtonColor = false,
            Parent = row,
        }, { corner(6) })

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
    local grad = loopBtn:FindFirstChildOfClass("UIGradient")
    if state.loop then
        grad.Color = ColorSequence.new(Color3.fromRGB(80, 150, 220), Color3.fromRGB(60, 100, 180))
        loopBtn.TextTransparency = 0
    else
        grad.Color = ColorSequence.new(Color3.fromRGB(90, 90, 110), Color3.fromRGB(60, 60, 80))
        loopBtn.TextTransparency = 0.5
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

-- Enter в поле ID = играть
connect(idBox.FocusLost, function(enterPressed)
    if enterPressed then playFromBox() end
end)

-- ═════════════ ПЕРЕМОТКА И ГРОМКОСТЬ (слайдеры) ═════════════
local function makeSlider(hit, track, onChange, onBegin, onEnd)
    local dragging = false
    local function update(x)
        local rel = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
        onChange(rel)
    end
    connect(hit.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            if onBegin then onBegin() end
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
            if onEnd then onEnd() end
        end
    end)
    return function() return dragging end
end

-- Громкость
makeSlider(volHit, volBg, function(rel)
    state.volume = rel
    sound.Volume = rel * CONFIG.MaxVolume
    volFill.Size = UDim2.new(rel, 0, 1, 0)
    volKnob.Position = UDim2.new(rel, 0, 0.5, 0)
    volLabel.Text = math.floor(rel * 100) .. "%"
end)

-- Перемотка
local seeking = makeSlider(barHit, barBg, function(rel)
    bar.Size = UDim2.new(rel, 0, 1, 0)
    knob.Position = UDim2.new(rel, 0, 0.5, 0)
    if sound.TimeLength > 0 then
        sound.TimePosition = rel * sound.TimeLength
        timeLeft.Text = fmtTime(sound.TimePosition)
    end
end)

-- ═════════════ АВТОПЕРЕХОД ПРИ ОКОНЧАНИИ ТРЕКА ═════════════
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

-- ═════════════ АНИМАЦИЯ RGB + ВИЗУАЛИЗАТОР + ПРОГРЕСС ═════════════
local hue = 0
local smoothLoud = 0
local barLevels = table.create(CONFIG.BarCount, 0.08)

local rgbConnection = RunService.RenderStepped:Connect(function(dt)
    if state.closed then return end
    hue = (hue + dt * 0.15) % 1

    local c1 = Color3.fromHSV(hue, 0.75, 1)
    local c2 = Color3.fromHSV((hue + 0.3) % 1, 0.75, 1)
    local c3 = Color3.fromHSV((hue + 0.6) % 1, 0.75, 1)
    local seq = ColorSequence.new({
        ColorSequenceKeypoint.new(0, c1),
        ColorSequenceKeypoint.new(0.5, c2),
        ColorSequenceKeypoint.new(1, c3),
    })

    stroke.Color = c1
    floatStroke.Color = c1
    glow.ImageColor3 = c1
    headerGradient.Color = seq
    barGradient.Color = seq
    volGradient.Color = seq

    -- Эквалайзер
    local playing = sound.IsPlaying
    local target = playing and math.clamp(sound.PlaybackLoudness / 500, 0, 1) or 0
    smoothLoud += (target - smoothLoud) * math.min(dt * 12, 1)

    for i = 1, CONFIG.BarCount do
        local wave = playing
            and (0.55 + 0.45 * math.sin(os.clock() * 5 + i * 0.7))
            or 0
        local want = 0.08 + smoothLoud * wave * 0.92
        barLevels[i] += (want - barLevels[i]) * math.min(dt * 14, 1)
        bars[i].Size = UDim2.new(1 / CONFIG.BarCount, -3, barLevels[i], 0)
        bars[i].BackgroundColor3 = Color3.fromHSV((hue + i / CONFIG.BarCount * 0.6) % 1, 0.7, 1)
    end

    -- Прогресс
    if sound.TimeLength > 0 then
        timeRight.Text = fmtTime(sound.TimeLength)
        if not seeking() then
            local rel = sound.TimePosition / sound.TimeLength
            bar.Size = UDim2.new(rel, 0, 1, 0)
            knob.Position = UDim2.new(rel, 0, 0.5, 0)
            timeLeft.Text = fmtTime(sound.TimePosition)
        end
    end
end)
table.insert(connections, rgbConnection)

-- Обновление статуса раз в 0.5 c (не перебивает ошибки/загрузку)
task.spawn(function()
    while not state.closed do
        if sound.IsPlaying then
            setStatus(
                "▶  Играет" .. (state.loop and " · 🔁" or ""),
                COLORS.ok
            )
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
    for _, c in ipairs(connections) do
        pcall(function() c:Disconnect() end)
    end
    tween(frame, 0.25, {Size = UDim2.new(0, 0, 0, 0)}, Enum.EasingStyle.Back, Enum.EasingDirection.In)
    task.delay(0.3, function()
        gui:Destroy()
        sound:Destroy()
    end)
end
connect(closeBtn.MouseButton1Click, shutdown)

-- ═════════════ ПОЯВЛЕНИЕ ОКНА ═════════════
tween(frame, 0.5, {Size = FULL_SIZE}, Enum.EasingStyle.Back)
