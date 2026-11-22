function RegRead(key as String, default = "" as String) as String
    sec = CreateObject("roRegistrySection", "streams")
    if sec.Exists(key) then return sec.Read(key)
    return default
end function

sub RegWrite(key as String, value as String)
    sec = CreateObject("roRegistrySection", "streams")
    sec.Write(key, value)
    sec.Flush()
end sub

function DefaultSources() as Object
    return [
        { id: "d", name: "robinpalat/streams", url: "https://raw.githubusercontent.com/robinpalat/streams/refs/heads/main/streams.m3u" }
        { id: "d2", name: "Bulder (m3u.cl)", url: "https://m3u.cl/fav/Bulder.m3u" }
        { id: "d3", name: "Mi PC (192.168.1.7)", url: "http://192.168.1.7:8000/playlist.m3u" }
    ]
end function

function LoadSources() as Object
    arr = invalid
    json = RegRead("sources", "")
    if json <> "" then
        parsed = ParseJson(json)
        if parsed <> invalid then
            if Type(parsed) = "roArray" then
                if parsed.Count() > 0 then arr = parsed
            end if
        end if
    end if
    if arr = invalid then arr = DefaultSources()

    ' una sola vez: añade las fuentes por defecto que falten (sin duplicar por URL)
    if RegRead("seeded_v2", "") <> "1" then
        for each d in DefaultSources()
            have = false
            for each s in arr
                if LCase(s.url) = LCase(d.url) then have = true
            end for
            if have = false then arr.Push(d)
        end for
        SaveSources(arr)
        RegWrite("seeded_v2", "1")
    end if

    ' Migrate existing sources to the generated automatic metadata base.
    changed = false
    for each s in arr
        if IsConfiguredMetaSource(s.url) then
            if s.meta = invalid or s.meta = "" then
                s.meta = DefaultMetaBase()
                changed = true
            else if IsLegacyLocalMeta(s.meta) and Left(LCase(DefaultMetaBase()), 8) = "https://" then
                ' Production moved to GitHub Pages; replace the old LAN URL.
                s.meta = DefaultMetaBase()
                changed = true
            end if
        end if
    end for
    if changed then SaveSources(arr)
    return arr
end function

function IsLegacyLocalMeta(url as String) as Boolean
    l = LCase(url)
    if Instr(1, l, "http://localhost") = 1 then return true
    if Instr(1, l, "http://127.") = 1 then return true
    if Instr(1, l, "http://192.168.") = 1 then return true
    if Instr(1, l, "http://10.") = 1 then return true
    if Instr(1, l, "http://172.16.") = 1 then return true
    if Instr(1, l, "http://172.17.") = 1 then return true
    if Instr(1, l, "http://172.18.") = 1 then return true
    if Instr(1, l, "http://172.19.") = 1 then return true
    if Instr(1, l, "http://172.2") = 1 then return true
    if Instr(1, l, "http://172.30.") = 1 then return true
    if Instr(1, l, "http://172.31.") = 1 then return true
    return false
end function

function IsConfiguredMetaSource(url as String) as Boolean
    base = DefaultMetaBase()
    match = DefaultMetaSourceMatch()
    if base = "" or match = "" then return false
    return Instr(1, LCase(url), LCase(match)) > 0
end function

sub SaveSources(arr as Object)
    RegWrite("sources", FormatJson(arr))
end sub

function LoadFavs() as Object
    json = RegRead("favs", "")
    if json <> "" then
        arr = ParseJson(json)
        if arr <> invalid and Type(arr) = "roArray" then return arr
    end if
    return []
end function

sub SaveFavs(arr as Object)
    RegWrite("favs", FormatJson(arr))
end sub

function GuessFormat(url as String) as String
    l = LCase(url)
    if Instr(1, l, ".m3u8") > 0 then return "hls"
    if Instr(1, l, ".mkv") > 0 then return "mkv"
    if Instr(1, l, ".mp4") > 0 then return "mp4"
    if Instr(1, l, ".m4v") > 0 then return "mp4"
    if Instr(1, l, ".mov") > 0 then return "mp4"
    if Instr(1, l, ".mp3") > 0 then return "mp3"
    if Instr(1, l, ".m4a") > 0 then return "aac"
    if Instr(1, l, ".aac") > 0 then return "aac"
    if Instr(1, l, ".flac") > 0 then return "flac"
    if Instr(1, l, ".ts") > 0 then return "ts"
    return ""
end function

function DeriveName(url as String) as String
    parts = url.Split("/")
    if parts.Count() < 3 then return url
    host = parts[2]
    last = parts[parts.Count() - 1]
    if last <> "" and last <> host then return host + "/" + last
    return host
end function

function Pad2(n as Integer) as String
    if n < 10 then return "0" + n.ToStr()
    return n.ToStr()
end function

function FormatTime(t as Dynamic) as String
    total = Int(t)
    h = total \ 3600
    mn = (total mod 3600) \ 60
    sc = total mod 60
    if h > 0 then return h.ToStr() + ":" + Pad2(mn) + ":" + Pad2(sc)
    return mn.ToStr() + ":" + Pad2(sc)
end function

function LangName(code as String) as String
    c = LCase(code)
    if c = "spa" then return "Español"
    if c = "eng" then return "Inglés"
    if c = "fre" then return "Francés"
    if c = "ger" then return "Alemán"
    if c = "ita" then return "Italiano"
    if c = "por" then return "Portugués"
    if c = "cat" then return "Catalán"
    if c = "und" then return "Subtítulos"
    return UCase(code)
end function

function NowSeconds() as Integer
    return CreateObject("roDateTime").AsSeconds()
end function

function SafeCacheKey(value as String) as String
    k = value
    for each ch in ["/", Chr(92), ":", "?", "&", "=", " ", Chr(9)]
        k = k.Replace(ch, "_")
    end for
    if k = "" then k = "default"
    return k
end function

function JoinUrl(base as String, rel as String) as String
    b = base.Trim()
    r = rel.Trim()
    while Right(b, 1) = "/"
        b = Left(b, Len(b) - 1)
    end while
    while Left(r, 1) = "/"
        r = Mid(r, 2)
    end while
    return b + "/" + r
end function
