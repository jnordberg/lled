### Interface for the LimitlessLED WiFi bridge v5. ###

###

  NOTICE: Deprecated code. Kept here for reference only.
          I could never get the v5 bridges to work reliably so not going to
          make an effort supporting them in this module.

###

async = require 'async'
dgram = require 'dgram'

noop = ->

class Bridge

  GROUP_COMMANDS = [
    {ON: 0x42, OFF: 0x41, WHITE: 0xC2} # all
    {ON: 0x45, OFF: 0x46, WHITE: 0xC5} # group 1
    {ON: 0x47, OFF: 0x48, WHITE: 0xC7} # group 2
    {ON: 0x49, OFF: 0x4A, WHITE: 0xC9} # group 3
    {ON: 0x4B, OFF: 0x4C, WHITE: 0xCB} # group 4
  ]

  constructor: (@address, @mac='N/A') ->
    @socket = dgram.createSocket 'udp4'
    @busy = false
    @repeatCount = 5
    @retryTimeout = 50

  send: (data, callback) ->
    send = (n, callback) =>
      @socket.send data, 0, data.length, 8899, @address, callback
    async.timesSeries @repeatCount, send, callback

  turnOn: (group, callback) ->
    ### Turn on lamp *group*. ###
    if @busy
      setTimeout @turnOn.bind(this), @retryTimeout, group, callback
      return
    @busy = true
    data = new Buffer [GROUP_COMMANDS[group].ON, 0x00]
    @send data, (error) =>
      @busy = false
      unless error?
        @activeGroup = group
      callback error

  turnOff: (group, callback) ->
    ### Turn off lamp *group*. ###
    if @busy
      setTimeout @turnOff.bind(this), @retryTimeout, group, callback
      return
    @busy = true
    data = new Buffer [GROUP_COMMANDS[group].OFF, 0x00]
    @send data, (error) =>
      @busy = false
      @activeGroup = null
      callback error

  activateGroup: (group, callback) ->
    if @activeGroup is group
      do callback
    else
      data = new Buffer [GROUP_COMMANDS[group].ON, 0x00]
      @send data, (error) =>
        if error?
          callback error
        else
          @activeGroup = group
          setTimeout callback, 50

  setBrightness: (group, brightness, callback) ->
    ### Set *brightness* for lamp *group* expressed as a number between 1 and 100. ###
    if @busy
      setTimeout @setBrightness.bind(this), @retryTimeout, group, brightness, callback
      return
    @busy = true
    b = 2 + Math.round ((brightness - 1) / 99) * 25
    data = new Buffer [0x4E, b]
    flow = [
      (callback) => @activateGroup group, callback
      (callback) => @send data, callback
    ]
    async.series flow, (error) =>
      @busy = false
      callback error

  setHue: (group, hue, callback) ->
    ### Set lamp *group* to *hue* expressed as a number between 0 and 359. ###
    if @busy
      setTimeout @setHue.bind(this), @retryTimeout, group, hue, callback
      return
    @busy = true
    h = Math.round (((1.0 - (hue / 359)) * 255) - 85) % 256
    data = new Buffer [0x40, h]
    flow = [
      (callback) => @activateGroup group, callback
      (callback) => @send data, callback
    ]
    async.series flow, (error) =>
      @busy = false
      callback error

  setWhite: (group, callback) ->
    ### Set lamp *group* to white light. ###
    if @busy
      setTimeout @setWhite.bind(this), @retryTimeout, group, callback
      return
    @busy = true
    data = new Buffer [GROUP_COMMANDS[group].WHITE, 0x00]
    @send data, (error) =>
      @busy = false
      callback error

  setHSL: (group, hue, saturation, brightness, callback=noop) ->
    if @busy
      setTimeout @setHSL.bind(this), @retryTimeout, group, hue, saturation, brightness, callback
      return
    flow = []
    if brightness < 1
      # turn light off
      @turnOff group, callback
      return
    if saturation < 10 # the rgbw lights does not have any saturation control, use white light below treshold
      flow.push (callback) => @setWhite group, callback
    else
      flow.push (callback) => @setHue group, hue, callback
    flow.push (callback) => @setBrightness group, brightness, callback
    async.series flow, callback


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
    data = Buffer.from 'Link_Wi-Fi'
    socket.send data, 0, data.length, 48899, '255.255.255.255'
    setTimeout done, 1000

  socket.bind()


module.exports = Bridge
