### Interface for the LimitlessLED WiFi bridge v6. ###

async = require 'async'
dgram = require 'dgram'
{EventEmitter} = require 'events'


START_SESSION = new Buffer [
  0x20, 0x00, 0x00, 0x00, 0x16, 0x02, 0x62, 0x3A, 0xD5, 0xED, 0xA3, 0x01,
  0xAE, 0x08, 0x2D, 0x46, 0x61, 0x41, 0xA7, 0xF6, 0xDC, 0xAF, 0xD3, 0xE6,
  0x00, 0x00, 0x1E
]

CMD_HEADER = new Buffer [
  0x80, 0x00, 0x00, 0x00, 0x11
]

# Sent by the app every 10 or so seconds, response is always d8:00:00:00:07:MACADDR:01
# Not sure if needed, seems to work fine w/o
KEEPALIVE = new Buffer [
  0xd0, 0x00, 0x00, 0x00, 0x02, 0x4c, 0x00
]

Commands =

  # RGB + White bulbs (256 colors)
  RGBW:
    Off:                  -> [0x31, 0x00, 0x00, 0x07, 0x03, 0x02, 0x00, 0x00, 0x00]
    On:                   -> [0x31, 0x00, 0x00, 0x07, 0x03, 0x01, 0x00, 0x00, 0x00]
    NightOn:              -> [0x31, 0x00, 0x00, 0x07, 0x03, 0x06, 0x00, 0x00, 0x00]
    WhiteOn:              -> [0x31, 0x00, 0x00, 0x07, 0x03, 0x05, 0x00, 0x00, 0x00]
    SetHue:        (parm) -> [0x31, 0x00, 0x00, 0x07, 0x01, parm, parm, parm, parm]
    SetBrightness: (parm) -> [0x31, 0x00, 0x00, 0x07, 0x02, parm, 0x00, 0x00, 0x00]

  # "Full color" bulbs (25600 colors)
  RGBCCT:
    Off:                  -> [0x31, 0x00, 0x00, 0x08, 0x04, 0x02, 0x00, 0x00, 0x00]
    On:                   -> [0x31, 0x00, 0x00, 0x08, 0x04, 0x01, 0x00, 0x00, 0x00]
    NightOn:              -> [0x31, 0x00, 0x00, 0x08, 0x04, 0x05, 0x00, 0x00, 0x00]
    SetHue:        (parm) -> [0x31, 0x00, 0x00, 0x08, 0x01, parm, parm, parm, parm]
    SetSaturation: (parm) -> [0x31, 0x00, 0x00, 0x08, 0x02, parm, 0x00, 0x00, 0x00]
    SetBrightness: (parm) -> [0x31, 0x00, 0x00, 0x08, 0x03, parm, 0x00, 0x00, 0x00]
    SetKelvin:     (parm) -> [0x31, 0x00, 0x00, 0x08, 0x05, parm, 0x00, 0x00, 0x00]
    Link:                 -> [0x3D, 0x00, 0x00, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00]
    UnLink:               -> [0x3E, 0x00, 0x00, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00]


makeCommandPackage = (cmd, id1, id2, seqId, zone=0) ->
  ### Return buffer with command package. Structure:
    80:00:00:00:11:XX:XX:00:XX:00:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:00:XX
    Header         ^^^^^    ^^    Command (9 bytes)          ^^    ^^
                   Session  Sequence no.                     Zone  Checksum
  ###
  if cmd.length isnt 9
    throw new Error 'Command data must be exactly 9 bytes.'
  ptr = 0
  rv = Buffer.allocUnsafe 22
  ptr += CMD_HEADER.copy rv, ptr
  rv.writeUInt8 id1, ptr++
  rv.writeUInt8 id2, ptr++
  rv.writeUInt8 0x00, ptr++
  rv.writeUInt8 (seqId & 0xff), ptr++
  rv.writeUInt8 0x00, ptr++
  ptr += cmd.copy rv, ptr
  rv.writeUInt8 zone, ptr++
  checksum = 0
  checksum += rv[i] for i in [ptr-10...ptr]
  rv.writeUInt8 0x00, ptr++
  rv.writeUInt8 (checksum & 0xff), ptr
  return rv

class Bridge extends EventEmitter

  defaults =

    # how long in milliseconds to wait for the bridge to respond
    commandTimeout: 1000 # 1 second

    # how long in milliseconds before considering the sessionId to be stale
    sessionTimeout: 5 * 60 * 1000 # 5 minutes
    # the bridge will drop the session after some time of inactivity
    # timer is refreshed every time data is recieved from the bridge

  constructor: (@address, @mac, options={}) ->
    @sessionId = null
    @sessionTimer = null
    # the sequence number is only one byte so don't send more than 256 commands at once
    # in my tests i was able to send about 50 commands per second before starting to see errors
    # dunno if it's my network or the bridge not keeping up, why dont they just use tcp?
    @nextSeq = 0
    @waiting = {}
    @options = {}
    for key of defaults
      @options[key] = options[key] ? defaults[key]
    do @_setupSocket

  _setupSocket: ->
    @socket = dgram.createSocket 'udp4'
    @socket.on 'error', @_error.bind(this)
    @socket.on 'message', @_recv.bind(this)

  _send: (data, callback) ->
    @socket.send data, 0, data.length, 5987, @address, callback

  _error: (error) ->
    @emit 'error', error

  _recv: (data) ->
    switch data[0]

      # Session init
      when 0x28
        clearTimeout @_sessionInitTimer

        unless @_sessionCallbacks?
          @_error new Error "Got init packet without asking for it."
          return

        callback = (error) =>
          @_sessionCallbacks.forEach (cb) -> cb error
          @_sessionCallbacks = null

        if data.length isnt 22
          callback new Error "Init packet size mismatch. Expected 22, got #{ data.length }."
          return

        mac = data[7...13].toString 'hex'
        if @mac? and mac isnt @mac.toLowerCase()
          callback new Error "Mac address mismatch. Expected #{ @mac }, got #{ mac }."
          return

        @sessionId = [data.readUInt8(19), data.readUInt8(20)]
        do callback

      # Command ack
      when 0x88
        seqId = data.readUInt8 6
        unless pkg = @waiting[seqId]
          @_error new Error "Got response for unknown seqId: #{ seqId }."
          return

        clearTimeout pkg.timer
        clearTimeout @sessionTimer

        responseCode = data.readUInt8 7
        if responseCode isnt 0
          # bridge not happy, probably the session expired
          @sessionId = null # ask for new session id on next send
          error = new Error "Got unexpected response code from bridge: #{ responseCode }."
        else
          # session ok, refresh timer
          @sessionTimer = setTimeout (=> @sessionId = null), @options.sessionTimeout

        delete @waiting[pkg.id]
        pkg.callback error

      # Unhandled
      else
        console.log 'WARNING: Got unknown data packet from bridge.', data

  _getSession: (callback) ->
    if @_sessionCallbacks?
      @_sessionCallbacks.unshift callback
      return
    @_sessionCallbacks = []
    @_send START_SESSION, (error) =>
      if error?
        @_sessionCallbacks = null
        callback error
      else
        @_sessionCallbacks.unshift callback
        timeout = =>
          error = new Error 'Timed out waiting for session id.'
          @_sessionCallbacks.forEach (cb) -> cb error
          @_sessionCallbacks = null
        @_sessionInitTimer = setTimeout timeout, @options.commandTimeout

  close: ->
    clearTimeout @_sessionInitTimer
    clearTimeout @sessionTimer
    for id, pkg of @waiting
      clearTimeout pkg.timer
      pkg.callback new Error 'Socket closed.'
      delete @waiting[id]
    @socket.close()

  send: (command, zone, callback) ->
    ### Send 9-byte *command* to *zone* (0-4, 0 meaning all). ###

    pkg = null
    tasks = []

    # command can be either an array of 9 UInt8's or a nodejs Buffer instance
    unless command instanceof Buffer
      command = Buffer.from command

    # get the session id if neccesary
    unless @sessionId?
      tasks.push (callback) => @_getSession callback

    # send command
    tasks.push (callback) =>
      try
        pkg = {id: (@nextSeq++ & 0xff)}
        data = makeCommandPackage command, @sessionId[0], @sessionId[1], pkg.id, zone
      catch
        callback error
        return
      @_send data, callback

    async.series tasks, (error) =>
      if error?
        callback error
        return
      # command was sent, wait for response
      pkg.callback = callback
      pkg.timer = setTimeout =>
        pkg.callback new Error 'Timed out waiting for response from bridge.'
        delete @waiting[pkg.id]
      , @options.commandTimeout
      @waiting[pkg.id] = pkg


Bridge.discover = (callback) ->
  ### Probe the network for bridges and *callback* with an array of Bridge instances found. ###

  bridges = []
  socket = dgram.createSocket 'udp4'

  done = ->
    socket.close()
    callback null, bridges

  socket.on 'error', callback

  socket.on 'message', (data, meta) ->
    [address, mac] = data.toString().split ','
    bridges.push new Bridge address, mac

  socket.on 'listening', ->
    socket.setBroadcast true
    data = Buffer.from 'HF-A11ASSISTHREAD'
    socket.send data, 0, data.length, 48899, '255.255.255.255'
    setTimeout done, 1000

  socket.bind()


module.exports = {Bridge, Commands}
module.exports.discover = Bridge.discover # convenience
