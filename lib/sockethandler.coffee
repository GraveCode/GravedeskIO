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
	constructor: (@socket, @db, @settings) ->
		@user = @socket.handshake.user
		@socket.on 'isAdmin', (callback) => @isAdminCB callback
		@socket.on 'getMyTickets', (username, callback) => @getMyTickets username, callback	
		@socket.on 'getAllTickets', (group, type, callback) => @getAllTickets group, type, callback
		@socket.on 'getMessages', (id, callback) => @getMessages id, callback
		@socket.on 'addTicket', (formdata, callback) => @addTicket formdata, callback
		@socket.on 'addMessage', (message, names, callback) => @addMessage message, names, callback
		@socket.on 'updateTicket', (ticket, callback) => @updateTicket ticket, callback
		@socket.on 'deleteTicket', (ticket, callback) => @deleteTicket ticket, callback

	isAdmin: ->
		i = @settings.admins.indexOf @user?.emails[0]?.value
		if i >= 0
			return true
		else
			return false	

	isAdminCB: (callback) ->
		callback null, @isAdmin()

	getMyTickets: (user, callback) ->

		@db.view 'tickets/byuser', { descending: true, endkey: [[user]], startkey: [[user,{}],{}] } , (err, results) ->
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
				if self.isAdmin()
					cb null
				else
					cb "Not authorized to retrieve all tickets!"

			, (cb) ->
				if type == "open"
					self.db.view 'tickets/open', { descending: true, endkey: [group], startkey: [group,{},{}] } , cb
				else if type == "closed"
					self.db.view 'tickets/closed', { descending: true, endkey: [group], startkey: [group,{}] } , cb
				else
					cb "Unknown ticket type"

			], (err, results) ->
				if err
					callback err
				else
					# strip id/key headers
					cleanTickets = results.map unwrapObject
					callback null, cleanTickets
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
					if self.isAdmin()
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
					callback err
				else if err
					callback "Unable to find ticket with that ID: " + id
				else
					callback null, ticket, messages
			)

		else 
			callback "Error accessing ticket, invalid ID"

	addTicket: (data, callback) ->
		# make sure timestamp is in the past
		timestamp = Date.now() - 1000
		self = @
		nameObj = {}
		if data?.name
			nameObj[data.email] = data.name
		# Add proper name for server user
		nameObj[self.settings.serverEmail.email] = self.settings.serverEmail.name

		async.waterfall([
			(cb) -> 
				ticket = 
					type: 'ticket'
					created: timestamp
					modified: timestamp
					title: data.subject
					status: 0
					closed: false
					group: +data.team
					recipients: [data.email]
					names: nameObj
					priority: +data.priority

				# add ticket to db
				self.db.save ticket, (err, results) ->
					cb err, results, ticket

			, (results, ticket, cb) ->
				clean = self.cleanHTML data.description or ""
				message = 
					type: 'message'
					date: timestamp
					from: data.email
					private: false
					text: clean
					html: marked(clean)
					fromuser: true
					ticketid: results.id

				# add first message to db	
				self.db.save message, (err, res) ->
					cb err, results, ticket
					
		], (err, results, ticket) ->
				if err 
					msg = 'Unable to save ticket to database! '
					console.log msg + err
					callback msg
				else
					msg = 'Ticket added to system. '
					self.socket.broadcast.emit('ticketAdded', results.id, ticket)
					callback null, msg
		)

	addMessage: (message, names, callback) ->
		self = @
		# make sure timestamp is in the past! 
		timestamp = Date.now() - 1000
		clean = self.cleanHTML message.text
		message.text = clean
		message.html = marked(clean)
		message.type = 'message'
		message.date = timestamp

		async.waterfall([
			(cb) ->
				# save message to db
				self.db.save message, cb
			, (results, cb) ->
				self.socket.broadcast.emit('messageAdded', message.ticketid, message)
				# load related ticket
				self.db.get message.ticketid, cb
			, (ticket, cb) ->
				# update date, status and names of ticket
				for k,v of names
  				ticket.names[k] = v
				ticket.modified = timestamp
				if message.fromuser
					ticket.status = 0
				else if message.private
					ticket.status = 1
				else 
					ticket.status = 2
				self.db.save ticket._id, ticket._rev, ticket, (err, res) ->
					if err
						cb err
					else
						cb null, ticket, res

		], (err, ticket, result) ->
			if err
					console.log 'Unable to update ticket ' + ticket._id
					console.log err
					callback err
			else
				ticket._rev = result.rev
				self.socket.broadcast.emit('ticketUpdated', ticket._id, ticket)
				callback null, message, ticket
		)

	updateTicket: (ticket, callback) ->
		self = @
		# make sure timestamp is in the past!
		timestamp = Date.now() - 1000
		if self.isAdmin()
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

	deleteTicket: (ticket, callback) ->
		self = @
		async.waterfall([
			(cb) ->
				# authentication check
				if self.isAdmin()
					cb null
				else
					cb "Not authorized to delete tickets!"

			(cb) -> 
				# get messages of ticket
				self.db.view 'messages/ids', { startkey: ticket.id, endkey: ticket.id }, cb

			, (messages, cb) ->
				async.each(messages, self._deleteMessage, (err) ->
					if err
						console.log 'Unable to delete message ' + message.id
						console.log err
						cb err
					else
						cb null
				)

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
