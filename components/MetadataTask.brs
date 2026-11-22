' Versioned catalog/EPG manifest loader. Only compact artifacts are cached;
' the registry is never used for JSON payloads.

sub init()
    m.top.functionName = "fetchMetadata"
end sub

sub fetchMetadata()
    id = m.top.cacheKey
    if id = "" then id = "default"
    base = m.top.baseUrl
    if base = "" then
        SetMetaResult(MetaResult(id, "error", "empty_base"))
        return
    end if

    statePath = MetaStatePath(id)
    state = MetaReadJson(statePath)
    if state = invalid then state = { schema: 1, catalogVersion: "", epgVersion: "", epgFiles: [] }

    manifest = MetaFetchJson(JoinUrl(base, "latest.json"))
    if manifest = invalid then
        catalog = MetaLoadCachedCatalog(id, state)
        epg = MetaLoadCachedEpg(id, state)
        r = MetaResult(id, "cache", "manifest_unavailable")
        r.catalog = catalog
        r.epg = epg
        r.nextCheckAt = NowSeconds() + 300
        SetMetaResult(r)
        return
    end if

    catalogInfo = manifest.catalog
    epgInfo = manifest.epg
    catalogVersion = MetaInfoVersion(catalogInfo, manifest.version)
    epgVersion = MetaInfoVersion(epgInfo, manifest.version)

    catalog = invalid
    catalogUpdated = false
    catalogOk = false
    if catalogVersion <> "" then
        catFile = MetaInfoFile(catalogInfo, "catalog.json")
        catCache = MetaCachePath(id, "catalog", catalogVersion, catFile)
        if state.catalogVersion = catalogVersion and MetaFileExists(catCache) then
            catalog = MetaReadJson(catCache)
        end if
        if MetaValidCatalog(catalog) = false then
            fetched = MetaFetchJson(JoinUrl(base, catFile))
            if MetaValidCatalog(fetched) then
                catalog = fetched
                MetaWriteJson(catCache, fetched)
                catalogUpdated = true
            end if
        end if
        catalogOk = MetaValidCatalog(catalog)
        if catalogOk = false then
            catalog = MetaLoadCachedCatalog(id, state)
            catalogOk = MetaValidCatalog(catalog)
        end if
    end if

    epg = invalid
    epgUpdated = false
    epgOk = false
    epgFiles = []
    if epgVersion <> "" then
        if epgInfo <> invalid and Type(epgInfo) = "roAssociativeArray" and epgInfo.files <> invalid then
            files = epgInfo.files
            merged = invalid
            allOk = true
            for each entry in files
                file = entry.file
                if file = invalid or file = "" then
                    allOk = false
                else
                    cache = MetaCachePath(id, "epg", epgVersion, file)
                    shard = invalid
                    if state.epgVersion = epgVersion and MetaFileExists(cache) then shard = MetaReadJson(cache)
                    if MetaValidEpg(shard) = false then
                        shard = MetaFetchJson(JoinUrl(base, file))
                        if MetaValidEpg(shard) then
                            MetaWriteJson(cache, shard)
                            epgUpdated = true
                        end if
                    end if
                    if MetaValidEpg(shard) then
                        if merged = invalid then
                            merged = { schema: 1, version: epgVersion, channels: {} }
                            if shard.windowStart <> invalid then merged.windowStart = shard.windowStart
                            if shard.windowEnd <> invalid then merged.windowEnd = shard.windowEnd
                        end if
                        for each k in shard.channels.Keys()
                            merged.channels[k] = shard.channels[k]
                        end for
                        epgFiles.Push(file)
                    else
                        allOk = false
                    end if
                end if
            end for
            if MetaValidEpg(merged) then
                epg = merged
                epgOk = allOk
            end if
        else
            file = MetaInfoFile(epgInfo, "epg.json")
            cache = MetaCachePath(id, "epg", epgVersion, file)
            if state.epgVersion = epgVersion and MetaFileExists(cache) then epg = MetaReadJson(cache)
            if MetaValidEpg(epg) = false then
                fetched = MetaFetchJson(JoinUrl(base, file))
                if MetaValidEpg(fetched) then
                    epg = fetched
                    MetaWriteJson(cache, fetched)
                    epgUpdated = true
                end if
            end if
            epgOk = MetaValidEpg(epg)
            if epgOk = false then
                epg = MetaLoadCachedEpg(id, state)
                epgOk = MetaValidEpg(epg)
            end if
            if epgOk then epgFiles = [file]
        end if
    end if

    state.schema = 1
    state.catalogVersion = catalogVersion
    state.epgVersion = epgVersion
    state.epgFiles = epgFiles
    if catalogOk = false and catalogVersion <> "" then state.catalogVersion = ""
    if epgOk = false and epgVersion <> "" then state.epgVersion = ""
    MetaWriteJson(statePath, state)

    status = "ok"
    if catalogOk = false or epgOk = false then status = "partial"
    if catalogOk = false and epgOk = false then status = "error"
    r = MetaResult(id, status, "")
    r.catalog = catalog
    r.epg = epg
    r.manifest = manifest
    r.updatedCatalog = catalogUpdated
    r.updatedEpg = epgUpdated
    r.nextCheckAt = MetaNextCheck(manifest)
    SetMetaResult(r)
end sub

function MetaResult(id as String, status as String, reason as String) as Object
    return {
        id: id
        status: status
        reason: reason
        catalog: invalid
        epg: invalid
        manifest: invalid
        updatedCatalog: false
        updatedEpg: false
        nextCheckAt: 0
    }
end function

sub SetMetaResult(value as Object)
    m.top.result = value
end sub

function MetaStatePath(id as String) as String
    return "cachefs:/md_" + SafeCacheKey(id) + "_state.json"
end function

function MetaCachePath(id as String, kind as String, version as String, file as String) as String
    return "cachefs:/md_" + SafeCacheKey(id) + "_" + kind + "_" + SafeCacheKey(version) + "_" + SafeCacheKey(file) + ".json"
end function

function MetaFileExists(path as String) as Boolean
    fs = CreateObject("roFileSystem")
    return fs.Exists(path)
end function

function MetaReadJson(path as String) as Dynamic
    text = ReadAsciiFile(path)
    if text = "" then return invalid
    value = ParseJson(text)
    if value = invalid then return invalid
    if Type(value) <> "roAssociativeArray" then return invalid
    return value
end function

function MetaWriteJson(path as String, value as Object) as Boolean
    return WriteAsciiFile(path, FormatJson(value))
end function

function MetaFetchText(url as String) as String
    xfer = CreateObject("roUrlTransfer")
    xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.InitClientCertificates()
    xfer.EnableEncodings(true)
    xfer.SetUrl(url)
    return xfer.GetToString()
end function

function MetaFetchJson(url as String) as Dynamic
    text = MetaFetchText(url)
    if text = "" then return invalid
    value = ParseJson(text)
    if value = invalid then return invalid
    if Type(value) <> "roAssociativeArray" then return invalid
    return value
end function

function MetaValidCatalog(value as Dynamic) as Boolean
    if value = invalid then return false
    if Type(value) <> "roAssociativeArray" then return false
    if value.channels = invalid then return false
    if Type(value.channels) <> "roAssociativeArray" then return false
    return true
end function

function MetaValidEpg(value as Dynamic) as Boolean
    if value = invalid then return false
    if Type(value) <> "roAssociativeArray" then return false
    if value.channels = invalid then return false
    if Type(value.channels) <> "roAssociativeArray" then return false
    return true
end function

function MetaInfoVersion(info as Dynamic, fallback as Dynamic) as String
    if info <> invalid then
        if Type(info) = "roString" then return info
        if Type(info) = "roAssociativeArray" then
            if info.version <> invalid and info.version <> "" then return info.version
        end if
    end if
    if fallback <> invalid then return fallback
    return ""
end function

function MetaInfoFile(info as Dynamic, fallback as String) as String
    if info <> invalid and Type(info) = "roAssociativeArray" then
        if info.file <> invalid and info.file <> "" then return info.file
    end if
    return fallback
end function

function MetaNextCheck(manifest as Object) as Integer
    now = NowSeconds()
    if manifest <> invalid then
        if manifest.refreshAfter <> invalid then
            if manifest.refreshAfter > now then return manifest.refreshAfter
        end if
    end if
    return now + 3600
end function

function MetaLoadCachedCatalog(id as String, state as Object) as Dynamic
    if state = invalid then return invalid
    if state.catalogVersion = invalid or state.catalogVersion = "" then return invalid
    ' Try the conventional single-file name; a future state can store the file name.
    path = MetaCachePath(id, "catalog", state.catalogVersion, "catalog.json")
    value = MetaReadJson(path)
    if MetaValidCatalog(value) then return value
    return invalid
end function

function MetaLoadCachedEpg(id as String, state as Object) as Dynamic
    if state = invalid then return invalid
    if state.epgVersion = invalid or state.epgVersion = "" then return invalid
    merged = invalid
    files = state.epgFiles
    if files = invalid then files = ["epg.json"]
    if files.Count() = 0 then return invalid
    for each file in files
        path = MetaCachePath(id, "epg", state.epgVersion, file)
        shard = MetaReadJson(path)
        if MetaValidEpg(shard) then
            if merged = invalid then
                merged = { schema: 1, version: state.epgVersion, channels: {} }
                if shard.windowStart <> invalid then merged.windowStart = shard.windowStart
                if shard.windowEnd <> invalid then merged.windowEnd = shard.windowEnd
            end if
            for each k in shard.channels.Keys()
                merged.channels[k] = shard.channels[k]
            end for
        end if
    end for
    if MetaValidEpg(merged) then return merged
    return invalid
end function
