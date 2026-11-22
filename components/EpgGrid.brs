' Full EPG grid for a constrained Roku. Only visible channels/time are rendered.

sub init()
    m.gridLayer = m.top.findNode("gridLayer")
    m.timeLayer = m.top.findNode("timeLayer")
    m.nowLayer = m.top.findNode("nowLayer")
    m.range = m.top.findNode("range")
    m.detailChannel = m.top.findNode("detailChannel")
    m.detailTitle = m.top.findNode("detailTitle")
    m.detailTime = m.top.findNode("detailTime")
    m.detailDesc = m.top.findNode("detailDesc")
    m.detailNote = m.top.findNode("detailNote")
    m.clockTimer = m.top.findNode("clockTimer")

    m.timeX = 200
    m.timeW = 1040
    m.rowTop = 100
    m.rowH = 74
    m.visibleRows = 6
    m.windowMinutes = 240
    m.windowStart = 0
    m.row = 0
    m.rowOffset = 0
    m.selectedProgramIndex = -1
    m.cursorTime = NowSeconds()
    m.lastStartId = ""
    m.visibleChannels = []
    m.selectedChannelKey = ""
    m.selectedOriginalIndex = 0
    m.clockTimer.observeField("fire", "onClock")
    m.clockTimer.control = "start"
end sub

sub onDataChanged()
    if m.top.channels = invalid then return
    if m.top.channels.Count() = 0 then
        m.visibleChannels = []
        m.row = 0
        m.rowOffset = 0
        RenderGrid()
        return
    end if

    now = NowSeconds()
    startId = m.top.startChannelId
    if m.windowStart = 0 or startId <> m.lastStartId then
        m.lastStartId = startId
        m.windowStart = Align30(now - 1800)
        if m.top.epg <> invalid and m.top.epg.windowStart <> invalid then
            if m.windowStart < m.top.epg.windowStart then m.windowStart = m.top.epg.windowStart
        end if
        BuildVisibleChannels()
        orig = FindOriginalChannelIndex(startId)
        SelectVisibleNearest(orig)
        m.cursorTime = now
        m.selectedProgramIndex = FindProgramAtTime(ProgramsForRow(m.row), now)
    else
        oldKey = m.selectedChannelKey
        oldOrig = m.selectedOriginalIndex
        BuildVisibleChannels()
        PreserveSelection(oldKey, oldOrig)
        progs = ProgramsForRow(m.row)
        if m.selectedProgramIndex < 0 or m.selectedProgramIndex >= progs.Count() then
            m.selectedProgramIndex = FindProgramAtTime(progs, m.cursorTime)
        end if
    end if
    RenderGrid()
end sub

sub onClock()
    if m.top.visible = false then return
    RenderGrid()
end sub

function Align30(value as Integer) as Integer
    return value - (value mod 1800)
end function

function ChannelKey(ch as Object) as String
    if ch.tvgId <> invalid and ch.tvgId <> "" then return ch.tvgId
    if ch.url <> invalid then return ch.url
    return ch.name
end function

function FindOriginalChannelIndex(id as String) as Integer
    if id = "" or m.top.channels = invalid then return -1
    for i = 0 to m.top.channels.Count() - 1
        ch = m.top.channels[i]
        if ch.tvgId <> invalid and ch.tvgId = id then return i
        if ch.url <> invalid and ch.url = id then return i
    end for
    return -1
end function

function ChannelEpgId(ch as Object) as String
    return CatalogEpgIdForItem(m.top.catalog, ch)
end function

function ProgramsForChannel(ch as Object) as Object
    epgId = ChannelEpgId(ch)
    if epgId = "" or m.top.epg = invalid then return []
    channel = EpgFindChannel(m.top.epg, epgId)
    if channel = invalid or channel.programs = invalid then return []
    return channel.programs
end function

sub BuildVisibleChannels()
    m.visibleChannels = []
    if m.top.channels = invalid then return
    ws = m.windowStart
    we = WindowEnd()
    for i = 0 to m.top.channels.Count() - 1
        ch = m.top.channels[i]
        if ch.kind = "ch" then
            progs = ProgramsForChannel(ch)
            if EpgProgramsOverlap(progs, ws, we) then
                m.visibleChannels.Push({ channel: ch, originalIndex: i })
            end if
        end if
    end for
end sub

function ProgramsForRow(rowIndex as Integer) as Object
    if rowIndex < 0 or rowIndex >= m.visibleChannels.Count() then return []
    return ProgramsForChannel(m.visibleChannels[rowIndex].channel)
end function

function NearestVisibleIndex(originalIndex as Integer) as Integer
    if m.visibleChannels.Count() = 0 then return -1
    best = 0
    bestDiff = Abs(m.visibleChannels[0].originalIndex - originalIndex)
    for i = 1 to m.visibleChannels.Count() - 1
        diff = Abs(m.visibleChannels[i].originalIndex - originalIndex)
        if diff < bestDiff then
            best = i
            bestDiff = diff
        end if
    end for
    return best
end function

sub SetVisibleRow(rowIndex as Integer)
    if m.visibleChannels.Count() = 0 then
        m.row = 0
        m.rowOffset = 0
        m.selectedChannelKey = ""
        m.selectedOriginalIndex = 0
        return
    end if
    if rowIndex < 0 then rowIndex = 0
    if rowIndex >= m.visibleChannels.Count() then rowIndex = m.visibleChannels.Count() - 1
    m.row = rowIndex
    m.selectedChannelKey = ChannelKey(m.visibleChannels[rowIndex].channel)
    m.selectedOriginalIndex = m.visibleChannels[rowIndex].originalIndex
end sub

sub SelectVisibleNearest(originalIndex as Integer)
    if originalIndex < 0 then originalIndex = 0
    idx = NearestVisibleIndex(originalIndex)
    if idx < 0 then
        SetVisibleRow(0)
        return
    end if
    SetVisibleRow(idx)
end sub

sub PreserveSelection(oldKey as String, oldOriginalIndex as Integer)
    if m.visibleChannels.Count() = 0 then
        SetVisibleRow(0)
        return
    end if
    for i = 0 to m.visibleChannels.Count() - 1
        if ChannelKey(m.visibleChannels[i].channel) = oldKey then
            SetVisibleRow(i)
            return
        end if
    end for
    idx = NearestVisibleIndex(oldOriginalIndex)
    if idx < 0 then idx = 0
    SetVisibleRow(idx)
end sub

function WindowEnd() as Integer
    return m.windowStart + (m.windowMinutes * 60)
end function

function FindProgramAtTime(programs as Object, atTime as Integer) as Integer
    if programs = invalid or programs.Count() = 0 then return -1
    selected = -1
    for i = 0 to programs.Count() - 1
        p = programs[i]
        e = EpgProgramEnd(p)
        if p.s <= atTime then
            if e <> invalid then
                if atTime < e then selected = i
            else
                selected = i
            end if
        end if
    end for
    if selected >= 0 then return selected
    for i = 0 to programs.Count() - 1
        if programs[i].s >= atTime then return i
    end for
    return programs.Count() - 1
end function

function VisualEnd(programs as Object, index as Integer) as Integer
    p = programs[index]
    e = EpgProgramEnd(p)
    if e <> invalid then return e
    if index + 1 < programs.Count() then return programs[index + 1].s
    if m.top.epg <> invalid and m.top.epg.windowEnd <> invalid then return m.top.epg.windowEnd
    return p.s + 3600
end function

sub ClearLayer(layer as Object)
    if layer = invalid then return
    count = layer.getChildCount()
    if count > 0 then layer.removeChildrenIndex(count, 0)
end sub

function Ellipsize(text as Dynamic, maxChars as Integer) as String
    if text = invalid then return ""
    s = text
    if s = invalid then return ""
    if maxChars <= 0 then return ""
    if Len(s) <= maxChars then return s
    if maxChars = 1 then return "…"
    return Left(s, maxChars - 1) + "…"
end function

sub RenderGrid()
    if m.gridLayer = invalid then return
    ClearLayer(m.gridLayer)
    ClearLayer(m.timeLayer)
    ClearLayer(m.nowLayer)

    now = NowSeconds()
    m.range.text = EpgTimeRange(m.windowStart, WindowEnd())
    RenderTimeHeader()
    RenderNowLine(now)

    if m.visibleChannels.Count() = 0 then
        m.detailChannel.text = "Sin programación"
        m.detailTitle.text = "No hay canales con programación en esta ventana"
        m.detailTime.text = ""
        m.detailDesc.text = "Desplázate con Left/Right para buscar otra franja temporal."
        m.detailNote.text = ""
        return
    end if

    if m.row >= m.visibleChannels.Count() then m.row = m.visibleChannels.Count() - 1
    if m.row < 0 then m.row = 0
    if m.row < m.rowOffset then m.rowOffset = m.row
    if m.row >= m.rowOffset + m.visibleRows then m.rowOffset = m.row - m.visibleRows + 1
    if m.rowOffset < 0 then m.rowOffset = 0

    for r = 0 to m.visibleRows - 1
        rowIndex = m.rowOffset + r
        if rowIndex >= m.visibleChannels.Count() then exit for
        RenderRow(rowIndex, m.rowTop + r * m.rowH, now)
    end for
    RenderDetail(now)
end sub

sub RenderTimeHeader()
    channelHeader = m.timeLayer.CreateChild("Label")
    channelHeader.translation = [30, 58]
    channelHeader.width = 150
    channelHeader.height = 18
    channelHeader.font = "font:SmallestSystemFont"
    channelHeader.color = "0x6E8588FF"
    channelHeader.text = "CANAL"

    for minute = 0 to m.windowMinutes step 30
        x = m.timeX + Int((minute / m.windowMinutes) * m.timeW)
        label = m.timeLayer.CreateChild("Label")
        label.translation = [x + 5, 58]
        label.width = 100
        label.height = 18
        label.font = "font:SmallestSystemFont"
        label.color = "0x7F9699FF"
        label.text = EpgFormatTime(m.windowStart + minute * 60)
        line = m.timeLayer.CreateChild("Rectangle")
        line.translation = [x, 100]
        line.width = 1
        line.height = m.visibleRows * m.rowH
        line.color = "0x173037FF"
    end for
end sub

sub RenderNowLine(now as Integer)
    if now < m.windowStart or now > WindowEnd() then return
    x = m.timeX + Int(((now - m.windowStart) / 60 / m.windowMinutes) * m.timeW)
    line = m.nowLayer.CreateChild("Rectangle")
    line.translation = [x, 100]
    line.width = 1
    line.height = m.visibleRows * m.rowH
    line.color = "0xB97C6EFF"
    label = m.nowLayer.CreateChild("Label")
    label.translation = [x - 16, 82]
    label.width = 44
    label.height = 16
    label.font = "font:SmallestSystemFont"
    label.color = "0xB97C6EFF"
    label.text = "Ahora"
end sub

sub RenderRow(rowIndex as Integer, y as Integer, now as Integer)
    selectedRow = (rowIndex = m.row)
    bg = m.gridLayer.CreateChild("Rectangle")
    bg.translation = [20, y]
    bg.width = 1240
    bg.height = m.rowH - 2
    if selectedRow then
        bg.color = "0x10252BFF"
    else if rowIndex mod 2 = 0 then
        bg.color = "0x0D1B20FF"
    else
        bg.color = "0x0C181DFF"
    end if

    channelCell = m.gridLayer.CreateChild("Rectangle")
    channelCell.translation = [20, y]
    channelCell.width = 179
    channelCell.height = m.rowH - 2
    if selectedRow then
        channelCell.color = "0x173039FF"
    else
        channelCell.color = "0x0F2026FF"
    end if

    if selectedRow then
        accent = m.gridLayer.CreateChild("Rectangle")
        accent.translation = [20, y]
        accent.width = 2
        accent.height = m.rowH - 2
        accent.color = "0x8BCFC5FF"
    end if

    divider = m.gridLayer.CreateChild("Rectangle")
    divider.translation = [199, y]
    divider.width = 1
    divider.height = m.rowH - 2
    divider.color = "0x183137FF"

    ch = m.visibleChannels[rowIndex].channel
    logo = m.gridLayer.CreateChild("Poster")
    logo.translation = [30, y + 22]
    logo.width = 46
    logo.height = 30
    logo.loadWidth = 46
    logo.loadHeight = 30
    logo.loadDisplayMode = "scaleToFit"
    logo.failedBitmapUri = "pkg:/images/logo_placeholder.png"
    url = CatalogLogoForItem(m.top.catalog, ch)
    if url = "" then url = "pkg:/images/logo_placeholder.png"
    logo.uri = url

    name = m.gridLayer.CreateChild("Label")
    name.translation = [84, y + 15]
    name.width = 106
    name.height = 44
    name.font = "font:SmallSystemFont"
    name.wrap = true
    name.vertAlign = "center"
    if selectedRow then
        name.color = "0xF2FBFAFF"
    else
        name.color = "0xD6E3E2FF"
    end if
    name.text = Ellipsize(ch.name, 24)

    programs = ProgramsForRow(rowIndex)
    for i = 0 to programs.Count() - 1
        p = programs[i]
        ps = p.s
        pe = VisualEnd(programs, i)
        if ps < m.windowStart then ps = m.windowStart
        if pe > WindowEnd() then pe = WindowEnd()
        if pe > m.windowStart and ps < WindowEnd() then
            x = m.timeX + Int(((ps - m.windowStart) / 60 / m.windowMinutes) * m.timeW)
            w = Int(((pe - ps) / 60 / m.windowMinutes) * m.timeW)
            if w < 8 then w = 8
            if x + w > m.timeX + m.timeW then w = m.timeX + m.timeW - x
            if w > 0 then
                block = m.gridLayer.CreateChild("Group")
                block.translation = [x, y + 7]
                rect = block.CreateChild("Rectangle")
                rect.width = w - 3
                rect.height = m.rowH - 14
                progEnd = EpgProgramEnd(p)
                isCurrent = EpgProgramIsCurrent(programs, i, now)
                isSelected = selectedRow and i = m.selectedProgramIndex
                isPast = progEnd <> invalid and progEnd <= now
                if isSelected then
                    rect.color = "0x2A5C66FF"
                else if isCurrent then
                    rect.color = "0x1E4A47FF"
                else if isPast then
                    rect.color = "0x0F1D22FF"
                else
                    rect.color = "0x11252BFF"
                end if

                if isSelected then
                    mark = block.CreateChild("Rectangle")
                    mark.translation = [0, 0]
                    mark.width = 2
                    mark.height = m.rowH - 14
                    mark.color = "0x8BCFC5FF"
                end if

                titleWidth = w - 16
                if titleWidth >= 28 then
                    title = block.CreateChild("Label")
                    title.translation = [8, 8]
                    title.width = titleWidth
                    title.height = 24
                    title.font = "font:SmallSystemFont"
                    title.wrap = false
                    if isSelected then
                        title.color = "0xF5FCFAFF"
                    else if isCurrent then
                        title.color = "0xEEF9F5FF"
                    else if isPast then
                        title.color = "0x9EB1B2FF"
                    else
                        title.color = "0xDCE8E7FF"
                    end if
                    maxChars = Int(titleWidth / 7)
                    if maxChars < 1 then maxChars = 1
                    title.text = Ellipsize(p.t, maxChars)
                end if

                if w >= 106 then
                    timeLabel = block.CreateChild("Label")
                    timeLabel.translation = [8, 33]
                    timeLabel.width = w - 16
                    timeLabel.height = 18
                    timeLabel.font = "font:SmallestSystemFont"
                    timeLabel.wrap = false
                    if isSelected then
                        timeLabel.color = "0xC4E2DCFF"
                    else if isCurrent then
                        timeLabel.color = "0x9FC7C0FF"
                    else if isPast then
                        timeLabel.color = "0x6D8284FF"
                    else
                        timeLabel.color = "0x7F9A9BFF"
                    end if
                    maxTimeChars = Int((w - 16) / 6)
                    if maxTimeChars < 1 then maxTimeChars = 1
                    timeLabel.text = Ellipsize(EpgTimeRange(p.s, progEnd), maxTimeChars)
                end if
            end if
        end if
    end for
end sub

sub RenderDetail(now as Integer)
    m.detailNote.text = ""
    if m.visibleChannels.Count() = 0 then return
    ch = m.visibleChannels[m.row].channel
    m.detailChannel.text = Ellipsize(ch.name, 44)
    programs = ProgramsForRow(m.row)
    if programs.Count() = 0 then
        m.detailTitle.text = "Sin programación"
        m.detailTime.text = ""
        m.detailDesc.text = "Este canal no tiene datos EPG en la ventana actual."
        return
    end if
    if m.selectedProgramIndex < 0 or m.selectedProgramIndex >= programs.Count() then
        m.selectedProgramIndex = FindProgramAtTime(programs, now)
    end if
    p = programs[m.selectedProgramIndex]
    m.detailTitle.text = p.t
    m.detailTime.text = EpgTimeRange(p.s, EpgProgramEnd(p))
    m.detailDesc.text = ""
    if p.DoesExist("c") and p.c <> "" then m.detailDesc.text = p.c
    if p.DoesExist("ep") and p.ep <> "" then
        if m.detailDesc.text <> "" then m.detailDesc.text = m.detailDesc.text + "  ·  "
        m.detailDesc.text = m.detailDesc.text + "Ep. " + p.ep
    end if
    if p.DoesExist("d") and p.d <> "" then
        if m.detailDesc.text <> "" then m.detailDesc.text = m.detailDesc.text + Chr(10)
        m.detailDesc.text = m.detailDesc.text + p.d
    end if
    if m.detailDesc.text = "" then m.detailDesc.text = "Sin descripción disponible."
    if EpgProgramIsCurrent(programs, m.selectedProgramIndex, now) then
        if ch.url <> invalid and ch.url <> "" then
            m.detailNote.text = "OK para sintonizar este canal"
            m.detailNote.color = "0x8FD3C7FF"
        else
            m.detailNote.text = "No se puede sintonizar: URL no disponible"
            m.detailNote.color = "0xC79A8CFF"
        end if
    else
        m.detailNote.text = "Programa futuro: OK solo muestra información"
        m.detailNote.color = "0x8AA2A4FF"
    end if
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if press = false then return false
    if key = "back" then
        m.top.close = true
        return true
    end if
    if key = "up" then
        if m.visibleChannels.Count() > 0 and m.row > 0 then
            SetVisibleRow(m.row - 1)
            m.cursorTime = NowSeconds()
            m.selectedProgramIndex = FindProgramAtTime(ProgramsForRow(m.row), m.cursorTime)
            if m.row < m.rowOffset then m.rowOffset = m.row
            RenderGrid()
        end if
        return true
    else if key = "down" then
        if m.visibleChannels.Count() > 0 and m.row + 1 < m.visibleChannels.Count() then
            SetVisibleRow(m.row + 1)
            m.cursorTime = NowSeconds()
            m.selectedProgramIndex = FindProgramAtTime(ProgramsForRow(m.row), m.cursorTime)
            if m.row >= m.rowOffset + m.visibleRows then m.rowOffset = m.row - m.visibleRows + 1
            RenderGrid()
        end if
        return true
    else if key = "left" or key = "right" then
        dir = 1
        if key = "left" then dir = -1
        MoveProgram(dir)
        return true
    else if key = "play" or key = "OK" then
        HandleOk()
        return true
    end if
    return false
end function

sub HandleOk()
    now = NowSeconds()
    RenderDetail(now)
    if m.visibleChannels.Count() = 0 then return
    ch = m.visibleChannels[m.row].channel
    programs = ProgramsForRow(m.row)
    idx = m.selectedProgramIndex
    if idx < 0 or idx >= programs.Count() then return
    if EpgProgramIsCurrent(programs, idx, now) then
        if ch.url = invalid or ch.url = "" then
            m.detailNote.text = "No se puede sintonizar: URL no disponible"
            return
        end if
        m.top.playRequest = { url: ch.url, name: ch.name, tvgId: ch.tvgId }
        m.detailNote.text = "Sintonizando…"
    else
        m.detailNote.text = "Programa futuro: OK solo muestra información"
    end if
end sub

sub MoveProgram(dir as Integer)
    if m.visibleChannels.Count() = 0 then
        ShiftWindow(dir)
        return
    end if
    programs = ProgramsForRow(m.row)
    if programs.Count() = 0 then
        ShiftWindow(dir)
        return
    end if
    idx = m.selectedProgramIndex
    if idx < 0 or idx >= programs.Count() then idx = FindProgramAtTime(programs, m.cursorTime)
    newIndex = idx + dir
    if newIndex >= 0 and newIndex < programs.Count() then
        m.selectedProgramIndex = newIndex
        m.cursorTime = programs[newIndex].s
    else
        ShiftWindow(dir)
        return
    end if
    RenderGrid()
end sub

sub ShiftWindow(dir as Integer)
    oldKey = m.selectedChannelKey
    oldOrig = m.selectedOriginalIndex
    m.windowStart = ClampWindowStart(m.windowStart + dir * 1800)
    BuildVisibleChannels()
    PreserveSelection(oldKey, oldOrig)
    m.cursorTime = m.windowStart + 60
    m.selectedProgramIndex = FindProgramAtTime(ProgramsForRow(m.row), m.cursorTime)
    RenderGrid()
end sub

function ClampWindowStart(value as Integer) as Integer
    candidate = Align30(value)
    if m.top.epg <> invalid then
        if m.top.epg.windowStart <> invalid and m.top.epg.windowEnd <> invalid then
            if candidate < m.top.epg.windowStart then candidate = m.top.epg.windowStart
            if candidate > m.top.epg.windowEnd - (m.windowMinutes * 60) then
                candidate = m.top.epg.windowEnd - (m.windowMinutes * 60)
            end if
        end if
    end if
    return candidate
end function
