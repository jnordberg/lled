
lled = require './../'

randomPick = (list) -> list[~~(Math.random() * list.length)]

lled.discover (error, bridges) ->
  throw error if error?

  if bridges.length is 0
    console.log 'Did not find any bridges, exiting...'
    return

  console.log "Found #{ bridges.length } bridges."

  bridges.forEach (bridge) -> bridge.on 'error', (error) -> console.log "Bridge #{ bridge.address } error - #{ error.message }"

  beatInterval = (60 / 128) * 1000
  remotes = [lled.Commands.RGBCCT, lled.Commands.RGBW]

  console.log '-- Tap enter to adjust BPM --\n'

  tapTimer = null
  taps = []
  hrnow = ->
    t = process.hrtime()
    return t[0] * 1000 + (t[1] / 1e6)

  process.stdin.on 'data', (data) ->
    process.stdout.write '\u001b[1A'
    process.stdout.write randomPick ['NICE', 'YEAH', 'COOL', 'GREAT', 'AWESOME', 'SWEET']
    process.stdout.write '\n'
    clearTimeout tapTimer
    taps.push hrnow()
    tapTimer = setTimeout (-> taps = []), 4000
    return if taps.length < 3
    avg = 0
    count = 0
    for tap, idx in taps
      continue unless prev = taps[idx - 1]
      avg += tap - prev
      count++
    beatInterval = avg / count
    do beat

  beatTimer = null
  beat = ->
    clearTimeout beatTimer
    beatTimer = setTimeout beat, beatInterval
    ooyeee = randomPick ['omf', 'umf', 'OOOMPH', 'oo yeah', 'unfF', 'oMHF', 'ook', 'BONG', 'dong', 'Bam', 'blip', 'blop', 'tock']
    process.stdout.write "#{ Math.round (60 / (beatInterval / 1000)) } #{ ooyeee }\n"
    bridges.forEach (bridge) ->
      for remote in remotes
        for zone in [1..4]
          cmd = remote.SetHue(Math.random() * 0xff)
          # console.log "Zone #{ zone } Cmd: #{ cmd }"
          bridge.send cmd, zone, (error) ->
            if error?
              console.log "Bridge #{ bridge.address } command error - #{ error.message }"

  remotes.forEach (remote) -> bridges.forEach (bridge) ->
    bridge.send remote.On(), 0, (error) ->
      bridge.send remote.SetBrightness(0x64), 0, (error) ->
        console.log "Bridge #{ bridge.address } command error - #{ error.message }" if error?

  do beat
