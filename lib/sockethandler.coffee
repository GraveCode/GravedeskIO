# required modules
{EventEmitter} = require "events" 
async = require "async"
marked = require "marked"
{toMarkdown} = require "to-markdown"
util = require "util"

marked.setOptions(
	gfm: true
	breaks: true
	smartypants: true
	sanitize: true
)

class SocketHandler extends EventEmitter
	constructor: (@socket, @db, @joint, @lang, @settings) ->
		@user = @socket?.handshake?.user
		@socket.on 'getStatics', @getStatics
		@socket.on 'getMyTickets', @getMyTickets
		@socket.on 'getAllTickets', @getAllTickets
		@socket.on 'getTicketCounts', @getTicketCounts
		@socket.on 'getTicketPages', @getTicketPages
		@socket.on 'getMessages', @getMessages
		@socket.on 'addTicket', @joint.addTicket
		@socket.on 'addMessage', @joint.addMessage
		@socket.on 'closeWithEmail', @joint.closeWithEmail
		@socket.on 'updateTicket', @updateTicket
		@socket.on 'deleteTicket', @deleteTicket
		@socket.on 'updateMessage', @updateMessage
		@socket.on 'deleteMessage', @deleteMessage
		@socket.on 'bulkDelete', @bulkDelete

	isAdmin: =>
		i = @settings.admins.indexOf @user?.emails[0]?.value
		if i >= 0
			return true
		else
			return false	

	isTech: =>
		i = @settings.techs.indexOf @user?.emails[0]?.value
		if i >= 0
			return true
		else
			return false

	getStatics: (callback) =>
		# clone groups
		groups = @settings.groups.slice(0)
		# add standard 'private tickets' group to defined group list
		groups.unshift @lang.privategroup
		statics = 
			isAdmin: @isAdmin()
			isTech: @isTech()
			statuses: @lang.statuses
			groups: groups
		callback null, statics


	getMyTickets: (user, callback) =>

		@db.view 'tickets/byuser', { descending: true, endkey: [user], startkey: [user,{}] } , (err, results) ->
			if err
				callback err
			else
				# split tickets into open and closed tickets
				open = []
				closed = []
				length = results.length
				element = null
				i = 0
	
				while i < length
					element = results[i]
					closed.push element.value if element.value.closed
					open.push element.value unless element.value.closed
					i++

				callback null, open, closed


	getAllTickets: (group, type, pagesize, start, callback) =>
		self = @
		if pagesize and typeof(pagesize) is "number"
			limit = pagesize
		else
			limit = 1000

		unwrapObject = (item) ->
			return item

		async.waterfall([
			(cb) ->
				# authentication check
				if self.isAdmin() or self.isTech()
					cb null
				else
					cb "Not authorized to retrieve all tickets!"

			, (cb) ->
				self._getKeys group, type, cb

			, (startkey, endkey, view, cb) ->	

				# override startkey if defined
				if start and util.isArray(start)
					startkey = start	
				self.db.view view, { reduce: false, descending: true, endkey: endkey, startkey: startkey, limit: limit } , cb

			, (results, cb) ->
					# strip id/key headers
					cleanTickets = results.map unwrapObject
					cb null, cleanTickets

			], (err, results) ->
				if err
					console.log err
					callback "Unable to retrieve tickets."
				else
					callback null, results
			)

	getTicketPages: (limit, length, group, type, callback) =>
		self = @
		if length and limit and typeof(length) is "number" and typeof(limit) is "number"
			numOfPages = Math.ceil (length/limit)
			async.waterfall([
				(cb) ->
					self._getKeys group, type, cb	
	
				, (startkey, endkey, view, cb) ->
					count = numOfPages
					result = [startkey]
					if count <= 1
						cb null, result
					else
						iterator = (start) ->
							self.db.view view, { reduce:false, descending: true, endkey: endkey, startkey: start, limit: 1, skip: limit }, (err, res) ->
								if err 
									cb err
								else if res.length > 0
									key = res[0]?.key
									result.push key
									count = count - 1
									if count <= 1
										cb null, result
									else
										iterator key
								else
									cb null
	
						iterator startkey

			], callback)
			
		else
			callback "invalid limit or length"


	_getKeys: (group, type, callback) =>
		self = @
		# generic startkeys
		if group == 0 and type == 0
			startkey = [self.user.emails[0].value,{},{}]
			endkey = [self.user.emails[0].value]
			view = 'tickets/personalopen'
		else if group == 0 and type == 1
			startkey = [self.user.emails[0].value,{}]
			endkey = [self.user.emails[0].value]
			view = 'tickets/personalclosed'
		else if type == 0
			startkey = [group,{},{}]
			endkey = [group]
			view = 'tickets/open'
		else if type == 1
			startkey = [group,{}]
			endkey = [group]
			view = 'tickets/closed'
		else
			callback "Unable to calculate keys - invalid type or group."	
		# 
		callback null, startkey, endkey, view	

	getTicketCounts: (type, callback) =>
		self = @
		async.waterfall([
			(cb) ->
				# authentication check
				if self.isAdmin() or self.isTech()
					cb null
				else
					cb "Not authorized to retrieve ticket counts!"

			, (cb) ->
				iterator = (group, nextcb) ->
					self._getKeys group, type, (err, startkey, endkey, view) ->
						if err
							nextcb err
						else
							self.db.view view, { group: false, reduce:true, descending: true, endkey: endkey, startkey: startkey }, (err, res) ->
								if err
									nextcb err
								else if res[0]?.value
									nextcb null, res[0].value
								else
									nextcb null, 0

				length = self.settings.groups.length
				if length > 0
					groups = (num for num in [0..length])
					async.map groups, iterator, cb
				else
					cb "invalid length"


		], callback)

			

	getMessages: (id, callback) =>
		self = @
		unwrapObject = (item) ->
			return item

		if id
			async.waterfall([
				(cb) ->
					self.db.get id, cb

				, (ticket, cb) ->
					# check if user is an owner of the ticket
					i = ticket.recipients.indexOf self.user.emails[0].value

					# if admin, show all messages
					if self.isAdmin() or self.isTech()
						self.db.view 'messages/all', { startkey: [id], endkey: [id, {}] }, (err, messages) ->
							cb err, ticket, messages

					# if owner of ticket only get public messages
					else if i >= 0
						self.db.view 'messages/public', {startkey: [id], endkey: [id, {}] }, (err, messages) ->
							cb err, ticket, messages

					# else access denied		
					else 
						cb "Denied Access"

			, (ticket, messages, cb) ->
				# clean messages cruft
				cleanMessages = messages.map unwrapObject
				cb null, ticket, cleanMessages

			], (err, ticket, messages) ->
				if err == "Denied Access"
					callback "Sorry, you've been denied access to this ticket. Please check you're logged in with the right account."
				else if err
					callback "Unable to find ticket with that ID: " + id
				else
					callback null, ticket, messages
			)

		else 
			callback "Error accessing ticket, invalid ID"

	updateTicket: (ticket, callback) =>
		self = @
		# make sure timestamp is in the past!
		timestamp = Date.now() - 1000
		if self.isAdmin() or self.isTech()
			ticket.modified = timestamp
			self.db.save ticket._id, ticket._rev, ticket, (err, res) ->
				if err
					console.log 'Unable to save ticket ' + ticket._id
					console.log err
					callback err, null
				else
					ticket._rev = res.rev
					self.socket.broadcast.emit 'ticketUpdated', ticket._id, ticket
					callback null, ticket
		else callback "Not authorized to update ticket!"

	deleteTicket: (ticket, callback) =>
		self = @
		async.waterfall([
			(cb) ->
				# authentication check
				if self.isAdmin()
					cb null
				else
					cb "Not authorized to delete tickets!"

			, (cb) -> 
				# get messages of ticket
				self.db.view 'messages/ids', { reduce: false, startkey: ticket.id, endkey: ticket.id }, cb

			, (messages, cb) ->
				if messages
					async.each messages, self.deleteMessage, (err) ->
						if err
							console.log 'Unable to delete message ' + message.id
							console.log err
							cb err
						else
							cb null
				else
					cb "No messages to delete!"

			, (cb) ->
				# once all messages deleted, we can now delete the ticket
				self.db.remove ticket.id, ticket.rev, (err, res) ->
				 	if err
				 		console.log 'Unable to delete ticket ' + ticket.id
				 		console.log err
				 		cb err
				 	else
				 		cb null, res
			], (err, res) ->
				if err
					callback err
				else
					self.socket.broadcast.emit('ticketDeleted', res.id)
					callback null
			)

	bulkDelete: (tickets, callback) =>
		self = @
		async.each tickets, self.deleteTicket, callback

	updateMessage: (message, restoreOrig, callback) =>
		self = @
		if self.isAdmin() or self.isTech()
			if restoreOrig
				cleantext = self.joint.cleanHTML message.rawtext
				cleanhtml = self.joint.cleanHTML message.rawhtml
				message.text = cleantext
				message.html = cleanhtml
			else
				cleantext = self.joint.cleanHTML message.text
				message.text = cleantext
				message.html = marked cleantext
			self.db.save message._id, message._rev, message, (err, res) ->
				if err
					console.log 'Unable to save message ' + message._id
					console.log err
					callback err
				else
					message._rev = res.rev
					self.socket.broadcast.emit 'messageUpdated', message.ticketid, message
					callback null, message
		else 
			callback "Not authorized to update message!"

	deleteMessage: (message, callback) =>
		self = @
		if message.id and message.rev
			self.db.remove message.id, message.rev, (err, res) ->
				self.socket.broadcast.emit('messageDeleted', res.id)
				callback err
		else
			callback "Unknown message ID or revision."

			

module.exports = SocketHandler
