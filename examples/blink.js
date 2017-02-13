
var lled = require('./../')

lled.discover(function(error, bridges) {
    if (error) throw error

    console.log('Found', bridges.length, 'bridges')

    if (bridges.length == 0) return

    var bridge = bridges[0]
    console.log('Using bridge at', bridge.address, 'with mac', bridge.mac)

    // if you don't listen to the error event errors will be thrown and exit the process
    bridge.on('error', function(error) {
        console.log('Bridge error', error)
    })

    var zone = 4 // which zone to control, 0 = all zones
    var isOn = false
    function blink() {
        var cmd = isOn ? lled.Commands.RGBCCT.Off() : lled.Commands.RGBCCT.On()
        bridge.send(cmd, zone, function(error) {
            if (error) {
                console.log('Error sending command', error)
            } else {
                isOn = !isOn
                console.log('All lamps in zone', zone, 'are now', isOn ? 'on' : 'off')
                setTimeout(blink, 500)
            }
        })
    }
    blink()
})
