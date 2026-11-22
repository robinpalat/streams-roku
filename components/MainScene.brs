sub init()
    m.video = m.top.findNode("video")
    m.title = m.top.findNode("title")
    m.panel = m.top.findNode("panel")
    m.list = m.top.findNode("list")
    m.tabsLbl = m.top.findNode("tabs")
    m.status = m.top.findNode("status")
    m.hint = m.top.findNode("hint")
    m.task = m.top.findNode("task")
    m.metaTask = m.top.findNode("metaTask")
    m.guide = m.top.findNode("guide")
    m.epgCard = m.top.findNode("epgCard")
    m.epgLogo = m.top.findNode("epgLogo")
    m.epgName = m.top.findNode("epgName")
    m.epgGroup = m.top.findNode("epgGroup")
    m.epgNowTitle = m.top.findNode("epgNowTitle")
    m.epgNowTime = m.top.findNode("epgNowTime")
    m.epgDesc = m.top.findNode("epgDesc")
    m.epgBarBg = m.top.findNode("epgBarBg")
    m.epgBar = m.top.findNode("epgBar")
    m.epgNextTitle = m.top.findNode("epgNextTitle")
    m.epgNextTime = m.top.findNode("epgNextTime")
    m.epgStatus = m.top.findNode("epgStatus")
    m.titleTimer = m.top.findNode("titleTimer")
    m.retryTimer = m.top.findNode("retryTimer")
    m.seekTimer = m.top.findNode("seekTimer")
    m.playlistTimer = m.top.findNode("playlistTimer")
    m.epgTimer = m.top.findNode("epgTimer")
    m.metaTimer = m.top.findNode("metaTimer")
    m.seekPos = invalid
    m.temp = invalid
    m.current = invalid
    m.retries = 0
    m.catalog = invalid
    m.epg = invalid
    m.playlistInFlight = false
    m.metaInFlight = false
    m.nextPlaylistCheck = 0
    m.nextMetaCheck = 0
    m.lastManualRefresh = 0
    m.pendingPlaylist = invalid
    m.playlistStats = invalid
    m.dlgSourceId = ""

    m.hint.text = "OK elegir   Play favorito   < > pestaña   FF buscar   Replay actualizar   Atrás cerrar   (Guía EPG en la lista)"

    m.tab = 0
    m.filter = ""
    m.view = []
    m.channels = []
    m.playingUrl = ""
    m.autoplay = false
    m.path = ""
    m.subIdx = -1
    m.playingSource = ""

    m.sources = LoadSources()
    m.favs = LoadFavs()
    m.activeId = RegRead("active", m.sources[0].id)
    if FindSource(m.activeId) = invalid then m.activeId = m.sources[0].id

    m.task.observeField("result", "onPlaylist")
    m.metaTask.observeField("result", "onMetadata")
    m.video.observeField("state", "onVideoState")
    m.list.observeField("itemSelected", "onItemSelected")
    m.list.observeField("itemFocused", "onListFocused")
    m.titleTimer.observeField("fire", "onTitleTimer")
    m.retryTimer.observeField("fire", "onRetryTimer")
    m.seekTimer.observeField("fire", "onSeekTimer")
    m.playlistTimer.observeField("fire", "onPlaylistTimer")
    m.epgTimer.observeField("fire", "onEpgTimer")
    m.metaTimer.observeField("fire", "onMetaTimer")
    m.guide.observeField("close", "onGuideClose")
    m.guide.observeField("playRequest", "onGuidePlayRequest")

    m.top.setFocus(true)
    LoadPlaylist(true)
    StartMetadata()
end sub

' ---------------- recibido desde la web (ECP) ----------------
sub onLaunchArgs()
    a = m.top.launchArgs
    if a = invalid then return
    if a.DoesExist("contentId") = false then return
    url = a.contentId
    if Left(LCase(url), 4) <> "http" then return
    name = "Enviado desde la web"
    if a.DoesExist("name") then
        if a.name <> "" then name = a.name
    end if
    m.autoplay = false
    PlayChannel({ kind: "ch", name: name, group: "", url: url })
    ClosePanel()
end sub

' ---------------- fuentes / playlist ----------------
function SourceLabel() as String
    sc = FindSource(m.activeId)
    if sc = invalid then return ""
    return sc.name
end function

function FindSource(id as String) as Dynamic
    for each s in m.sources
        if s.id = id then return s
    end for
    return invalid
end function

function FindChannelByUrl(url as String) as Dynamic
    for each c in m.channels
        if c.url = url then return c
    end for
    return invalid
end function

function FindChannelByTvgId(tvgId as String) as Dynamic
    found = invalid
    count = 0
    for each c in m.channels
        if c.tvgId <> invalid and c.tvgId = tvgId then
            found = c
            count = count + 1
        end if
    end for
    if count = 1 then return found
    return invalid
end function

sub LoadPlaylist(autoplay as Boolean)
    src = FindSource(m.activeId)
    if src = invalid then return
    m.autoplay = autoplay
    m.status.text = "Cargando…"
    m.playlistInFlight = true
    m.task.control = "STOP"
    m.task.mode = "load"
    m.task.cacheKey = src.id
    m.task.url = src.url
    m.task.control = "RUN"
end sub

sub StartPlaylistCheck(force as Boolean)
    if m.playlistInFlight then return
    src = FindSource(m.activeId)
    if src = invalid then return
    now = NowSeconds()
    if force then
        if (now - m.lastManualRefresh) < 60 then
            m.status.text = "Lista comprobada hace menos de un minuto"
            return
        end if
        m.lastManualRefresh = now
    end if
    if m.channels.Count() = 0 then
        LoadPlaylist(false)
        return
    end if
    m.playlistInFlight = true
    m.task.control = "STOP"
    m.task.mode = "check"
    m.task.force = force
    m.task.cacheKey = src.id
    m.task.url = src.url
    m.task.control = "RUN"
end sub

sub onPlaylist()
    r = m.task.result
    m.playlistInFlight = false
    if r = invalid then return
    if r.id <> m.activeId then return
    if r.nextCheckAt <> invalid then
        if r.nextCheckAt > 0 then m.nextPlaylistCheck = r.nextCheckAt
    end if

    if r.status = "ok" or r.status = "cache" then
        m.channels = r.items
        if r.status = "ok" then
            m.status.text = m.channels.Count().ToStr() + " canales"
        else
            m.status.text = "Copia guardada (" + m.channels.Count().ToStr() + " canales)"
        end if
        RenderList()
        if m.autoplay then
            m.autoplay = false
            ResumeLast()
        end if
        if r.needsCheck = true then
            m.nextPlaylistCheck = 0
            StartPlaylistCheck(false)
        end if
    else if r.status = "updated" then
        ApplyPlaylistUpdate(r.items, r.stats)
        if r.nextCheckAt > 0 then m.nextPlaylistCheck = r.nextCheckAt
    else if r.status = "notmodified" then
        m.status.text = "Lista al día"
    else if r.status = "quarantine" then
        m.status.text = "Actualización en cuarentena; se conserva la lista anterior"
    else if r.status = "error" then
        if m.channels.Count() = 0 then
            m.status.text = "Error al cargar la lista"
        else
            m.status.text = "Sin conexión: se conserva la lista anterior"
        end if
    end if
end sub

sub ApplyPlaylistUpdate(items as Object, stats as Dynamic)
    if items = invalid then return
    m.playlistStats = stats
    oldFocused = invalid
    oldIndex = 0
    if m.panel.visible and m.tab = 0 then
        oldIndex = m.list.itemFocused
        if oldIndex < 0 then oldIndex = 0
        if oldIndex < m.view.Count() then oldFocused = m.view[oldIndex]
        if oldFocused <> invalid and oldFocused.kind <> "ch" then oldFocused = invalid
    end if

    if m.top.dialog <> invalid then
        m.pendingPlaylist = { items: items, old: oldFocused, index: oldIndex }
        m.status.text = "Lista nueva preparada; se aplicará al cerrar el diálogo"
        return
    end if

    m.channels = items
    if m.guide.visible then m.guide.channels = items
    m.status.text = "Lista actualizada (" + items.Count().ToStr() + " canales)"
    if m.panel.visible and m.tab = 0 and stats <> invalid and stats.reordered = true then
        m.status.text = "Lista actualizada; el nuevo orden se aplicará al reabrir"
        StartMetadata()
        return
    end if
    if m.panel.visible and m.tab = 0 then
        RenderList()
        RestoreFocus(oldFocused, oldIndex)
    end if
    StartMetadata()
end sub

sub ApplyPendingPlaylist()
    if m.pendingPlaylist = invalid then return
    pending = m.pendingPlaylist
    m.pendingPlaylist = invalid
    m.channels = pending.items
    m.status.text = "Lista actualizada (" + pending.items.Count().ToStr() + " canales)"
    if m.panel.visible and m.tab = 0 then
        RenderList()
        RestoreFocus(pending.old, pending.index)
    end if
end sub

sub RestoreFocus(oldItem as Dynamic, oldIndex as Integer)
    if oldItem = invalid then return
    idx = M3UFindIndexForItem(m.view, oldItem)
    if idx < 0 then
        idx = oldIndex
        if idx >= m.view.Count() then idx = m.view.Count() - 1
        if idx < 0 then idx = 0
    end if
    if m.view.Count() > 0 then m.list.jumpToItem = idx
end sub

sub onPlaylistTimer()
    if m.playlistInFlight then return
    if m.channels.Count() = 0 then return
    now = NowSeconds()
    if m.nextPlaylistCheck > 0 and now < m.nextPlaylistCheck then return
    StartPlaylistCheck(false)
end sub

sub ResumeLast()
    url = RegRead("last_" + m.activeId, "")
    found = invalid
    if url <> "" then
        for each c in m.channels
            if c.url = url then
                found = c
                exit for
            end if
        end for
        if found = invalid then
            for each c in m.favs
                if c.url = url then
                    found = c
                    exit for
                end if
            end for
        end if
    end if
    if found <> invalid then
        PlayChannel(found)
    else if m.playingUrl = "" then
        OpenPanel()
    end if
end sub

' ---------------- lista ----------------
function IsFav(url as String) as Boolean
    for each f in m.favs
        if f.url = url then return true
    end for
    return false
end function

sub RenderList()
    m.view = []
    if m.tab = 2 then
        m.view.Push({ kind: "add" })
        for each s in m.sources
            m.view.Push({ kind: "src", id: s.id, name: s.name, url: s.url })
        end for
    else if m.tab = 0 and m.filter = "" then
        m.view.Push({ kind: "guide", name: "Guía EPG" })
        BuildFolderView()
    else
        src = m.channels
        if m.tab = 1 then src = m.favs
        n = 0
        for each c in src
            if m.filter = "" or Instr(1, LCase(c.name + " " + c.group), m.filter) > 0 then
                m.view.Push(c)
                n = n + 1
                if n >= 2000 then exit for
            end if
        end for
    end if

    root = CreateObject("roSGNode", "ContentNode")
    for each it in m.view
        node = root.CreateChild("ContentNode")
        if it.kind = "add" then
            node.title = "+ Añadir fuente (URL de una lista M3U)"
        else if it.kind = "guide" then
            node.title = "Guía EPG"
        else if it.kind = "up" then
            node.title = ".. (subir)"
        else if it.kind = "dir" then
            node.title = "+ " + it.name + "   (" + it.count.ToStr() + ")"
        else if it.kind = "src" then
            mark = "   "
            if it.id = m.activeId then mark = ">  "
            node.title = mark + it.name
        else
            p = " "
            if it.url = m.playingUrl then p = ">"
            f = " "
            if IsFav(it.url) then f = "*"
            node.title = p + " " + f + " " + it.name
            if m.tab = 1 then
                if it.src <> invalid then node.title = node.title + "   [" + it.src + "]"
            end if
            node.HDPOSTERURL = ResolveLogo(it)
        end if
    end for
    m.list.content = root
    if m.panel.visible and m.tab = 0 then
        idx = m.list.itemFocused
        if idx >= 0 and idx < m.view.Count() then
            UpdateEpgCard(m.view[idx])
        else
            HideEpgCard()
        end if
    else
        HideEpgCard()
    end if

    names = ["Playlist", "Favoritos (" + m.favs.Count().ToStr() + ")", "Fuentes (" + m.sources.Count().ToStr() + ")"]
    t = ""
    for i = 0 to 2
        if i = m.tab then
            t = t + "[ " + names[i] + " ]   "
        else
            t = t + "  " + names[i] + "     "
        end if
    end for
    if m.filter <> "" then t = t + "   búsqueda: " + m.filter
    if m.tab = 0 and m.filter = "" and m.path <> "" then t = t + "   /" + m.path
    m.tabsLbl.text = t
end sub

sub SetTab(i as Integer)
    m.tab = (i + 3) mod 3
    RenderList()
end sub

sub OpenGuide()
    if m.channels.Count() = 0 then return
    m.guide.channels = m.channels
    m.guide.catalog = m.catalog
    m.guide.epg = m.epg
    m.guide.playRequest = invalid
    m.guide.startChannelId = ""
    if m.current <> invalid and m.current.tvgId <> invalid then m.guide.startChannelId = m.current.tvgId
    if m.guide.startChannelId = "" then m.guide.startChannelId = m.playingUrl
    m.guide.close = false
    m.panel.visible = false
    m.guide.visible = true
    m.guide.setFocus(true)
end sub

sub onGuideClose()
    if m.guide.close = false then return
    m.guide.visible = false
    m.guide.close = false
    OpenPanel()
end sub

sub onGuidePlayRequest()
    req = m.guide.playRequest
    if req = invalid then return
    m.guide.playRequest = invalid
    if req.url = invalid or req.url = "" then return
    ch = FindChannelByUrl(req.url)
    if ch = invalid and req.tvgId <> invalid and req.tvgId <> "" then
        ch = FindChannelByTvgId(req.tvgId)
    end if
    if ch = invalid then
        ShowTitle("Canal no disponible")
        return
    end if
    m.guide.visible = false
    m.guide.close = false
    PlayChannel(ch)
    m.top.setFocus(true)
end sub

sub OpenPanel()
    if m.tab = 0 and m.filter = "" and m.current <> invalid and m.playingSource = m.activeId then
        g = m.current.group
        if g <> invalid then m.path = g
    end if
    m.panel.visible = true
    RenderList()
    idx = 0
    for i = 0 to m.view.Count() - 1
        if m.view[i].kind = "ch" then
            if m.view[i].url = m.playingUrl then idx = i
        end if
    end for
    m.list.jumpToItem = idx
    m.list.setFocus(true)
end sub

sub ClosePanel()
    m.panel.visible = false
    m.top.setFocus(true)
end sub

sub onItemSelected()
    idx = m.list.itemSelected
    if idx < 0 or idx >= m.view.Count() then return
    it = m.view[idx]
    if it.kind = "add" then
        AskText("URL de la lista M3U", "https://", "addsource")
    else if it.kind = "guide" then
        OpenGuide()
    else if it.kind = "src" then
        m.activeId = it.id
        RegWrite("active", it.id)
        m.tab = 0
        m.filter = ""
        m.path = ""
        m.channels = []
        m.catalog = invalid
        m.epg = invalid
        m.pendingPlaylist = invalid
        m.nextPlaylistCheck = 0
        m.nextMetaCheck = 0
        RenderList()
        LoadPlaylist(true)
        StartMetadata()
    else if it.kind = "up" then
        GoUp()
    else if it.kind = "dir" then
        m.path = it.path
        RenderList()
    else
        PlayChannel(it)
        ClosePanel()
    end if
end sub

sub ToggleFavOrDelete()
    idx = m.list.itemFocused
    if idx < 0 or idx >= m.view.Count() then return
    it = m.view[idx]
    if it.kind = "ch" then
        found = -1
        for i = 0 to m.favs.Count() - 1
            if m.favs[i].url = it.url then found = i
        end for
        if found >= 0 then
            m.favs.Delete(found)
        else
            m.favs.Push({
                kind: "ch"
                name: it.name
                group: it.group
                url: it.url
                subs: it.subs
                src: SourceLabel()
                tvgId: it.tvgId
                tvgName: it.tvgName
                logoUrl: it.logoUrl
                epgId: it.epgId
            })
        end if
        SaveFavs(m.favs)
        RenderList()
        m.list.jumpToItem = idx
    else if it.kind = "src" then
        if m.sources.Count() < 2 then return
        keep = []
        for each s in m.sources
            if s.id <> it.id then keep.Push(s)
        end for
        m.sources = keep
        SaveSources(m.sources)
        if it.id = m.activeId then
            m.activeId = m.sources[0].id
            RegWrite("active", m.activeId)
            m.channels = []
            m.catalog = invalid
            m.epg = invalid
            m.nextPlaylistCheck = 0
            m.nextMetaCheck = 0
            LoadPlaylist(true)
            StartMetadata()
        end if
        RenderList()
    end if
end sub

' ---------------- reproducción ----------------
sub PlayChannel(c as Object)
    m.retryTimer.control = "stop"
    m.retries = 0
    ' canal no favorito: se incluye temporalmente en la lista de zapping
    keepTemp = false
    if m.temp <> invalid then
        if m.temp.url = c.url then keepTemp = true
    end if
    if keepTemp = false then
        if IsFav(c.url) = false then
            m.temp = {
                kind: "ch"
                name: c.name
                group: c.group
                url: c.url
                subs: c.subs
                after: m.playingUrl
                tvgId: c.tvgId
                tvgName: c.tvgName
                logoUrl: c.logoUrl
                epgId: c.epgId
            }
        end if
    end if
    m.current = c
    m.playingSource = m.activeId
    m.playingUrl = c.url
    RegWrite("last_" + m.activeId, c.url)
    StartPlayback(c)
    ShowTitle(c.name)
end sub

sub StartPlayback(c as Object)
    content = CreateObject("roSGNode", "ContentNode")
    content.url = c.url
    content.title = c.name
    fmt = GuessFormat(c.url)
    if fmt <> "" then content.streamFormat = fmt

    ' subtítulos externos (.srt) que acompañan al video
    m.subIdx = -1
    if c.subs <> invalid then
        if c.subs <> "" then
            tracks = []
            for each part in c.subs.Split(" ")
                kv = part.Split("|")
                if kv.Count() = 2 then
                    tracks.Push({ Language: kv[0], TrackName: kv[1], Description: LangName(kv[0]) })
                end if
            end for
            if tracks.Count() > 0 then
                content.SubtitleTracks = tracks
                content.SubtitleConfig = { TrackName: tracks[0].TrackName }
                m.subIdx = 0
            end if
        end if
    end if

    m.video.content = content
    m.video.control = "play"
end sub

sub CycleSubtitles()
    tracks = m.video.availableSubtitleTracks
    if tracks = invalid then
        ShowTitle("Sin subtítulos disponibles")
        return
    end if
    n = tracks.Count()
    if n = 0 then
        ShowTitle("Sin subtítulos disponibles")
        return
    end if
    m.subIdx = m.subIdx + 1
    if m.subIdx >= n then m.subIdx = -1
    if m.subIdx = -1 then
        m.video.globalCaptionMode = "Off"
        ShowTitle("Subtítulos: desactivados")
    else
        t = tracks[m.subIdx]
        label = "pista " + (m.subIdx + 1).ToStr()
        if t.Description <> invalid then
            label = t.Description
        else if t.Language <> invalid then
            label = t.Language
        end if
        m.video.globalCaptionMode = "On"
        m.video.subtitleTrack = t.TrackName
        ShowTitle("Subtítulos: " + label)
    end if
end sub

sub GoUp()
    p = m.path
    idx = 0
    for i = 1 to Len(p)
        if Mid(p, i, 1) = "/" then idx = i
    end for
    if idx = 0 then
        m.path = ""
    else
        m.path = Left(p, idx - 1)
    end if
    RenderList()
end sub

sub BuildFolderView()
    p = m.path
    prefix = ""
    if p <> "" then prefix = p + "/"
    if p <> "" then m.view.Push({ kind: "up" })

    dirs = []
    counts = {}
    items = []
    for each c in m.channels
        g = c.group
        if g = invalid then g = ""
        if g = p then
            items.Push(c)
        else if g <> "" then
            if Left(g, Len(prefix)) = prefix then
                rest = Mid(g, Len(prefix) + 1)
                segs = rest.Split("/")
                seg = segs[0]
                key = LCase(seg)
                if counts.DoesExist(key) = false then
                    counts[key] = 0
                    dirs.Push(seg)
                end if
                counts[key] = counts[key] + 1
            end if
        end if
    end for

    for each d in dirs
        m.view.Push({ kind: "dir", path: prefix + d, name: d, count: counts[LCase(d)] })
    end for
    n = 0
    for each c in items
        m.view.Push(c)
        n = n + 1
        if n >= 2000 then exit for
    end for
end sub

function ZapList() as Object
    useTemp = false
    if m.temp <> invalid then
        if IsFav(m.temp.url) = false then useTemp = true
    end if
    after = ""
    if useTemp then after = m.temp.after
    out = []
    placed = false
    for each f in m.favs
        out.Push(f)
        if useTemp then
            if f.url = after then
                out.Push(m.temp)
                placed = true
            end if
        end if
    end for
    if useTemp and placed = false then out.Push(m.temp)
    return out
end function

sub Zap(dir as Integer)
    list = ZapList()
    n = list.Count()
    if n = 0 then
        ShowTitle("Sin favoritos: en la lista pulsa Play sobre un canal")
        return
    end if
    idx = -1
    for i = 0 to n - 1
        if list[i].url = m.playingUrl then idx = i
    end for
    if idx = -1 then
        if dir > 0 then
            idx = 0
        else
            idx = n - 1
        end if
    else
        idx = (idx + dir + n) mod n
    end if
    PlayChannel(list[idx])
end sub

sub ScheduleRetry()
    if m.current = invalid then return
    if m.retries >= 5 then
        ShowTitle("Canal no disponible: " + m.current.name)
        return
    end if
    waits = [2, 4, 8, 16, 30]
    d = waits[m.retries]
    m.retries = m.retries + 1
    ShowTitle("Reconectando " + m.retries.ToStr() + "/5… " + m.current.name)
    m.retryTimer.control = "stop"
    m.retryTimer.duration = d
    m.retryTimer.control = "start"
end sub

sub SeekBy(delta as Integer)
    dur = m.video.duration
    base = m.video.position
    if m.seekPos <> invalid then base = m.seekPos
    target = base + delta
    if target < 0 then target = 0
    if dur > 10 then
        if target > dur - 5 then target = dur - 5
    end if
    m.seekPos = target
    m.video.seek = target
    m.seekTimer.control = "stop"
    m.seekTimer.control = "start"
    ShowTitle(FormatTime(target) + " / " + FormatTime(dur))
end sub

sub onSeekTimer()
    m.seekPos = invalid
end sub

sub onRetryTimer()
    if m.current <> invalid then StartPlayback(m.current)
end sub

sub ShowTitle(text as String)
    m.title.text = text
    m.title.visible = true
    m.titleTimer.control = "stop"
    m.titleTimer.control = "start"
end sub

sub onTitleTimer()
    m.title.visible = false
end sub

sub onVideoState()
    st = m.video.state
    if st = "playing" then
        if m.retries > 0 then
            if m.current <> invalid then ShowTitle(m.current.name)
        end if
        m.retries = 0
    else if st = "error" then
        ScheduleRetry()
    else if st = "finished" then
        ' en directo no debería terminar; si es un vídeo con duración, no reintentar
        if m.video.duration <= 0 then ScheduleRetry()
    end if
end sub

' ---------------- logos / metadata / EPG ----------------
function ResolveLogo(item as Object) as String
    logo = CatalogLogoForItem(m.catalog, item)
    if logo <> "" then return logo
    return "pkg:/images/logo_placeholder.png"
end function

function GetSourceMeta(src as Dynamic) as String
    if src = invalid then return ""
    if src.meta <> invalid then return src.meta
    return ""
end function

function MetaBase(src as Dynamic) as String
    if src = invalid then return ""
    if src.meta <> invalid and src.meta <> "" then return src.meta
    perSource = RegRead("meta_" + src.id, "")
    if perSource <> "" then return perSource
    if IsConfiguredMetaSource(src.url) then return DefaultMetaBase()
    return RegRead("meta_base", "")
end function

sub StartMetadata()
    if m.metaInFlight then return
    src = FindSource(m.activeId)
    base = MetaBase(src)
    if base = "" then return
    m.metaInFlight = true
    m.metaTask.control = "STOP"
    m.metaTask.baseUrl = base
    m.metaTask.cacheKey = m.activeId
    m.metaTask.control = "RUN"
end sub

sub onMetadata()
    r = m.metaTask.result
    m.metaInFlight = false
    if r = invalid then return
    if r.id <> m.activeId then return
    if r.nextCheckAt <> invalid and r.nextCheckAt > 0 then m.nextMetaCheck = r.nextCheckAt
    hadCatalog = (m.catalog <> invalid)
    if r.catalog <> invalid then m.catalog = r.catalog
    if r.epg <> invalid then m.epg = r.epg
    if m.guide.visible then
        if r.catalog <> invalid then m.guide.catalog = r.catalog
        if r.epg <> invalid then m.guide.epg = r.epg
    end if
    if (r.updatedCatalog = true or hadCatalog = false) and m.panel.visible and m.tab = 0 and m.top.dialog = invalid then
        idx = m.list.itemFocused
        focused = invalid
        if idx >= 0 and idx < m.view.Count() then focused = m.view[idx]
        RenderList()
        RestoreFocus(focused, idx)
    else if m.panel.visible and m.tab = 0 then
        idx = m.list.itemFocused
        if idx >= 0 and idx < m.view.Count() then UpdateEpgCard(m.view[idx])
    end if
end sub

sub onMetaTimer()
    if m.metaInFlight then return
    if MetaBase(FindSource(m.activeId)) = "" then return
    if m.nextMetaCheck > 0 and NowSeconds() < m.nextMetaCheck then return
    StartMetadata()
end sub

sub onListFocused()
    if m.panel.visible = false or m.tab <> 0 then
        HideEpgCard()
        return
    end if
    idx = m.list.itemFocused
    if idx < 0 or idx >= m.view.Count() then
        HideEpgCard()
        return
    end if
    UpdateEpgCard(m.view[idx])
end sub

sub onEpgTimer()
    if m.panel.visible = false or m.tab <> 0 then return
    idx = m.list.itemFocused
    if idx >= 0 and idx < m.view.Count() then UpdateEpgCard(m.view[idx])
end sub

sub HideEpgCard()
    if m.epgCard <> invalid then m.epgCard.visible = false
end sub

sub UpdateEpgCard(item as Dynamic)
    if m.epgCard = invalid then return
    if item = invalid or item.kind <> "ch" then
        HideEpgCard()
        return
    end if
    m.epgCard.visible = true
    m.epgLogo.uri = ResolveLogo(item)
    m.epgName.text = item.name
    m.epgGroup.text = item.group
    m.epgNowTitle.text = ""
    m.epgNowTime.text = ""
    m.epgDesc.text = ""
    m.epgNextTitle.text = ""
    m.epgNextTime.text = ""
    m.epgStatus.text = ""
    m.epgBar.width = 0

    epgId = CatalogEpgIdForItem(m.catalog, item)
    if epgId = "" or m.epg = invalid then
        m.epgStatus.text = "Sin información de programación"
        return
    end if
    sel = EpgSelectNowNext(m.epg, epgId, NowSeconds())
    if sel.hasData = false or (sel.hasNow = false and sel.hasNext = false) then
        m.epgStatus.text = "Sin información de programación"
        return
    end if
    if sel.hasNow then
        m.epgNowTitle.text = "Ahora: " + sel.nowTitle
        m.epgNowTime.text = EpgTimeRange(sel.nowStart, sel.nowStop)
        if sel.nowDesc <> "" then m.epgDesc.text = sel.nowDesc
        if sel.progress >= 0 then
            m.epgBar.width = Int(350 * sel.progress)
        else
            m.epgBar.width = 0
        end if
    else
        m.epgStatus.text = "Sin programa en este momento"
    end if
    if sel.hasNext then
        m.epgNextTitle.text = "Después: " + sel.nextTitle
        m.epgNextTime.text = EpgTimeRange(sel.nextStart, sel.nextStop)
    else
        m.epgNextTitle.text = "Sin siguiente"
    end if
end sub

' ---------------- teclado en pantalla ----------------
sub AskText(title as String, initial as String, mode as String)
    m.dlgMode = mode
    dlg = CreateObject("roSGNode", "StandardKeyboardDialog")
    dlg.title = title
    dlg.text = initial
    dlg.buttons = ["Aceptar", "Cancelar"]
    dlg.observeFieldScoped("buttonSelected", "onDlgButton")
    m.dlg = dlg
    m.top.dialog = dlg
end sub

sub onDlgButton()
    idx = m.dlg.buttonSelected
    txt = m.dlg.text.Trim()
    m.dlg.close = true
    if m.panel.visible then
        m.list.setFocus(true)
    else
        m.top.setFocus(true)
    end if
    ApplyPendingPlaylist()
    if idx <> 0 then return

    if m.dlgMode = "search" then
        m.filter = LCase(txt)
        RenderList()
    else if m.dlgMode = "sourcemeta" then
        src = FindSource(m.dlgSourceId)
        if src <> invalid then
            if txt = "" then
                if src.DoesExist("meta") then src.Delete("meta")
            else if Left(LCase(txt), 4) = "http" then
                src.meta = txt
            else
                m.status.text = "La URL de metadatos debe empezar por http"
                return
            end if
            SaveSources(m.sources)
            m.catalog = invalid
            m.epg = invalid
            m.nextMetaCheck = 0
            HideEpgCard()
            if m.activeId = src.id then StartMetadata()
            m.status.text = "Metadatos actualizados"
        end if
    else if m.dlgMode = "addsource" then
        if Left(LCase(txt), 4) = "http" then
            id = "s" + CreateObject("roDateTime").AsSeconds().ToStr()
            m.sources.Push({ id: id, name: DeriveName(txt), url: txt })
            SaveSources(m.sources)
            m.activeId = id
            RegWrite("active", id)
            m.tab = 0
            m.filter = ""
            m.channels = []
            m.catalog = invalid
            m.epg = invalid
            m.nextPlaylistCheck = 0
            m.nextMetaCheck = 0
            RenderList()
            LoadPlaylist(true)
            StartMetadata()
        else
            m.status.text = "La URL debe empezar por http"
        end if
    end if
end sub

' ---------------- mando ----------------
function onKeyEvent(key as String, press as Boolean) as Boolean
    if press = false then return false
    if m.guide <> invalid and m.guide.visible then return false

    if m.panel.visible then
        if key = "back" then
            if m.tab = 0 and m.filter = "" and m.path <> "" then
                GoUp()
            else
                ClosePanel()
            end if
            return true
        else if key = "left" then
            SetTab(m.tab - 1)
            return true
        else if key = "right" then
            SetTab(m.tab + 1)
            return true
        else if key = "play" then
            ToggleFavOrDelete()
            return true
        else if key = "options" then
            ToggleFavOrDelete()
            return true
        else if key = "replay" then
            StartPlaylistCheck(true)
            return true
        else if key = "fastforward" then
            if m.tab = 2 then
                idx = m.list.itemFocused
                if idx >= 0 and idx < m.view.Count() then
                    it = m.view[idx]
                    if it.kind = "src" then
                        m.dlgSourceId = it.id
                        AskText("URL base de metadatos (vacío = quitar)", GetSourceMeta(it), "sourcemeta")
                        return true
                    end if
                end if
            end if
            AskText("Buscar (vacío = todos)", m.filter, "search")
            return true
        end if
        return false
    end if

    ' izquierda/derecha: cambiar de canal (favoritos + último canal); arriba/abajo: avanzar/retroceder en videos con duración
    vod = false
    if m.video.duration > 0 then vod = true

    if key = "right" then
        Zap(1)
        return true
    else if key = "left" then
        Zap(-1)
        return true
    else if key = "up" then
        if vod then
            SeekBy(10)
            return true
        end if
    else if key = "down" then
        if vod then
            SeekBy(-10)
            return true
        end if
    else if key = "fastforward" then
        if vod then
            SeekBy(30)
            return true
        end if
    else if key = "rewind" then
        if vod then
            SeekBy(-30)
            return true
        end if
    else if key = "replay" then
        CycleSubtitles()
        return true
    end if

    if key = "back" then
        OpenPanel()
        return true
    else if key = "play" then
        if m.video.state = "playing" then
            m.video.control = "pause"
        else
            m.video.control = "resume"
        end if
        if vod then ShowTitle(FormatTime(m.video.position) + " / " + FormatTime(m.video.duration))
        return true
    end if
    return false
end function
