' M3U parsing helpers shared by PlaylistTask and MainScene.
' Keeps the original PlaylistTask parsing semantics and adds optional metadata.

function GetAttr(line as String, key as String) as String
    token = key + "=" + Chr(34)
    p = Instr(1, line, token)
    if p = 0 then return ""
    s = p + Len(token)
    e = Instr(s, line, Chr(34))
    if e = 0 then return ""
    return Mid(line, s, e - s)
end function

function NormPath(g as String) as String
    g = g.Trim()
    g = g.Replace("\", "/")
    g = g.Replace(" / ", "/")
    while Left(g, 1) = "/"
        g = Mid(g, 2)
    end while
    while Right(g, 1) = "/"
        g = Left(g, Len(g) - 1)
    end while
    return g
end function

function ParseM3U(text as String) as Object
    out = []
    if text = "" then return out
    name = ""
    group = ""
    subs = ""
    tvgId = ""
    tvgName = ""
    logoUrl = ""
    have = false
    for each raw in text.Split(Chr(10))
        l = raw.Trim()
        if l <> "" then
            if Left(l, 7) = "#EXTINF" then
                parts = l.Split(",")
                name = parts[parts.Count() - 1].Trim()
                group = NormPath(GetAttr(l, "group-title"))
                subs = GetAttr(l, "subtitles")
                tvgId = GetAttr(l, "tvg-id")
                tvgName = GetAttr(l, "tvg-name")
                logoUrl = GetAttr(l, "tvg-logo")
                have = true
            else if Left(l, 1) <> "#" then
                if have = false or name = "" then name = l
                out.Push({
                    kind: "ch"
                    name: name
                    group: group
                    url: l
                    subs: subs
                    tvgId: tvgId
                    tvgName: tvgName
                    logoUrl: logoUrl
                })
                name = ""
                group = ""
                subs = ""
                tvgId = ""
                tvgName = ""
                logoUrl = ""
                have = false
            end if
        end if
    end for
    return out
end function
