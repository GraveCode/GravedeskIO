# required modules
{EventEmitter} = require "events" 
async = require "async"

class SocketHandler extends EventEmitter
	constructor: (@socket, @db, @settings) ->
		@user = @socket.handshake.user
		@socket.on 'isAdmin', (callback) => @isAdmin callback
		@socket.on 'getMyTickets', (username, callback) => @getMyTickets username, callback	
		@socket.on 'addTicket', (formdata, callback) => @addTicket formdata, callback

	isAdmin: (callback) ->
		if @settings.admins.indexOf @user.emails[0].value >= 0
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
					closed.push element if element.value.closed
					open.push element unless element.value.closed
					i++
				callback null, open, closed
			else
				callback err

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
