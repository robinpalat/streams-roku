' EPG window helpers. The device only sees the compact JSON generated locally.

function EpgFindChannel(epg as Dynamic, channelId as String) as Dynamic
    if epg = invalid or channelId = "" then return invalid
    channels = epg.channels
    if channels = invalid then return invalid
    if channels.DoesExist(channelId) then return channels[channelId]
    return invalid
end function

function EpgProgramEnd(p as Object) as Dynamic
    if p.DoesExist("e") = false then return invalid
    if p.e = invalid then return invalid
    if p.e <= 0 then return invalid
    return p.e
end function

function EpgClampProgress(value as Float) as Float
    if value < 0 then return 0
    if value > 1 then return 1
    return value
end function

function EpgSelectNowNext(epg as Dynamic, channelId as String, now as Integer) as Object
    out = {
        hasData: false
        channelId: channelId
        hasNow: false
        hasNext: false
        nowTitle: ""
        nowStart: 0
        nowStop: 0
        nowDesc: ""
        nowCategory: ""
        nowEpisode: ""
        nowImage: ""
        nextTitle: ""
        nextStart: 0
        nextStop: 0
        nextDesc: ""
        progress: -1.0
        unknownDuration: false
        programCount: 0
        endKnown: false
    }
    ch = EpgFindChannel(epg, channelId)
    if ch = invalid then return out
    programs = ch.programs
    if programs = invalid or programs.Count() = 0 then
        out.hasData = true
        out.programCount = 0
        return out
    end if
    out.hasData = true
    out.programCount = programs.Count()
    out.endKnown = ch.endKnown

    current = -1
    for i = 0 to programs.Count() - 1
        p = programs[i]
        s = p.s
        e = EpgProgramEnd(p)
        nextStart = invalid
        if i + 1 < programs.Count() then nextStart = programs[i + 1].s
        if s <= now then
            if e <> invalid then
                if now < e then current = i
            else if nextStart <> invalid then
                if now < nextStart then current = i
            else
                current = i
            end if
        end if
    end for

    if current >= 0 then
        p = programs[current]
        out.hasNow = true
        out.nowTitle = p.t
        out.nowStart = p.s
        out.nowStop = EpgProgramEnd(p)
        out.unknownDuration = (out.nowStop = invalid)
        if p.DoesExist("d") then out.nowDesc = p.d
        if p.DoesExist("c") then out.nowCategory = p.c
        if p.DoesExist("ep") then out.nowEpisode = p.ep
        if p.DoesExist("i") then out.nowImage = p.i
        if out.nowStop <> invalid and out.nowStop > out.nowStart then
            out.progress = EpgClampProgress((now - out.nowStart) / (out.nowStop - out.nowStart))
        end if
        if current + 1 < programs.Count() then
            n = programs[current + 1]
            out.hasNext = true
            out.nextTitle = n.t
            out.nextStart = n.s
            out.nextStop = EpgProgramEnd(n)
            if n.DoesExist("d") then out.nextDesc = n.d
        end if
    else
        for i = 0 to programs.Count() - 1
            p = programs[i]
            if p.s >= now then
                out.hasNext = true
                out.nextTitle = p.t
                out.nextStart = p.s
                out.nextStop = EpgProgramEnd(p)
                if p.DoesExist("d") then out.nextDesc = p.d
                exit for
            end if
        end for
    end if
    return out
end function

function EpgFormatTime(epoch as Dynamic) as String
    if epoch = invalid then return "--:--"
    if epoch <= 0 then return "--:--"
    dt = CreateObject("roDateTime")
    dt.FromSeconds(epoch)
    dt.ToLocalTime()
    return Pad2(dt.GetHours()) + ":" + Pad2(dt.GetMinutes())
end function

function EpgTimeRange(startEpoch as Dynamic, stopEpoch as Dynamic) as String
    if stopEpoch = invalid or stopEpoch <= 0 then
        return EpgFormatTime(startEpoch) + " · Duración desconocida"
    end if
    return EpgFormatTime(startEpoch) + "–" + EpgFormatTime(stopEpoch)
end function

function EpgProgramIsCurrent(programs as Object, index as Integer, now as Integer) as Boolean
    if programs = invalid or index < 0 or index >= programs.Count() then return false
    p = programs[index]
    if p.s > now then return false
    e = EpgProgramEnd(p)
    if e <> invalid then return now < e
    if index + 1 < programs.Count() then return now < programs[index + 1].s
    return true
end function

function EpgProgramsOverlap(programs as Object, winStart as Integer, winEnd as Integer) as Boolean
    if programs = invalid or programs.Count() = 0 then return false
    for i = 0 to programs.Count() - 1
        p = programs[i]
        if p.DoesExist("t") and p.t <> "" then
            s = p.s
            e = EpgProgramEnd(p)
            if e = invalid and i + 1 < programs.Count() then e = programs[i + 1].s
            if e = invalid then e = winEnd
            if s < winEnd and e > winStart then return true
        end if
    end for
    return false
end function
