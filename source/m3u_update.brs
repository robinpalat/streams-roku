' Pure M3U validation, hashing, diff and anomaly helpers.
' No Roku UI / playback dependencies. Included in PlaylistTask and MainScene.

function M3UNormalizeText(text as String) as String
    t = text.Replace(Chr(13) + Chr(10), Chr(10))
    t = t.Replace(Chr(13), Chr(10))
    out = ""
    for each raw in t.Split(Chr(10))
        l = raw.Trim()
        if Len(l) > 0 then
            if Asc(Mid(l, 1, 1)) = 65279 then
                l = Mid(l, 2)
            else if Len(l) >= 3 then
                if Asc(Mid(l, 1, 1)) = 239 and Asc(Mid(l, 2, 1)) = 187 and Asc(Mid(l, 3, 1)) = 191 then
                    l = Mid(l, 4)
                end if
            end if
            if l <> "" then
                if out <> "" then out = out + Chr(10)
                out = out + l
            end if
        end if
    end for
    return out
end function

function M3UHashText(normalized as String, count as Integer) as String
    ' Two small modular accumulators plus length/count. Not cryptographic;
    ' intended only for change detection in a resource-limited client.
    h1 = 7
    h2 = 11
    for i = 1 to Len(normalized)
        c = Asc(Mid(normalized, i, 1))
        h1 = (h1 * 31 + c) mod 65521
        h2 = (h2 * 131 + c) mod 65521
    end for
    return "h" + h1.ToStr() + "_" + h2.ToStr() + "_" + Len(normalized).ToStr() + "_" + count.ToStr()
end function

function M3UHash(text as String, items as Object) as String
    return M3UHashText(M3UNormalizeText(text), items.Count())
end function

function M3UNormalizeName(value as String) as String
    n = LCase(value.Trim())
    for each suffix in [" (1080p)", " (720p)", " (576p)", " (480p)", " (360p)", " (4k)", " fhd", " hd", " sd"]
        n = n.Replace(suffix, "")
    end for
    n = n.Replace("&", "and")
    n = n.Replace("+", "plus")
    n = n.Replace("_", " ")
    n = n.Replace("-", " ")
    while Instr(1, n, "  ") > 0
        n = n.Replace("  ", " ")
    end while
    return n.Trim()
end function

function M3UUrlLooksValid(url as String) as Boolean
    u = url.Trim()
    if u = "" then return false
    p = Instr(1, u, "://")
    if p > 1 then
        rest = Mid(u, p + 3)
        if rest = "" then return false
        slash = Instr(1, rest, "/")
        if slash > 0 then rest = Left(rest, slash - 1)
        if rest.Trim() = "" then return false
        return true
    end if
    ' Non-hierarchical but schemed URLs are allowed; the player decides.
    c = Instr(1, u, ":")
    return c > 1
end function

function M3UValidateText(text as String) as Object
    result = {
        ok: false
        reason: ""
        items: []
        count: 0
        validUrls: 0
        invalidUrls: 0
        truncated: false
        html: false
    }
    if text = "" then
        result.reason = "empty"
        return result
    end if

    upper = UCase(text)
    if Instr(1, upper, "<!DOCTYPE") > 0 or Instr(1, upper, "<HTML") > 0 then
        result.html = true
        result.reason = "html"
        return result
    end if

    firstLine = ""
    lastLine = ""
    for each raw in text.Split(Chr(10))
        l = raw.Trim()
        if l <> "" then
            if firstLine = "" then firstLine = l
            lastLine = l
        end if
    end for
    p = Instr(1, UCase(firstLine), "#EXTM3U")
    if p = 0 or p > 4 then
        result.reason = "missing_extm3u"
        return result
    end if
    if Left(UCase(lastLine), 7) = "#EXTINF" then
        result.truncated = true
        result.reason = "truncated"
        return result
    end if

    items = ParseM3U(text)
    result.items = items
    result.count = items.Count()
    if result.count = 0 then
        result.reason = "no_entries"
        return result
    end if

    for each it in items
        if M3UUrlLooksValid(it.url) then
            result.validUrls = result.validUrls + 1
        else
            result.invalidUrls = result.invalidUrls + 1
        end if
    end for
    if result.validUrls = 0 then
        result.reason = "no_valid_urls"
        return result
    end if

    result.ok = true
    result.reason = "ok"
    return result
end function

function M3UJoinArray(arr as Object) as String
    out = ""
    for each v in arr
        if out <> "" then out = out + Chr(10)
        out = out + v
    end for
    return out
end function

function M3UDuplicateUrlCount(items as Object) as Integer
    counts = {}
    for each it in items
        u = it.url
        if u <> "" then
            if counts.DoesExist(u) then
                counts[u] = counts[u] + 1
            else
                counts[u] = 1
            end if
        end if
    end for
    dup = 0
    for each k in counts.Keys()
        if counts[k] > 1 then dup = dup + counts[k]
    end for
    return dup
end function

function M3UUniqueMap(items as Object, field as String) as Object
    uniq = {}
    for each it in items
        v = it[field]
        if v <> invalid and v <> "" then uniq[v] = 1
    end for
    return uniq
end function

function M3UUniqueCount(items as Object, field as String) as Integer
    return M3UUniqueMap(items, field).Count()
end function

function M3UCommonCount(oldMap as Object, newMap as Object) as Integer
    n = 0
    for each k in oldMap.Keys()
        if newMap.DoesExist(k) then n = n + 1
    end for
    return n
end function

function M3UComputeDiff(oldItems as Object, newItems as Object) as Object
    oldByUrl = {}
    newByUrl = {}
    for each it in oldItems
        if it.url <> "" then oldByUrl[it.url] = it
    end for
    for each it in newItems
        if it.url <> "" then newByUrl[it.url] = it
    end for

    stats = {
        oldCount: oldItems.Count()
        newCount: newItems.Count()
        added: 0
        removed: 0
        retainedUrls: 0
        renamed: 0
        groupChanged: 0
        urlChanged: 0
        tvgIdChanged: 0
        logoChanged: 0
        tvgNameChanged: 0
        reordered: false
        addedRate: 0.0
        removedRate: 0.0
        urlRetentionRate: 0.0
        tvgIdVariationRate: 0.0
        tvgIdVariationCount: 0
        groupRetentionRate: 0.0
        groupRetentionCount: 0
        duplicateUrlCount: 0
        duplicateOldCount: 0
        oldTvgIds: 0
        oldGroups: 0
    }

    for each u in oldByUrl.Keys()
        if newByUrl.DoesExist(u) then
            stats.retainedUrls = stats.retainedUrls + 1
            o = oldByUrl[u]
            n = newByUrl[u]
            if o.name <> n.name then stats.renamed = stats.renamed + 1
            if o.group <> n.group then stats.groupChanged = stats.groupChanged + 1
            if o.tvgId <> n.tvgId then stats.tvgIdChanged = stats.tvgIdChanged + 1
            if o.logoUrl <> n.logoUrl then stats.logoChanged = stats.logoChanged + 1
            if o.tvgName <> n.tvgName then stats.tvgNameChanged = stats.tvgNameChanged + 1
        else
            stats.removed = stats.removed + 1
        end if
    end for
    for each u in newByUrl.Keys()
        if oldByUrl.DoesExist(u) = false then stats.added = stats.added + 1
    end for

    ' Secondary identity for URL changes: tvg-id + normalized name + group,
    ' only when the key is unique on both sides.
    oldByKey = {}
    newByKey = {}
    oldKeyDup = {}
    newKeyDup = {}
    for each it in oldItems
        if it.url <> "" and newByUrl.DoesExist(it.url) = false and it.tvgId <> "" then
            k = it.tvgId + "|" + M3UNormalizeName(it.name) + "|" + LCase(it.group)
            if oldByKey.DoesExist(k) then
                oldKeyDup[k] = true
            else
                oldByKey[k] = it
            end if
        end if
    end for
    for each it in newItems
        if it.url <> "" and oldByUrl.DoesExist(it.url) = false and it.tvgId <> "" then
            k = it.tvgId + "|" + M3UNormalizeName(it.name) + "|" + LCase(it.group)
            if newByKey.DoesExist(k) then
                newKeyDup[k] = true
            else
                newByKey[k] = it
            end if
        end if
    end for
    for each k in oldByKey.Keys()
        if newByKey.DoesExist(k) and oldKeyDup.DoesExist(k) = false and newKeyDup.DoesExist(k) = false then
            o = oldByKey[k]
            n = newByKey[k]
            stats.urlChanged = stats.urlChanged + 1
            if o.name <> n.name then stats.renamed = stats.renamed + 1
            if o.group <> n.group then stats.groupChanged = stats.groupChanged + 1
            if o.tvgId <> n.tvgId then stats.tvgIdChanged = stats.tvgIdChanged + 1
            if o.logoUrl <> n.logoUrl then stats.logoChanged = stats.logoChanged + 1
            if o.tvgName <> n.tvgName then stats.tvgNameChanged = stats.tvgNameChanged + 1
        end if
    end for

    oldSeq = []
    newSeq = []
    for each it in oldItems
        if it.url <> "" and newByUrl.DoesExist(it.url) then oldSeq.Push(it.url)
    end for
    for each it in newItems
        if it.url <> "" and oldByUrl.DoesExist(it.url) then newSeq.Push(it.url)
    end for
    if M3UJoinArray(oldSeq) <> M3UJoinArray(newSeq) then stats.reordered = true

    stats.duplicateUrlCount = M3UDuplicateUrlCount(newItems)
    stats.duplicateOldCount = M3UDuplicateUrlCount(oldItems)

    oldIds = M3UUniqueMap(oldItems, "tvgId")
    newIds = M3UUniqueMap(newItems, "tvgId")
    oldGroups = M3UUniqueMap(oldItems, "group")
    newGroups = M3UUniqueMap(newItems, "group")
    stats.oldTvgIds = oldIds.Count()
    stats.oldGroups = oldGroups.Count()
    if stats.oldTvgIds > 0 then
        stats.tvgIdVariationCount = stats.oldTvgIds - M3UCommonCount(oldIds, newIds)
        stats.tvgIdVariationRate = stats.tvgIdVariationCount / stats.oldTvgIds
    end if
    if stats.oldGroups > 0 then
        stats.groupRetentionCount = M3UCommonCount(oldGroups, newGroups)
        stats.groupRetentionRate = stats.groupRetentionCount / stats.oldGroups
    end if
    if stats.oldCount > 0 then
        stats.removedRate = stats.removed / stats.oldCount
        stats.urlRetentionRate = stats.retainedUrls / stats.oldCount
    end if
    if stats.newCount > 0 then stats.addedRate = stats.added / stats.newCount

    return stats
end function

function M3UMedian(values as Object, fallback as Integer) as Integer
    if values = invalid then return fallback
    if values.Count() = 0 then return fallback
    sorted = []
    for each v in values
        sorted.Push(v)
    end for
    for i = 1 to sorted.Count() - 1
        v = sorted[i]
        j = i - 1
        while j >= 0 and sorted[j] > v
            sorted[j + 1] = sorted[j]
            j = j - 1
        end while
        sorted[j + 1] = v
    end for
    n = sorted.Count()
    if n mod 2 = 1 then return sorted[(n - 1) \ 2]
    return Int((sorted[n \ 2 - 1] + sorted[n \ 2]) / 2)
end function

function M3UDetectAnomaly(stats as Object, recentCounts as Object) as Object
    prev = stats.oldCount
    newCount = stats.newCount
    median = M3UMedian(recentCounts, prev)
    reasons = []
    quantity = false
    composition = false

    if prev >= 20 then
        if newCount < (median * 0.6) and (median - newCount) >= 10 then
            quantity = true
            reasons.Push("quantity_drop")
        end if
        if newCount > (median * 3) or (newCount - median) > 1000 then
            quantity = true
            reasons.Push("quantity_growth")
        end if
    end if

    if prev >= 20 then
        if stats.urlRetentionRate < 0.5 then
            composition = true
            reasons.Push("url_retention")
        end if
        if stats.addedRate > 0.5 or stats.removedRate > 0.5 then
            composition = true
            reasons.Push("stream_turnover")
        end if
        if stats.oldTvgIds > 0 and stats.tvgIdVariationRate > 0.5 then
            composition = true
            reasons.Push("tvgid_variation")
        end if
        if stats.oldGroups > 0 and stats.groupRetentionRate < 0.5 then
            composition = true
            reasons.Push("group_variation")
        end if
        dupLimit = newCount * 0.1
        if dupLimit < 3 then dupLimit = 3
        prevDupLimit = stats.duplicateOldCount * 2
        if prevDupLimit < 1 then prevDupLimit = 1
        if stats.duplicateUrlCount > dupLimit and stats.duplicateUrlCount > prevDupLimit then
            composition = true
            reasons.Push("duplicate_urls")
        end if
    end if

    return {
        anomaly: quantity or composition
        quantity: quantity
        composition: composition
        reasons: reasons
        median: median
        metrics: {
            urlRetentionRate: stats.urlRetentionRate
            addedRate: stats.addedRate
            removedRate: stats.removedRate
            tvgIdVariationRate: stats.tvgIdVariationRate
            groupRetentionRate: stats.groupRetentionRate
            duplicateUrlCount: stats.duplicateUrlCount
            duplicateOldCount: stats.duplicateOldCount
            oldCount: prev
            newCount: newCount
        }
    }
end function

function M3UItemIdentityKey(item as Object) as String
    if item = invalid then return ""
    if item.kind <> "ch" then return "k:" + item.kind
    if item.url <> "" then return "u:" + item.url
    if item.tvgId <> invalid and item.tvgId <> "" then return "t:" + item.tvgId + "|" + M3UNormalizeName(item.name) + "|" + LCase(item.group)
    return "n:" + M3UNormalizeName(item.name) + "|" + LCase(item.group)
end function

function M3UFindIndexForItem(items as Object, oldItem as Object) as Integer
    if oldItem = invalid then return -1
    if oldItem.kind <> "ch" then return -1
    for i = 0 to items.Count() - 1
        it = items[i]
        if it.kind = "ch" and it.url = oldItem.url and oldItem.url <> "" then return i
    end for
    if oldItem.tvgId <> invalid and oldItem.tvgId <> "" then
        found = -1
        n = 0
        for i = 0 to items.Count() - 1
            it = items[i]
            if it.kind = "ch" and it.tvgId <> invalid and it.tvgId = oldItem.tvgId then
                found = i
                n = n + 1
            end if
        end for
        if n = 1 then return found
    end if
    key = M3UNormalizeName(oldItem.name) + "|" + LCase(oldItem.group)
    found = -1
    n = 0
    for i = 0 to items.Count() - 1
        it = items[i]
        if it.kind = "ch" and (M3UNormalizeName(it.name) + "|" + LCase(it.group)) = key then
            found = i
            n = n + 1
        end if
    end for
    if n = 1 then return found
    return -1
end function

function M3UCanConfirm(pendingHash as String, currentHash as String, pendingAt as Integer, now as Integer, confirmAfter as Integer) as Boolean
    if pendingHash = "" or currentHash = "" then return false
    if pendingHash <> currentHash then return false
    if pendingAt <= 0 then return false
    return (now - pendingAt) >= confirmAfter
end function

function M3UBackoffSeconds(failures as Integer) as Integer
    waits = [120, 300, 900, 1800, 3600]
    idx = failures - 1
    if idx < 0 then idx = 0
    if idx >= waits.Count() then idx = waits.Count() - 1
    return waits[idx]
end function

function M3UChooseRecoveryCandidate(candidates as Object, centralVersion as String) as Object
    out = { ok: false, index: -1, ambiguous: false }
    if candidates = invalid then return out
    if candidates.Count() = 0 then return out
    best = 0
    ambiguous = false
    if candidates.Count() > 1 then
        c = candidates[1]
        b = candidates[0]
        bv = b.version
        cv = c.version
        if bv = invalid then bv = ""
        if cv = invalid then cv = ""
        if bv <> cv then
            if cv > bv then best = 1
        else
            ba = b.confirmedAt
            ca = c.confirmedAt
            if ba = invalid then ba = 0
            if ca = invalid then ca = 0
            if ca > ba then
                best = 1
            else if ca = ba then
                ambiguous = true
            end if
        end if
    end if
    chosenVersion = candidates[best].version
    if chosenVersion = invalid then chosenVersion = ""
    if centralVersion <> "" and centralVersion <> chosenVersion then ambiguous = true
    out.ok = true
    out.index = best
    out.ambiguous = ambiguous
    return out
end function
