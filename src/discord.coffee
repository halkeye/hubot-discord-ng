# Description:
#   Adapter for Hubot to communicate on Discord
#
# Commands:
#   None
#
# Configuration:
#   HUBOT_MAX_MESSAGE_LENGTH - maximum allowable message length (defaults to 2000, discord's default)
#   HUBOT_DISCORD_EMAIL - authentication email for bot account (optional)
#   HUBOT_DISCORD_PASSWORD - authentication password for bot account (optional)
#   HUBOT_DISCORD_TOKEN - authentication token for bot
#   HUBOT_DISCORD_STATUS_MSG - Status message to set for "currently playing game"
#

try
	{Robot, Adapter, EnterMessage, LeaveMessage, TopicMessage, TextMessage}  = require 'hubot'
catch
	prequire = require( 'parent-require' )
	{Robot, Adapter, EnterMessage, LeaveMessage, TopicMessage, TextMessage}  = prequire 'hubot'
Discord = require 'discord.js'
util = require 'util'

maxLength = parseInt process.env.HUBOT_MAX_MESSAGE_LENGTH || 2000
currentlyPlaying = process.env.HUBOT_DISCORD_STATUS_MSG || ''

class DiscordBot extends Adapter
	constructor: (@robot) ->
		super
		@rooms = {}
		@direct_rooms = {}

	run: =>
		@options =
			email: process.env.HUBOT_DISCORD_EMAIL,
			password: process.env.HUBOT_DISCORD_PASSWORD,
			token: process.env.HUBOT_DISCORD_TOKEN

		@client = new Discord.Client {forceFetchUsers: true, autoReconnect: true}
		@client.on 'ready', @ready
		@client.on 'message', @message
		@client.on 'error', @error
		@client.on 'debug', @debug
		@client.on 'warn', @warn
		@client.on 'disconnected', @disconnected

		if @options.token?
			@client.loginWithToken @options.token, @options.email, @options.password, (err) ->
				@robot.logger.error err
		else
			@client.login @options.email, @options.password, (err) ->
				@robot.logger.error err

	ready: =>
		@robot.logger.info "Logged in: #{@client.user.username}"
		@robot.name = @client.user.username.toLowerCase()
		@robot.logger.info "Robot Name: #{@robot.name}"
		@emit 'connected'

		# post-connect actions
		@rooms[channel.id] = channel for channel in @client.channels
		@client.setStatus 'here', currentlyPlaying, (err) ->
			@robot.logger.error err

	message: (message) =>
		# ignore messages from myself
		return if message.author.id is @client.user.id

		user = @robot.brain.userForId message.author.id
		user.room = message.channel.id
		user.name = message.author.name
		user.id = message.author.id
		user.message = message

		text = message.cleanContent

		if message.channel instanceof Discord.PMChannel
			@robot.logger.debug 'Message channel is PM, prepending bot name for matching purposes.'
			text = "#{@robot.name}: #{text}" if not text.match new RegExp( "^@?#{@robot.name}" )

		@robot.logger.debug text
		@receive new TextMessage( user, text, message.id )

	chunkMessage: (msg) ->
		subMessages = []
		if msg.length > maxLength
			while msg.length > 0
				# Split message at last line break, if it exists
				chunk = msg.substring 0, maxLength
				breakIndex = if chunk.lastIndexOf('\n') isnt -1 then chunk.lastIndexOf('\n') else maxLength
				subMessages.push msg.substring 0, breakIndex
				# Skip char if split on line break
				breakIndex++ if breakIndex isnt maxLength
				msg = msg.substring breakIndex, msg.length
		else subMessages.push msg
		return subMessages

	send: (envelope, messages...) ->
		@robot.logger.debug "sending a message. envelope is:\n#{util.inspect envelope}"
		# TODO: figure out a way to discriminate between basic sends and sends to someone specific or w/e
		@robot.logger.debug "About to send message '#{messages[0]}' to #{envelope.user.name} at #{envelope.user.message.channel.name}" if messages[0]?
		if messages.length > 0
			message = messages.shift()
			chunkedMessage = @chunkMessage message
			if chunkedMessage.length > 0
				chunk = chunkedMessage.shift()
				@client.sendMessage envelope.user.message, chunk, (err) =>
					remainingMessages = chunkedMessage.concat messages
					if err then @robot.logger.error err
					@send envelope, remainingMessages...

	reply: (envelope, messages...) =>
		@robot.logger.debug "Replying to #{envelope.user.name} in channel #{envelope.user.message.channel.name}"
		for msg in messages
			@client.reply envelope.user.message, msg, (err) ->
				@robot.logger.error err

	debug: (log) =>
		@robot.logger.debug "(discord.js) #{log}"

	warn: (message) =>
		@robot.logger.warning "(discord.js) #{message}"

	error: (error) =>
		@robot.logger.error "(discord.js) #{error}"

	disconnected: (message) =>
		@robot.logger.warning "Disconnected from server. #{message}"

exports.use = (robot) ->
	new DiscordBot robot
