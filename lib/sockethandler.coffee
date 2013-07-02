# required modules
{EventEmitter} = require "events" 
async = require "async"

class SocketHandler extends EventEmitter
	constructor: (@socket, @db, @settings) ->
		@user = @socket.handshake.user
		@socket.on 'isAdmin', (callback) => @isAdmin callback
		@socket.on 'getMyTickets', (username, callback) => @getMyTickets username, callback	
		@socket.on 'getMessages', (id, callback) => @getMessages id, callback
		@socket.on 'addTicket', (formdata, callback) => @addTicket formdata, callback

	isAdmin: (callback) ->
		i = @settings.admins.indexOf @user.emails[0].value
		if i >= 0
			callback true
		else
			callback false

	getMyTickets: (user, callback) ->

		@db.view 'tickets/mine', { descending: true, endkey: [[user]], startkey: [[user,{}],{}] } , (err, results) ->
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
		


	addTicket: (formdata, callback) ->
		timestamp = Date.now()
		self = @
		async.waterfall([
			(cb) -> 
				ticket = 
					type: 'ticket'
					created: timestamp
					modified: timestamp
					title: formdata.subject
					status: 0
					closed: false
					group: +formdata.team
					recipients: [formdata.from]
				self.db.save ticket, (err, results) ->
					cb err, results, ticket

			, (results, ticket, cb) ->
				message = 
					type: 'message'
					date: timestamp
					from: formdata.from
					to: self.settings.serverEmail
					private: false
					body: formdata.description
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
		 	

module.exports = SocketHandler
