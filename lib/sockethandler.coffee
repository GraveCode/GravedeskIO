# required modules
{EventEmitter} = require "events" 
async = require "async"
marked = require "marked"
sanitizer = require "sanitizer"
{toMarkdown} = require "to-markdown"

marked.setOptions(
	gfm: true
	breaks: true
	smartypants: true
	sanitize: true
)

class SocketHandler extends EventEmitter
	constructor: (@socket, @db, @joint, @settings) ->
		@user = @socket?.handshake?.user
		@socket.on 'isAdmin', (callback) => @isAdminCB callback
		@socket.on 'isTech', (callback) => @isTechCB callback
		@socket.on 'getMyTickets', (username, callback) => @getMyTickets username, callback	
		@socket.on 'getAllTickets', (group, type, callback) => @getAllTickets group, type, callback
		@socket.on 'getTicketCounts', (type, length, callback) => @getTicketCounts type, length, callback
		@socket.on 'getMessages', (id, callback) => @getMessages id, callback
		@socket.on 'addTicket', @joint.addTicket
		@socket.on 'addMessage', @joint.addMessage
		@socket.on 'closeWithEmail', @joint.closeWithEmail
		@socket.on 'updateTicket', (ticket, callback) => @updateTicket ticket, callback
		@socket.on 'deleteTicket', (ticket, callback) => @deleteTicket ticket, callback
		@socket.on 'bulkDelete', (tickets, callback) => @bulkDelete tickets, callback

	isAdmin: ->
		i = @settings.admins.indexOf @user?.emails[0]?.value
		if i >= 0
			return true
		else
			return false	

	isTech: ->
		i = @settings.techs.indexOf @user?.emails[0]?.value
		if i >= 0
			return true
		else
			return false

	isAdminCB: (callback) ->
		callback null, @isAdmin()

	isTechCB: (callback) ->
		callback null, @isTech()

	getMyTickets: (user, callback) ->

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


	getAllTickets: (group, type, callback) ->
		self = @
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

				if group == 0
					# personal tickets
					if type == 0
						self.db.view 'tickets/personalopen', { reduce: false, descending: true, endkey: [self.user.emails[0].value], startkey: [self.user.emails[0].value,{},{}] } , cb
					else if type == 1
						self.db.view 'tickets/personalclosed', { reduce: false, descending: true, endkey: [self.user.emails[0].value], startkey: [self.user.emails[0].value,{}] } , cb
					else
						cb "unknown ticket type"

				else
					# general tickets
					if type == 0
						self.db.view 'tickets/open', { reduce: false, descending: true, endkey: [group], startkey: [group,{},{}] } , cb
					else if type == 1
						self.db.view 'tickets/closed', { reduce: false, descending: true, endkey: [group], startkey: [group,{}] } , cb
					else
						cb "Unknown ticket type"

			, (results, cb) ->
					# strip id/key headers
					cleanTickets = results.map unwrapObject
					cb null, cleanTickets

			], (err, results) ->
				if err
					callback err
				else
					callback null, results
			)

	getTicketCounts: (type, length, callback) =>
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
					if group == 0
						# personal tickets
						if type == 0
							self.db.view 'tickets/personalopen', { group: false, reduce:true, descending: true, endkey: [self.user.emails[0].value], startkey: [self.user.emails[0].value,{},{}] }, (err, res) ->
								if err
									nextcb err
								else if res[0]?.value
									nextcb null, res[0].value
								else
									nextcb null, 0

						else if type == 1
							self.db.view 'tickets/personalclosed', {group: false, reduce: true, descending: true, endkey: [self.user.emails[0].value], startkey: [self.user.emails[0].value,{},{}] }, (err, res) ->
								if err
									nextcb err
								else if res[0]?.value
									nextcb null, res[0].value
								else
									nextcb null, 0

						else
							cb "Unknown ticket type"

					else 
						# general tickets
						if type == 0
							self.db.view 'tickets/open', { group: false, reduce:true, descending: true, endkey: [group], startkey: [group,{},{}] }, (err, res) ->
								if err
									nextcb err
								else if res[0]?.value
									nextcb null, res[0].value
								else
									nextcb null, 0

						else if type == 1
							self.db.view 'tickets/closed', {group: false, reduce: true, descending: true, endkey: [group], startkey: [group,{},{}] }, (err, res) ->
								if err
									nextcb err
								else if res[0]?.value
									nextcb null, res[0].value
								else
									nextcb null, 0
						else
							cb "Unknown ticket type"

				if length > 0
					groups = (num for num in [0..length-1])
					async.map groups, iterator, cb
				else
					cb "invalid length"


		], (err, results) ->
			callback err, results
		)

			

	getMessages: (id, callback) ->
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

	updateTicket: (ticket, callback) ->
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
					async.each messages, self._deleteMessage, (err) ->
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

	bulkDelete: (tickets, callback) ->
		self = @
		async.each tickets, self.deleteTicket, callback
			
	cleanHTML: (html) -> 
		# remove unsafe tags
		clean = sanitizer.sanitize html
		# convert safe tags to markdown
		clean = toMarkdown clean
		# Remove all remaining HTML tags.
		clean = clean.replace(/<(?:.|\n)*?>/gm, "")

		return clean

	_deleteMessage: (message, callback) =>
		self = @
		self.db.remove message.id, message.rev, callback

			

module.exports = SocketHandler
