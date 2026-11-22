sub Main(args as Dynamic)
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.SetMessagePort(port)
    input = CreateObject("roInput")
    input.SetMessagePort(port)

    scene = screen.CreateScene("MainScene")
    screen.Show()
    scene.SetFocus(true)

    n = 0
    ' arranque desde la web: contentId (URL del stream), name
    if args <> invalid then
        if Type(args) = "roAssociativeArray" then
            n = n + 1
            a = {}
            a.Append(args)
            a.nonce = n.ToStr()
            scene.launchArgs = a
        end if
    end if

    while true
        msg = Wait(0, port)
        t = Type(msg)
        if t = "roSGScreenEvent" then
            if msg.IsScreenClosed() then return
        else if t = "roInputEvent" then
            ' canal ya abierto: llega un nuevo stream desde la web
            if msg.IsInput() then
                info = msg.GetInfo()
                if info <> invalid then
                    n = n + 1
                    a = {}
                    a.Append(info)
                    a.nonce = n.ToStr()
                    scene.launchArgs = a
                end if
            end if
        end if
    end while
end sub
