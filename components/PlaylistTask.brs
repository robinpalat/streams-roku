' Cache-first M3U loader and conditional revalidator.
' All network/file work stays in the Task thread; playback is never touched.

sub init()
    m.top.functionName = "fetchPlaylist"
    m.counter = 0
end sub

sub fetchPlaylist()
    id = m.top.cacheKey
    if id = "" then id = "default"
    if m.top.mode = "check" then
        CheckPlaylist(id)
    else
        LoadCachedOrFetch(id)
    end if
end sub

' ------------------------- result helpers -------------------------

sub SetResult(value as Object)
    m.counter = m.counter + 1
    value.n = m.counter
    m.top.result = value
end sub

function BaseResult(id as String, mode as String, status as String) as Object
    return {
        id: id
        mode: mode
        status: status
        items: invalid
        changed: false
        version: ""
        hash: ""
        count: 0
        nextCheckAt: 0
        needsCheck: false
        ambiguous: false
        recovered: false
        reason: ""
        stats: invalid
        anomaly: invalid
    }
end function

' ------------------------- file helpers -------------------------

function PKey(id as String, suffix as String) as String
    return "cachefs:/pl_" + SafeCacheKey(id) + suffix
end function

function ReadText(path as String) as String
    if path = "" then return ""
    return ReadAsciiFile(path)
end function

function ReadJson(path as String) as Dynamic
    text = ReadAsciiFile(path)
    if text = "" then return invalid
    value = ParseJson(text)
    if value = invalid then return invalid
    if Type(value) <> "roAssociativeArray" then return invalid
    return value
end function

function WriteJson(path as String, value as Object) as Boolean
    return WriteAsciiFile(path, FormatJson(value))
end function

function FileExists(path as String) as Boolean
    fs = CreateObject("roFileSystem")
    return fs.Exists(path)
end function

sub RemoveFile(path as String)
    if FileExists(path) then
        fs = CreateObject("roFileSystem")
        fs.Delete(path)
    end if
end sub

function SlotPath(id as String, slot as String) as String
    return PKey(id, "_" + slot + ".m3u")
end function

function SlotMetaPath(id as String, slot as String) as String
    return PKey(id, "_" + slot + ".json")
end function

function MetaPath(id as String) as String
    return PKey(id, "_meta.json")
end function

function CandidatePath(id as String) as String
    return PKey(id, "_candidate.m3u")
end function

function MetaValid(meta as Dynamic) as Boolean
    if meta = invalid then return false
    if meta.schema <> 1 then return false
    if meta.activeSlot <> "a" and meta.activeSlot <> "b" then return false
    if meta.hash = invalid or meta.hash = "" then return false
    if meta.version = invalid then return false
    return true
end function

function ReadMeta(id as String) as Dynamic
    meta = ReadJson(MetaPath(id))
    if MetaValid(meta) = false then return invalid
    return meta
end function

' ------------------------- load paths -------------------------

sub LoadCachedOrFetch(id as String)
    meta = ReadMeta(id)
    if meta <> invalid then
        r = LoadSlot(id, meta.activeSlot)
        if r.ok and r.hash = meta.hash then
            result = BaseResult(id, "load", "cache")
            result.items = r.items
            result.count = r.items.Count()
            result.version = meta.version
            result.hash = meta.hash
            result.nextCheckAt = meta.nextCheckAt
            if result.nextCheckAt = invalid then result.nextCheckAt = 0
            result.needsCheck = (NowSeconds() >= result.nextCheckAt)
            SetResult(result)
            return
        end if
    end if

    rec = RecoverSlots(id, meta)
    if rec.ok then
        result = BaseResult(id, "load", "cache")
        result.items = rec.items
        result.count = rec.items.Count()
        result.version = rec.meta.version
        result.hash = rec.meta.hash
        result.nextCheckAt = 0
        result.needsCheck = true
        result.ambiguous = rec.ambiguous
        result.recovered = true
        SetResult(result)
        return
    end if

    FullFetch(id, true)
end sub

function LoadSlot(id as String, slot as String) as Object
    out = { ok: false, items: invalid, hash: "", text: "", meta: invalid }
    path = SlotPath(id, slot)
    text = ReadText(path)
    if text = "" then return out
    v = M3UValidateText(text)
    if v.ok = false then return out
    side = ReadJson(SlotMetaPath(id, slot))
    h = M3UHash(text, v.items)
    if side <> invalid then
        if side.hash <> invalid and side.hash <> "" and side.hash <> h then return out
        out.meta = side
    end if
    out.ok = true
    out.text = text
    out.items = v.items
    out.hash = h
    return out
end function

function RecoverSlots(id as String, central as Dynamic) as Object
    out = { ok: false, items: invalid, meta: invalid, ambiguous: false, recovered: true }
    candidates = []
    for each slot in ["a", "b"]
        side = ReadJson(SlotMetaPath(id, slot))
        if side <> invalid then
            if side.confirmed = true then
                r = LoadSlot(id, slot)
                if r.ok then
                    candidates.Push({
                        slot: slot
                        items: r.items
                        hash: r.hash
                        version: side.version
                        confirmedAt: side.confirmedAt
                        side: side
                        text: r.text
                    })
                end if
            end if
        end if
    end for
    if candidates.Count() = 0 then return out

    centralVersion = ""
    if central <> invalid then
        if central.version <> invalid then centralVersion = central.version
    end if
    choice = M3UChooseRecoveryCandidate(candidates, centralVersion)
    if choice.ok = false then return out
    best = candidates[choice.index]
    ambiguous = choice.ambiguous

    meta = {
        schema: 1
        sourceId: id
        version: best.version
        hash: best.hash
        etag: ""
        lastModified: ""
        channelCount: best.items.Count()
        recentCounts: []
        activeSlot: best.slot
        lastGoodAt: 0
        lastCheckAt: 0
        failures: 0
        nextCheckAt: 0
        pendingHash: ""
        pendingAt: 0
        pendingCount: 0
    }
    if central <> invalid then
        if central.recentCounts <> invalid then meta.recentCounts = central.recentCounts
        if central.lastGoodAt <> invalid then meta.lastGoodAt = central.lastGoodAt
        if central.lastCheckAt <> invalid then meta.lastCheckAt = central.lastCheckAt
    end if
    WriteJson(MetaPath(id), meta)
    out.ok = true
    out.items = best.items
    out.meta = meta
    out.ambiguous = ambiguous
    return out
end function

' ------------------------- check path -------------------------

sub CheckPlaylist(id as String)
    meta = ReadMeta(id)
    if meta = invalid then
        FullFetch(id, false)
        return
    end if
    active = LoadSlot(id, meta.activeSlot)
    if active.ok = false then
        rec = RecoverSlots(id, meta)
        if rec.ok then
            meta = rec.meta
            active = LoadSlot(id, meta.activeSlot)
        end if
    end if
    if active.ok = false then
        FullFetch(id, false)
        return
    end if

    f = FetchHttp(m.top.url, meta.etag, meta.lastModified)
    now = NowSeconds()
    if f.ok = false then
        Fail(id, meta, now, f.reason)
        return
    end if

    if f.code = 304 then
        meta.lastCheckAt = now
        meta.failures = 0
        meta.nextCheckAt = now + NextCheckInterval(meta)
        WriteJson(MetaPath(id), meta)
        r = BaseResult(id, "check", "notmodified")
        r.version = meta.version
        r.hash = meta.hash
        r.count = meta.channelCount
        r.nextCheckAt = meta.nextCheckAt
        SetResult(r)
        return
    end if

    if f.code <> 200 then
        Fail(id, meta, now, "http_" + f.code.ToStr())
        return
    end if

    v = M3UValidateText(f.body)
    if v.ok = false then
        Fail(id, meta, now, "invalid_" + v.reason)
        return
    end if

    h = M3UHash(f.body, v.items)
    if h = meta.hash then
        if f.etag <> "" then meta.etag = f.etag
        if f.lastModified <> "" then meta.lastModified = f.lastModified
        meta.lastCheckAt = now
        meta.failures = 0
        meta.pendingHash = ""
        meta.pendingAt = 0
        meta.nextCheckAt = now + NextCheckInterval(meta)
        WriteJson(MetaPath(id), meta)
        r = BaseResult(id, "check", "notmodified")
        r.version = meta.version
        r.hash = meta.hash
        r.count = meta.channelCount
        r.nextCheckAt = meta.nextCheckAt
        SetResult(r)
        return
    end if

    stats = M3UComputeDiff(active.items, v.items)
    recent = meta.recentCounts
    if recent = invalid then recent = []
    anomaly = M3UDetectAnomaly(stats, recent)

    if anomaly.anomaly then
        samePending = (meta.pendingHash <> invalid and meta.pendingHash = h)
        pendingAt = meta.pendingAt
        if pendingAt = invalid then pendingAt = 0
        if samePending and pendingAt <= 0 then
            pendingAt = now
            meta.pendingAt = now
        end if
        if samePending and M3UCanConfirm(meta.pendingHash, h, pendingAt, now, 600) then
            ' Second identical read after the confirmation window: legitimate.
        else
            if samePending = false then
                meta.pendingHash = h
                meta.pendingAt = now
                meta.pendingCount = v.count
                WriteAsciiFile(CandidatePath(id), f.body)
            end if
            meta.lastCheckAt = now
            meta.failures = 0
            meta.nextCheckAt = now + 600
            WriteJson(MetaPath(id), meta)
            r = BaseResult(id, "check", "quarantine")
            r.version = meta.version
            r.hash = meta.hash
            r.count = v.count
            r.nextCheckAt = meta.nextCheckAt
            r.stats = stats
            r.anomaly = anomaly
            SetResult(r)
            return
        end if
    end if

    committed = CommitVersion(id, meta, f, v, stats, now)
    if committed = false then
        Fail(id, meta, now, "commit_failed")
        return
    end if

    updated = ReadMeta(id)
    if updated = invalid then updated = meta
    r = BaseResult(id, "check", "updated")
    r.items = v.items
    r.changed = true
    r.version = updated.version
    r.hash = updated.hash
    r.count = v.count
    r.nextCheckAt = updated.nextCheckAt
    r.stats = stats
    r.anomaly = anomaly
    SetResult(r)
end sub

sub FullFetch(id as String, initial as Boolean)
    f = FetchHttp(m.top.url, "", "")
    now = NowSeconds()
    if f.ok = false or f.code <> 200 then
        r = BaseResult(id, "load", "error")
        r.reason = f.reason
        r.nextCheckAt = now + 300
        SetResult(r)
        return
    end if
    v = M3UValidateText(f.body)
    if v.ok = false then
        r = BaseResult(id, "load", "error")
        r.reason = "invalid_" + v.reason
        r.nextCheckAt = now + 300
        SetResult(r)
        return
    end if
    stats = M3UComputeDiff([], v.items)
    meta = {
        schema: 1
        sourceId: id
        version: ""
        hash: ""
        etag: ""
        lastModified: ""
        channelCount: 0
        recentCounts: []
        activeSlot: "a"
        lastGoodAt: 0
        lastCheckAt: 0
        failures: 0
        nextCheckAt: 0
        pendingHash: ""
        pendingAt: 0
        pendingCount: 0
    }
    if CommitVersion(id, meta, f, v, stats, now) = false then
        r = BaseResult(id, "load", "error")
        r.reason = "commit_failed"
        r.nextCheckAt = now + 300
        SetResult(r)
        return
    end if
    saved = ReadMeta(id)
    if saved = invalid then saved = meta
    r = BaseResult(id, "load", "ok")
    r.items = v.items
    r.changed = initial
    r.version = saved.version
    r.hash = saved.hash
    r.count = v.count
    r.nextCheckAt = saved.nextCheckAt
    r.stats = stats
    SetResult(r)
end sub

' ------------------------- commit / failure -------------------------

function CommitVersion(id as String, meta as Object, f as Object, v as Object, stats as Object, now as Integer) as Boolean
    active = "a"
    if meta <> invalid and (meta.activeSlot = "a" or meta.activeSlot = "b") then active = meta.activeSlot
    slot = "b"
    if active = "b" then slot = "a"
    path = SlotPath(id, slot)
    if WriteAsciiFile(path, f.body) = false then return false

    checkText = ReadAsciiFile(path)
    check = M3UValidateText(checkText)
    if check.ok = false then return false
    h = M3UHash(checkText, check.items)
    if h <> M3UHash(f.body, v.items) then return false

    version = now.ToStr() + "-" + h
    side = {
        schema: 1
        sourceId: id
        slot: slot
        version: version
        hash: h
        channelCount: check.items.Count()
        validated: true
        confirmed: false
        confirmedAt: now
    }
    if WriteJson(SlotMetaPath(id, slot), side) = false then return false

    recent = meta.recentCounts
    if recent = invalid then recent = []
    recent.Push(check.items.Count())
    while recent.Count() > 3
        recent.Delete(0)
    end while

    newMeta = {
        schema: 1
        sourceId: id
        version: version
        hash: h
        etag: f.etag
        lastModified: f.lastModified
        channelCount: check.items.Count()
        recentCounts: recent
        activeSlot: slot
        lastGoodAt: now
        lastCheckAt: now
        failures: 0
        nextCheckAt: now
        pendingHash: ""
        pendingAt: 0
        pendingCount: 0
    }
    newMeta.nextCheckAt = now + NextCheckInterval(newMeta)
    if WriteJson(MetaPath(id), newMeta) = false then return false

    side.confirmed = true
    WriteJson(SlotMetaPath(id, slot), side)
    RemoveFile(CandidatePath(id))
    return true
end function

sub Fail(id as String, meta as Object, now as Integer, reason as String)
    failures = 0
    if meta <> invalid and meta.failures <> invalid then failures = meta.failures
    failures = failures + 1
    nextCheck = now + M3UBackoffSeconds(failures)
    if meta <> invalid then
        meta.failures = failures
        meta.lastCheckAt = now
        meta.nextCheckAt = nextCheck
        WriteJson(MetaPath(id), meta)
    end if
    r = BaseResult(id, "check", "error")
    r.reason = reason
    r.nextCheckAt = nextCheck
    SetResult(r)
end sub

function NextCheckInterval(meta as Object) as Integer
    if meta = invalid then return 3600
    etag = meta.etag
    last = meta.lastModified
    if (etag = invalid or etag = "") and (last = invalid or last = "") then return 21600
    return 3600
end function

' ------------------------- HTTP -------------------------

function HeaderValue(headers as Dynamic, name as String) as String
    if headers = invalid then return ""
    if Type(headers) <> "roAssociativeArray" then return ""
    for each k in headers.Keys()
        if LCase(k) = LCase(name) then
            v = headers[k]
            if v = invalid then return ""
            return v
        end if
    end for
    return ""
end function

function FetchHttp(url as String, etag as String, lastModified as String) as Object
    out = { ok: false, code: 0, body: "", headers: invalid, etag: "", lastModified: "", reason: "" }
    if url = "" then
        out.reason = "empty_url"
        return out
    end if

    xfer = CreateObject("roUrlTransfer")
    xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.InitClientCertificates()
    xfer.EnableEncodings(true)
    xfer.SetUrl(url)
    if etag <> invalid and etag <> "" then xfer.AddHeader("If-None-Match", etag)
    if lastModified <> invalid and lastModified <> "" then xfer.AddHeader("If-Modified-Since", lastModified)

    port = CreateObject("roMessagePort")
    xfer.SetMessagePort(port)
    if xfer.AsyncGetToString() = false then
        out.reason = "async_start_failed"
        return out
    end if
    msg = Wait(30000, port)
    if msg = invalid then
        xfer.AsyncCancel()
        out.reason = "timeout"
        return out
    end if
    if Type(msg) <> "roUrlEvent" then
        out.reason = "unexpected_event"
        return out
    end if

    code = msg.GetResponseCode()
    out.code = code
    if code <= 0 then
        out.reason = msg.GetFailureReason()
        if out.reason = "" then out.reason = "network_error"
        return out
    end if
    out.ok = true
    out.body = msg.GetString()
    headers = msg.GetResponseHeaders()
    if headers = invalid then headers = {}
    out.headers = headers
    out.etag = HeaderValue(headers, "etag")
    out.lastModified = HeaderValue(headers, "last-modified")
    return out
end function
