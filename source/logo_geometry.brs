' Pure geometry for a fixed logo box. The image is fitted with "contain"
' semantics and centered inside the box; it can never exceed the box.

function FitLogoInBox(imageWidth as Float, imageHeight as Float, boxWidth as Float, boxHeight as Float) as Object
    out = { ok: false, width: 0.0, height: 0.0, x: 0.0, y: 0.0 }
    if imageWidth <= 0 or imageHeight <= 0 or boxWidth <= 0 or boxHeight <= 0 then return out
    scale = 1.0
    if imageWidth > boxWidth or imageHeight > boxHeight then
        sx = boxWidth / imageWidth
        sy = boxHeight / imageHeight
        scale = sx
        if sy < sx then scale = sy
    end if
    out.width = imageWidth * scale
    out.height = imageHeight * scale
    out.x = (boxWidth - out.width) / 2
    out.y = (boxHeight - out.height) / 2
    out.ok = true
    return out
end function
