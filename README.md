
lled
====

node.js library for controlling LimitlessLED (a.k.a. MiLight) WiFi bridges (v6+)


Install
-------

```bash
npm install lled
```


Usage
-----

```javascript
var lled = require('lled')

lled.discover(function(error, bridges) {
    if (error) throw error
    bridges.forEach(function(bridge) {
        var zone = 0 // 1-4, 0 = all zones
        bridge.send(lled.Commands.RGBW.On(), 0, function(error) {
            if (error) throw error
            console.log('Turned on all RGBW bulbs.')
            bridge.close() // closes the underlying socket allowing the process to exit
        })
    })
})
```

See `examples/` for more and have a look at `src/brige.coffee` for all options.


Notes
-----

Altough the v6 bridges now ACKs the commands sent to it, that's not a guarantee the command reaches the lights since the 2.4ghz protocol the bridge uses to communicate with the lights are still one-way. So you are better off sending each command multiple times to ensure it reaches all lightbulbs.


License
-------

[BSD 3-Clause](https://en.wikipedia.org/wiki/BSD_licenses#3-clause_license_.28.22BSD_License_2.0.22.2C_.22Revised_BSD_License.22.2C_.22New_BSD_License.22.2C_or_.22Modified_BSD_License.22.29)

