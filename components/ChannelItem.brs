sub init()
    m.bg = m.top.findNode("bg")
    m.logo = m.top.findNode("logo")
    m.name = m.top.findNode("name")
    m.logo.observeField("loadStatus", "onLogoStatus")
    m.logo.uri = "pkg:/images/logo_placeholder.png"
end sub

sub onLogoStatus()
    if m.logo.loadStatus <> "ready" then return
    w = m.logo.bitmapWidth
    h = m.logo.bitmapHeight
    if w <= 0 or h <= 0 then return
    fit = FitLogoInBox(w, h, 58, 36)
    if fit.ok = false then return
    m.logo.width = fit.width
    m.logo.height = fit.height
    m.logo.translation = [8 + fit.x, 4 + fit.y]
end sub

sub onSizeChanged()
    w = m.top.width
    h = m.top.height
    if w <= 0 or h <= 0 then return
    m.bg.width = w
    m.bg.height = h
    m.name.width = w - 84
end sub

sub onContentChanged()
    content = m.top.itemContent
    if content = invalid then return
    if content.HDPOSTERURL <> invalid and content.HDPOSTERURL <> "" then
        m.logo.uri = content.HDPOSTERURL
    else
        m.logo.uri = "pkg:/images/logo_placeholder.png"
    end if
    if content.title <> invalid then m.name.text = content.title
end sub

sub onFocusChanged()
    focused = (m.top.itemHasFocus = true and m.top.listHasFocus = true)
    if focused then
        m.bg.color = "0x2A2F3AFF"
        m.name.color = "0xFFFFFFFF"
    else
        m.bg.color = "0x00000000"
        m.name.color = "0xDDDDDDFF"
    end if
end sub
