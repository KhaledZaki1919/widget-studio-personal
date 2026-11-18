# Draws the ADR-029 eval cases (docs/ai-eval/draw-p-*.png) with GDI+: widgets in the style of the
# image-to-widget report's problem areas, drawn for this repository (no third-party images).
# Run: powershell -ExecutionPolicy Bypass -File scripts/draw-pdf-cases.ps1
Add-Type -AssemblyName System.Drawing
$out = Join-Path $PSScriptRoot "..\docs\ai-eval"

function New-Canvas($w, $h, $bg) {
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = "AntiAlias"
    $g.TextRenderingHint = "AntiAliasGridFit"
    $g.Clear([System.Drawing.ColorTranslator]::FromHtml($bg))
    return @($bmp, $g)
}
function Brush($hex) { New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml($hex)) }
function Font($size, $style = "Regular") { New-Object System.Drawing.Font "Segoe UI", $size, ([System.Drawing.FontStyle]::$style), ([System.Drawing.GraphicsUnit]::Pixel) }
function RoundRect($g, $brush, $x, $y, $w, $h, $r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $p.AddArc($x, $y, 2 * $r, 2 * $r, 180, 90); $p.AddArc($x + $w - 2 * $r, $y, 2 * $r, 2 * $r, 270, 90)
    $p.AddArc($x + $w - 2 * $r, $y + $h - 2 * $r, 2 * $r, 2 * $r, 0, 90); $p.AddArc($x, $y + $h - 2 * $r, 2 * $r, 2 * $r, 90, 90)
    $p.CloseFigure(); $g.FillPath($brush, $p)
}
function Cloud($g, $brush, $x, $y, $s) {
    $g.FillEllipse($brush, $x, $y + 0.35 * $s, 0.5 * $s, 0.45 * $s)
    $g.FillEllipse($brush, $x + 0.25 * $s, $y + 0.1 * $s, 0.55 * $s, 0.6 * $s)
    $g.FillEllipse($brush, $x + 0.55 * $s, $y + 0.35 * $s, 0.45 * $s, 0.45 * $s)
    $g.FillRectangle($brush, $x + 0.2 * $s, $y + 0.5 * $s, 0.65 * $s, 0.3 * $s)
}
function Save($bmp, $name) { $bmp.Save((Join-Path $out $name), [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose() }
$white = Brush "#FFFFFF"; $gray = Brush "#8E8E93"; $black = Brush "#000000"

# 1. A week strip on a wide black island (calendar rows: week).
$bmp, $g = New-Canvas 900 330 "#F2F2F2"
RoundRect $g $black 30 30 840 270 70
$g.DrawString("November", (Font 34), $gray, 100, 62); $g.DrawString("3 events", (Font 34), $gray, 640, 62)
$days = "Mo","Tu","We","Th","Fr","Sa","Su"; $dates = 9..15
for ($i = 0; $i -lt 7; $i++) {
    $x = 120 + $i * 108
    $g.DrawString($days[$i], (Font 36 "Bold"), $white, $x - 18, 128)
    if ($dates[$i] -eq 12) { $g.FillEllipse($white, $x - 24, 190, 64, 64); $g.DrawString("$($dates[$i])", (Font 34 "Bold"), $black, $x - 16, 200) }
    else { $g.DrawString("$($dates[$i])", (Font 34), $white, $x - 16, 200) }
}
Save $bmp "draw-p-week.png"

# 2. Hourly rain forecast on a white card.
$bmp, $g = New-Canvas 760 380 "#E9EAEE"
RoundRect $g $white 20 20 720 340 48
Cloud $g $black 60 50 90; $g.DrawString("23°", (Font 64), $black, 170, 52)
$g.DrawString("Rain", (Font 40 "Bold"), $black, 590, 50); $g.DrawString("Cairo", (Font 32), $gray, 600, 100)
$hours = "4 PM","5 PM","6 PM","7 PM","8 PM","9 PM"; $temps = 23,22,21,21,21,20
for ($i = 0; $i -lt 6; $i++) {
    $x = 70 + $i * 110
    $g.DrawString($hours[$i], (Font 24), $gray, $x - 6, 190); Cloud $g $black ($x + 4) 230 50
    $g.DrawString("$($temps[$i])°", (Font 26), $black, $x + 4, 290)
}
Save $bmp "draw-p-hourly.png"

# 3. Heart rate with a candle chart and y labels (chart kind candles, heart bindings).
$bmp, $g = New-Canvas 820 400 "#3A3530"
RoundRect $g (Brush "#1E1B19") 20 20 780 360 50
$g.DrawString("Heart Rate", (Font 46), $white, 60, 50); $g.DrawString("resting", (Font 28), $gray, 62, 106)
$g.DrawString("61", (Font 80 "Bold"), $white, 570, 34); $g.DrawString("bpm", (Font 24), $gray, 700, 110)
$g.DrawString("130", (Font 22), $gray, 60, 170); $g.DrawString("90", (Font 22), $gray, 66, 235); $g.DrawString("50", (Font 22), $gray, 66, 300)
$rand = New-Object System.Random 7
for ($i = 0; $i -lt 34; $i++) {
    $x = 130 + $i * 19; $lo = 250 - 70 * [Math]::Sin($i / 6) - $rand.Next(0, 30); $h = 12 + $rand.Next(0, 26)
    RoundRect $g $white $x ($lo - $h) 6 $h 3
}
$g.DrawString("1 AM", (Font 22), $gray, 120, 330); $g.DrawString("6 AM", (Font 22), $gray, 400, 330); $g.DrawString("1 PM", (Font 22), $gray, 690, 330)
Save $bmp "draw-p-heart.png"

# 4. A scallop clock with the date along the top and thick rounded hands.
$bmp, $g = New-Canvas 600 600 "#4E6B3A"
$p = New-Object System.Drawing.Drawing2D.GraphicsPath; $pts = @()
for ($k = 0; $k -le 240; $k++) { $t = $k / 240 * 2 * [Math]::PI; $r = 270 * (0.93 + 0.07 * [Math]::Cos(12 * $t)); $pts += New-Object System.Drawing.PointF ([float](300 + $r * [Math]::Sin($t))), ([float](300 - $r * [Math]::Cos($t))) }
$p.AddPolygon($pts); $g.FillPath((Brush "#EEF0F3"), $p)
$chars = "Thu 12".ToCharArray(); $start = -22
for ($k = 0; $k -lt $chars.Length; $k++) {
    $a = ($start + $k * 9) * [Math]::PI / 180; $x = 300 + 215 * [Math]::Sin($a); $y = 300 - 215 * [Math]::Cos($a)
    $s = $g.Save(); $g.TranslateTransform([float]$x, [float]$y); $g.RotateTransform([float]($start + $k * 9)); $g.DrawString($chars[$k], (Font 46 "Bold"), (Brush "#3C4043"), -14, -26); $g.Restore($s)
}
$pen = New-Object System.Drawing.Pen ([System.Drawing.ColorTranslator]::FromHtml("#5F6368")), 46; $pen.StartCap = "Round"; $pen.EndCap = "Round"
$g.DrawLine($pen, 300, 300, 420, 360)
$pen2 = New-Object System.Drawing.Pen ([System.Drawing.ColorTranslator]::FromHtml("#9AA0A6")), 40; $pen2.StartCap = "Round"; $pen2.EndCap = "Round"
$g.DrawLine($pen2, 300, 300, 460, 210); $g.FillEllipse((Brush "#6F8BA4"), 275, 480, 50, 50)
Save $bmp "draw-p-scallop.png"

# 5. A stock card: ticker, price, change and an area line chart over a dashed baseline.
$bmp, $g = New-Canvas 760 420 "#C7CBD1"
RoundRect $g $black 20 20 720 380 70
$g.DrawString("TICKER", (Font 26), $gray, 70, 60); $g.DrawString("Company", (Font 34 "Bold"), $white, 70, 92)
$g.DrawString("updated", (Font 24), $gray, 560, 60); $g.DrawString("2m ago", (Font 32 "Bold"), $white, 560, 92)
$g.DrawString("`$ 8.01", (Font 64), $white, 70, 150); $g.DrawString("+0.92", (Font 26), (Brush "#34C759"), 300, 160); $g.DrawString("+1.24%", (Font 26), (Brush "#34C759"), 300, 192)
$vals = 30,28,31,33,29,26,27,20,21,25,24,26,28,27,30,29,31,30,33,32; $line = @()
for ($i = 0; $i -lt $vals.Count; $i++) { $line += New-Object System.Drawing.PointF ([float](70 + $i * 32)), ([float](370 - $vals[$i] * 3)) }
$area = $line + (New-Object System.Drawing.PointF 678, 370) + (New-Object System.Drawing.PointF 70, 370)
$grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.Point 0, 250), (New-Object System.Drawing.Point 0, 370), ([System.Drawing.Color]::FromArgb(150, 52, 199, 89)), ([System.Drawing.Color]::FromArgb(0, 52, 199, 89))
$g.FillPolygon($grad, $area); $g.DrawLines((New-Object System.Drawing.Pen ([System.Drawing.ColorTranslator]::FromHtml("#34C759")), 4), $line)
$dash = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(160, 255, 255, 255)), 2; $dash.DashPattern = 6, 6; $g.DrawLine($dash, 70, 280, 680, 280)
Save $bmp "draw-p-stock.png"

# 6. A tall assistant pill: a light pill with a sparkle (card capsule vertical, assistant.open).
$bmp, $g = New-Canvas 360 560 "#5A7A4A"
RoundRect $g (Brush "#F1F3F4") 40 30 280 500 140
RoundRect $g (Brush "#D3E3FD") 80 80 200 400 100
$sp = New-Object System.Drawing.Drawing2D.GraphicsPath
$sp.AddPolygon(@((New-Object System.Drawing.PointF 180, 220), (New-Object System.Drawing.PointF 198, 262), (New-Object System.Drawing.PointF 240, 280), (New-Object System.Drawing.PointF 198, 298), (New-Object System.Drawing.PointF 180, 340), (New-Object System.Drawing.PointF 162, 298), (New-Object System.Drawing.PointF 120, 280), (New-Object System.Drawing.PointF 162, 262)))
$g.FillPath((Brush "#0B1D33"), $sp)
Save $bmp "draw-p-pill.png"
"drawn"
