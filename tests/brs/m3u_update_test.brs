sub main()
    counts = { pass: 0, fail: 0, pending: 0 }
    TestValidation(counts)
    TestHashAndDiff(counts)
    TestAnomaly(counts)
    TestRecoveryHelpers(counts)
    TestCatalogAndEpg(counts)
    TestLogoGeometry(counts)
    TestGridHelpers(counts)
    print "RESULT pass=" + counts.pass.ToStr() + " fail=" + counts.fail.ToStr() + " pending=" + counts.pending.ToStr()
    if counts.fail > 0 then print "FAILURES PRESENT"
end sub

sub Check(cond as Boolean, label as String, counts as Object)
    if cond then
        counts.pass = counts.pass + 1
        print "ok - " + label
    else
        counts.fail = counts.fail + 1
        print "FAIL - " + label
    end if
end sub

sub Pending(label as String, counts as Object)
    counts.pending = counts.pending + 1
    print "PENDIENTE hardware/simulacion - " + label
end sub

function MakeItems(n as Integer, group as String, urlPrefix as String, idPrefix as String) as Object
    out = []
    for i = 1 to n
        out.Push({
            kind: "ch"
            name: "C" + i.ToStr()
            group: group
            url: urlPrefix + i.ToStr()
            subs: ""
            tvgId: idPrefix + i.ToStr() + "@SD"
            tvgName: ""
            logoUrl: ""
        })
    end for
    return out
end function

sub TestValidation(counts as Object)
    valid = M3UValidateText("#EXTM3U" + Chr(10) + "#EXTINF:-1 tvg-id=""A.us@SD"" group-title=""News"",A" + Chr(10) + "https://x/a.m3u8")
    Check(valid.ok, "parser/metadata: M3U valida", counts)
    Check(valid.items[0].tvgId = "A.us@SD", "parser/metadata: tvg-id capturado", counts)
    Check(M3UValidateText("<html>error</html>").reason = "html", "M3U: HTML rechazado", counts)
    Check(M3UValidateText("#EXTM3U" + Chr(10) + "#EXTINF:-1,Only").reason = "truncated", "M3U: truncada rechazada", counts)
    Check(M3UValidateText("").reason = "empty", "M3U: vacia rechazada", counts)
    Check(M3UValidateText("#EXTM3U" + Chr(10) + "#EXTINF:-1,A" + Chr(10) + "rtsp://x/a").ok, "protocolos: rtsp aceptado sin filtro", counts)
    Check(M3UUrlLooksValid("rtsp://example.test/a"), "protocolos: URL rtsp valida", counts)
    Check(M3UUrlLooksValid("https://example.test/a"), "protocolos: URL https valida", counts)
    Check(M3UUrlLooksValid("") = false, "protocolos: URL vacia invalida", counts)
end sub

sub TestHashAndDiff(counts as Object)
    a = "#EXTM3U" + Chr(10) + "#EXTINF:-1,A" + Chr(10) + "https://x/a"
    b = "#EXTM3U" + Chr(10) + "#EXTINF:-1,A" + Chr(10) + "https://x/b"
    va = M3UValidateText(a)
    vb = M3UValidateText(b)
    ha = M3UHash(a, va.items)
    hb = M3UHash(b, vb.items)
    Check(ha = M3UHash(a, va.items), "hash: mismo contenido mismo hash", counts)
    Check(ha <> hb, "hash: contenido distinto cambia hash", counts)
    old = MakeItems(100, "News", "https://old/", "T")
    same = MakeItems(100, "News", "https://old/", "T")
    stats0 = M3UComputeDiff(old, same)
    Check(stats0.reordered = false, "diff: fuente sin cambios", counts)

    added = MakeItems(100, "News", "https://old/", "T")
    added.Push({kind:"ch",name:"New",group:"News",url:"https://new/1",subs:"",tvgId:"NEW@SD",tvgName:"",logoUrl:""})
    stats1 = M3UComputeDiff(old, added)
    Check(stats1.added = 1, "diff: canal agregado", counts)

    removed = MakeItems(99, "News", "https://old/", "T")
    stats2 = M3UComputeDiff(old, removed)
    Check(stats2.removed = 1, "diff: canal eliminado", counts)

    urlChanged = MakeItems(100, "News", "https://old/", "T")
    urlChanged[0] = {kind:"ch",name:"C1",group:"News",url:"https://changed/1",subs:"",tvgId:"T1@SD",tvgName:"",logoUrl:""}
    stats3 = M3UComputeDiff(old, urlChanged)
    Check(stats3.urlChanged = 1, "diff: cambio de URL por identidad secundaria", counts)

    renamed = MakeItems(100, "News", "https://old/", "T")
    renamed[0] = {kind:"ch",name:"Renamed",group:"News",url:"https://old/1",subs:"",tvgId:"T1@SD",tvgName:"",logoUrl:""}
    stats4 = M3UComputeDiff(old, renamed)
    Check(stats4.renamed = 1, "diff: cambio de nombre", counts)

    reordered = MakeItems(100, "News", "https://old/", "T")
    reversed = []
    for i = reordered.Count() - 1 to 0 step -1
        reversed.Push(reordered[i])
    end for
    stats5 = M3UComputeDiff(old, reversed)
    Check(stats5.reordered, "diff: cambio de orden detectado", counts)

    duplicate = []
    for i = 1 to 20
        duplicate.Push({kind:"ch",name:"D" + i.ToStr(),group:"News",url:"https://dup/same",subs:"",tvgId:"D" + i.ToStr() + "@SD",tvgName:"",logoUrl:""})
    end for
    dupStats = M3UComputeDiff([], duplicate)
    Check(dupStats.duplicateUrlCount = 20, "diff: duplicados de URL contados", counts)
    Check(M3UFindIndexForItem(duplicate, {kind:"ch",name:"xD",group:"News",url:"https://dup/same",tvgId:"D1@SD"}) = 0, "identidad: URL prioritaria", counts)
    oldFav = {kind:"ch",name:"C1",group:"News",url:"https://x/a"}
    Check(M3UFindIndexForItem(old, oldFav) = 0, "favoritos antiguos: recuperacion por URL", counts)
    changed = MakeItems(1, "News", "https://new/", "T")
    Check(M3UFindIndexForItem(changed, {kind:"ch",name:"C1",group:"News",url:"https://x/old",tvgId:"T1@SD"}) = 0, "identidad: tvg-id unico tras cambio de URL", counts)
end sub

sub TestAnomaly(counts as Object)
    old = MakeItems(100, "News", "https://old/", "T")
    drop = MakeItems(5, "News", "https://old/", "T")
    dropStats = M3UComputeDiff(old, drop)
    dropAnom = M3UDetectAnomaly(dropStats, [100, 100, 100])
    Check(dropAnom.anomaly and dropAnom.quantity, "anomalia: caida de cantidad", counts)

    added = MakeItems(101, "News", "https://old/", "T")
    addAnom = M3UDetectAnomaly(M3UComputeDiff(old, added), [100, 100, 100])
    Check(addAnom.anomaly = false, "anomalia: cambio pequeno no bloquea", counts)

    replacement = []
    for i = 1 to 100
        if i <= 20 then
            replacement.Push(old[i - 1])
        else
            replacement.Push({kind:"ch",name:"C" + i.ToStr(),group:"News",url:"https://new/" + i.ToStr(),subs:"",tvgId:"T" + i.ToStr() + "@SD",tvgName:"",logoUrl:""})
        end if
    end for
    repStats = M3UComputeDiff(old, replacement)
    repAnom = M3UDetectAnomaly(repStats, [100, 100, 100])
    Check(repAnom.anomaly and repAnom.composition, "anomalia: misma cantidad, 80 URLs sustituidas", counts)

    idChange = MakeItems(20, "News", "https://old/", "T")
    idNew = MakeItems(20, "News", "https://old/", "X")
    idAnom = M3UDetectAnomaly(M3UComputeDiff(idChange, idNew), [20, 20, 20])
    Check(idAnom.anomaly and idAnom.composition, "anomalia: cambio masivo de tvg-id", counts)

    groupChange = MakeItems(20, "OldGroup", "https://old/", "T")
    groupNew = MakeItems(20, "NewGroup", "https://old/", "T")
    groupAnom = M3UDetectAnomaly(M3UComputeDiff(groupChange, groupNew), [20, 20, 20])
    Check(groupAnom.anomaly and groupAnom.composition, "anomalia: cambio masivo de grupos", counts)

    oldDup = MakeItems(20, "News", "https://unique/", "D")
    dup = []
    for i = 1 to 20
        dup.Push({kind:"ch",name:"D" + i.ToStr(),group:"News",url:"https://dup/same",subs:"",tvgId:"D" + i.ToStr() + "@SD",tvgName:"",logoUrl:""})
    end for
    dupAnom = M3UDetectAnomaly(M3UComputeDiff(oldDup, dup), [20, 20, 20])
    Check(dupAnom.anomaly and dupAnom.composition, "anomalia: duplicacion masiva", counts)

    Check(M3UCanConfirm("h", "h", 100, 700, 600), "anomalia: segunda lectura confirma", counts)
    Check(M3UCanConfirm("h", "h", 100, 500, 600) = false, "anomalia: no confirma antes de plazo", counts)
    Check(M3UBackoffSeconds(1) = 120 and M3UBackoffSeconds(9) = 3600, "backoff: valores acotados", counts)
end sub

sub TestRecoveryHelpers(counts as Object)
    Check(M3UCanConfirm("a", "b", 0, 999, 600) = false, "recuperacion: hash distinto no confirma", counts)
    c1 = [{slot:"a",version:"1",confirmedAt:10},{slot:"b",version:"2",confirmedAt:20}]
    r1 = M3UChooseRecoveryCandidate(c1, "")
    Check(r1.ok and r1.index = 1 and r1.ambiguous = false, "recuperacion: elige generacion mas reciente", counts)
    c2 = [{slot:"a",version:"1",confirmedAt:10},{slot:"b",version:"1",confirmedAt:20}]
    r2 = M3UChooseRecoveryCandidate(c2, "")
    Check(r2.index = 1 and r2.ambiguous = false, "recuperacion: usa confirmedAt si version empata", counts)
    c3 = [{slot:"a",version:"1",confirmedAt:10},{slot:"b",version:"1",confirmedAt:10}]
    r3 = M3UChooseRecoveryCandidate(c3, "")
    Check(r3.ambiguous, "recuperacion: ambiguedad marcada", counts)
    c4 = [{slot:"a",version:"1",confirmedAt:10},{slot:"b",version:"2",confirmedAt:20}]
    r4 = M3UChooseRecoveryCandidate(c4, "3")
    Check(r4.ambiguous, "recuperacion: version central distinta marca recuperacion", counts)
    Pending("reinicio durante actualizacion / slots A-B en dispositivo", counts)
    Pending("perdida total de cachefs", counts)
    Pending("metadatos corruptos y sidecars", counts)
    Pending("revalidacion HTTP 304/ETag", counts)
    Pending("timeout / DNS / HTTP 500", counts)
    Pending("interrupcion de descarga", counts)
end sub

sub TestLogoGeometry(counts as Object)
    square = FitLogoInBox(100, 100, 58, 36)
    Check(square.ok and square.width = 36 and square.height = 36 and square.x = 11 and square.y = 0, "geometria: cuadrado contenido y centrado", counts)
    wide = FitLogoInBox(200, 50, 58, 36)
    Check(wide.ok and wide.width = 58 and wide.height = 14.5 and wide.x = 0, "geometria: horizontal contenido", counts)
    tall = FitLogoInBox(50, 200, 58, 36)
    Check(tall.ok and tall.width = 9 and tall.height = 36 and tall.y = 0, "geometria: vertical contenido", counts)
    small = FitLogoInBox(10, 10, 58, 36)
    Check(small.ok and small.width = 10 and small.height = 10 and small.x = 24 and small.y = 13, "geometria: imagen pequena centrada", counts)
    Check(FitLogoInBox(0, 10, 58, 36).ok = false, "geometria: dimension invalida rechazada", counts)
end sub

sub TestGridHelpers(counts as Object)
    Check(Align30(1800900) = 1800000, "grilla: alineacion a 30 minutos", counts)
    progs = [{s:100,e:200,t:"A"},{s:200,e:300,t:"B"},{s:300,t:"C"}]
    Check(FindProgramAtTime(progs, 150) = 0, "grilla: programa en tiempo", counts)
    Check(FindProgramAtTime(progs, 250) = 1, "grilla: siguiente bloque", counts)
    Check(FindProgramAtTime(progs, 350) = 2, "grilla: programa sin stop", counts)
    Check(EpgProgramsOverlap(progs, 120, 180), "filtro: solape con ventana", counts)
    Check(EpgProgramsOverlap([{s:100,e:200,t:"A"}], 400, 500) = false, "filtro: programa fuera de ventana", counts)
    Check(EpgProgramsOverlap([{s:100,t:"NoStop"}], 150, 200), "filtro: programa sin stop en ventana", counts)
    Check(EpgProgramIsCurrent(progs, 0, 150), "grilla: programa actual", counts)
    Check(EpgProgramIsCurrent(progs, 1, 250), "grilla: siguiente actual", counts)
    Check(EpgProgramIsCurrent(progs, 1, 150) = false, "grilla: futuro no actual", counts)
    Check(EpgProgramIsCurrent(progs, 2, 350), "grilla: sin stop actual", counts)
end sub

sub TestCatalogAndEpg(counts as Object)
    item = {kind:"ch",name:"A",group:"News",url:"https://x/a",subs:"",tvgId:"A.us@SD",tvgName:"",logoUrl:""}
    catalog = {logoBase:"https://cdn/", channels:{ "A.us@SD": {logo:"a.png", epgId:"A.us@SD"} }}
    Check(CatalogLogoForItem(catalog, item) = "https://cdn/a.png", "logos: fallback desde catalogo", counts)
    Check(CatalogLogoForItem(catalog, {kind:"ch",tvgId:"A.us@SD",logoUrl:"https://x/direct.png"}) = "https://x/direct.png", "logos: tvg-logo prioritario", counts)
    Check(ResolveLogoPlaceholder("") = "pkg:/images/logo_placeholder.png", "logos: placeholder", counts)

    epg = {channels:{ "A.us@SD": {programs:[
        {s:100,e:200,t:"One"},
        {s:200,t:"Two"},
        {s:300,e:400,t:"Three"}
    ], endKnown:false} }}
    now = EpgSelectNowNext(epg, "A.us@SD", 150)
    Check(now.hasNow and now.nowTitle = "One", "EPG: programa actual", counts)
    Check(now.progress = 0.5, "EPG: progreso", counts)
    unknown = EpgSelectNowNext(epg, "A.us@SD", 250)
    Check(unknown.hasNow and unknown.unknownDuration and unknown.progress = -1, "EPG: programa sin stop", counts)
    later = EpgSelectNowNext(epg, "A.us@SD", 500)
    Check(later.hasNow = false and later.hasNext = false, "EPG: ventana agotada", counts)
    Check(JoinUrl(DefaultMetaBase(), "latest.json") = "https://robinpalat.github.io/streams-roku/real/latest.json", "URL: produccion conserva prefijo del repo", counts)
    Check(JoinUrl("https://robinpalat.github.io/streams-roku/real/", "/catalog.json") = "https://robinpalat.github.io/streams-roku/real/catalog.json", "URL: JoinUrl normaliza barras", counts)
    Check(IsLegacyLocalMeta("http://192.168.1.7:8001/real/"), "URL: detecta meta LAN antigua", counts)
    Check(IsLegacyLocalMeta("https://robinpalat.github.io/streams-roku/real/") = false, "URL: no migra meta HTTPS", counts)
end sub

function ResolveLogoPlaceholder(value as String) as String
    if value = "" then return "pkg:/images/logo_placeholder.png"
    return value
end function
