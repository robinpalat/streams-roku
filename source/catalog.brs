' Optional local metadata catalog helpers. All lookups tolerate missing data.

function CatalogFind(catalog as Dynamic, tvgId as String) as Dynamic
    if catalog = invalid or tvgId = "" then return invalid
    channels = catalog.channels
    if channels = invalid then return invalid
    if channels.DoesExist(tvgId) then return channels[tvgId]
    return invalid
end function

function CatalogChannelId(item as Object) as String
    if item = invalid then return ""
    if item.kind <> "ch" then return ""
    if item.epgId <> invalid and item.epgId <> "" then return item.epgId
    if item.tvgId <> invalid and item.tvgId <> "" then return item.tvgId
    return ""
end function

function CatalogLogoForItem(catalog as Dynamic, item as Object) as String
    if item = invalid then return ""
    if item.logoUrl <> invalid and item.logoUrl <> "" then return item.logoUrl
    if item.tvgId = invalid or item.tvgId = "" then return ""
    ch = CatalogFind(catalog, item.tvgId)
    if ch = invalid then return ""
    logo = ch.logo
    if logo = invalid or logo = "" then return ""
    if Left(LCase(logo), 4) = "http" then return logo
    base = catalog.logoBase
    if base <> invalid and base <> "" then return JoinUrl(base, logo)
    return logo
end function

function CatalogEpgIdForItem(catalog as Dynamic, item as Object) as String
    id = CatalogChannelId(item)
    if id <> "" then return id
    if item = invalid then return ""
    if item.tvgId = invalid or item.tvgId = "" then return ""
    ch = CatalogFind(catalog, item.tvgId)
    if ch <> invalid and ch.epgId <> invalid and ch.epgId <> "" then return ch.epgId
    return item.tvgId
end function
