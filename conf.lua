function love.conf(t)
    t.identity = "Telegram"
    t.version = "11.5"
    t.console = false

    t.window.title = "SPgram"
    t.window.width = 640
    t.window.height = 480
    t.window.resizable = false
    t.window.fullscreen = true
    t.window.vsync = 1
    t.window.msaa = 0
    t.window.highdpi = false

    t.modules.physics = false
    t.modules.video = true
    t.modules.audio = true
    t.modules.joystick = true
    t.modules.thread = true
end
