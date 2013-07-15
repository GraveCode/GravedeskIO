# required modules
{EventEmitter} = require "events" 
async = require "async"
marked = require "marked"
sanitizer = require "sanitizer"

class SocketHandler extends EventEmitter
	constructor: (@socket, @db, @settings) ->
		@user = @socket.handshake.user
		@socket.on 'isAdmin', (callback) => @isAdmin callback
		@socket.on 'getMyTickets', (username, callback) => @getMyTickets username, callback	
		@socket.on 'getMessages', (id, callback) => @getMessages id, callback
		@socket.on 'addTicket', (formdata, callback) => @addTicket formdata, callback
		@socket.on 'addMessage', (message, callback) => @addMessage message, callback

	isAdmin: (callback) ->
		i = @settings.admins.indexOf @user.emails[0].value
		if i >= 0
			callback true
		else
			callback false

	getMyTickets: (user, callback) ->

		@db.view 'tickets/byuser', { descending: true, endkey: [[user]], startkey: [[user,{}],{}] } , (err, results) ->
			if !err
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
			else
				callback err

	getMessages: (id, callback) ->
		self = @
		unwrapObject = (item) ->
			return item

		if id
			async.waterfall([
				(cb) ->
					self.db.get id, cb

				, (ticket, cb) ->
					# check allowed access
					self.isAdmin (isAdmin) ->
						cb null, isAdmin, ticket

				, (isAdmin, ticket, cb) ->
					# check if user is an owner of the ticket
					i = ticket.recipients.indexOf self.user.emails[0].value

					# if admin, show all messages
					if isAdmin
						self.db.view 'messages/all', { startkey: [id], endkey: [id, {}] }, (err, messages) ->
							cb err, ticket, messages

					# if owner of ticket only get public messages
					else if i >= 0
						self.db.view 'messages/public', {startkey: [id], endkey: [id, {}] }, (err, messages) ->
							cb err, ticket, messages

					# else access denied		
					else 
						cb "Denied access"

			, (ticket, messages, cb) ->
				# clean messages cruft
				cleanMessages = messages.map unwrapObject
				cb null, ticket, cleanMessages

			], (err, ticket, messages) ->
				if err
					callback "Unable to retrieve ticket by that ID: " + id
				else
					callback null, ticket, messages
			)

		else 
			callback "Error accessing ticket, invalid ID"

	addTicket: (data, callback) ->
		timestamp = Date.now()
		self = @
		nameObj = {}
		if data?.name
			nameObj[data.email] = data.name

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

				self.db.save ticket, (err, results) ->
					cb err, results, ticket

			, (results, ticket, cb) ->
				nameObj[self.settings.serverEmail.email] = self.settings.serverEmail.name
				clean = self.stripHTML data.description or ""
				message = 
					type: 'message'
					date: timestamp
					from: data.email
					recipients: [self.settings.serverEmail.email]
					names: nameObj
					private: false
					text: clean
					html: marked(clean)
					fromuser: true
					ticketid: results.id
				self.db.save message, (err, res) ->
					cb err, results, ticket
					
		], (err, results, ticket) ->
				if err 
					msg = 'Unable to save ticket to database! '
					console.log msg + err
					callback msg
				else
					msg = 'Ticket added to system. '
					console.log msg + 'Ticket id: ' + results.id
					self.socket.broadcast.emit('ticketAdded', results.id, ticket)
					callback null, msg
		)

	addMessage: (message, callback) ->
		self = @
		timestamp = Date.now()
		clean = self.stripHTML message.text
		message.text = clean
		message.html = marked(clean)
		message.type = 'message'
		message.date = timestamp
		
		async.waterfall([
			(cb) ->
				# save message to db
				self.db.save message, cb
			(results, cb) ->
				console.log 'Message added, id: ' + results.id
				self.socket.broadcast.emit('messageAdded', message.ticketid, message)
				# load related ticket
				self.db.get message.ticketid, cb
			(ticket, cb) ->
				# update date and status of ticket
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
						cb null, ticket

		], (err, ticket) ->
			if err
				callback err
			else
				console.log 'Ticket ' + ticket._id + ' updated.'
				self.socket.broadcast.emit('ticketUpdated', ticket._id, ticket)
				callback null, message, ticket
		)


	stripHTML: (html) -> 
		clean = sanitizer.sanitize html, (str) ->
			return str

		# Remove all remaining HTML tags.
		clean = clean.replace(/<(?:.|\n)*?>/gm, "")

		# Return the final string, minus any leading/trailing whitespace.
		return clean.trim()

			

module.exports = SocketHandler
