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

class Joint extends EventEmitter
	constructor: (@socket, @db, @settings) ->

	emailToTicket: (msgid, form, attachments) =>
		self = @
		# assume all emails are new tickets!
		form.description = form.html or form.text or ""

		# first add ticket
		self.addTicket form, (err, msg, results) ->
			if err
				console.log "Unable to save ticket."
			else
				# now add attachments to that ticket
				if attachments.length > 0
					# remove the first attachment from array as record
					record = attachments.splice(0,1)[0]
					idData = 
						id: results.id
						rev: results.rev

					callback = (err, reply) ->
						if err
							console.log "Unable to save attachment!"
							console.log err
						else if attachments.length == 0
							# we're done here
							self.emit "emailToTicketSuccess", msgid
							return
						else
							idData.rev = reply.rev
							record = attachments.splice(0,1)[0]
							# recursion, baby
							self.db.saveAttachment idData, record, callback

					# save first attachment					
					self.db.saveAttachment idData, record, callback

				else
					# we're done here
					self.emit "emailToTicketSuccess", msgid

	addTicket: (data, callback) =>
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
				clean = self.cleanHTML(data.description) or ""
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
					cb err, results, ticket, clean
					
		], (err, results, ticket, text) ->
				if err 
					msg = 'Unable to save ticket to database! '
					console.log msg + err
					callback msg
				else
					msg = ' Ticket added to system. '
					# local emit for autoreply
					console.log results.id + msg
					self.emit 'autoReply', results.id, text, true, null
					# socket emit for web interface
					self.socket.emit 'ticketAdded', results.id, ticket
					callback null, msg, results
		)

	addMessage: (message, names, callback) =>
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
				self.socket.emit('messageAdded', message.ticketid, message)
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
						cb null, ticket, res, clean, message

		], (err, ticket, result, text, message) ->
			if err
					console.log 'Unable to update ticket ' + ticket._id
					console.log err
					callback err
			else
				ticket._rev = result.rev
				# local emit for autoreply
				if !message.private
					self.emit 'autoReply', result.id, text, false, message
				self.socket.emit('ticketUpdated', ticket._id, ticket)
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



module.exports = Joint