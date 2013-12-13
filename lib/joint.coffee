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
		# on email to be added as newticket
		@on "doNewTicket", @_doNewTicket
		@on "doNewReply", @_doNewReply		

	closeWithEmail: (ticketid, message) =>
		self = @
		if message 
			message = self.cleanHTML(message)
		@emit 'autoReply', ticketid, message, false, true, null

	emailToTicket: (msgid, form, attachments) =>
		self = @
		form.description = form.html or form.text or ""
		# strip quoted lines we put in
		form.description = form.description.replace(/^.*PLEASE ONLY REPLY ABOVE THIS LINE(.|\n|\r)*/m,'')	
		# new ticket or reply?
		searchstring = form.subject.match(/\<[a-z|A-Z|0-9]*\>/g) 
		if searchstring 
			# ticket ID like number found in subject, strip < and >
			substring = searchstring.pop().slice(1,-1)
			self.db.get substring, (err, results) ->
				if err
					# ticket not found, create as new
					self.emit 'doNewTicket', msgid, form, attachments
				else
					# ticket with that id found
					if !results.closed
						# and ticket still open
						self.emit 'doNewReply', msgid, results, form, attachments
					else
						# old ticket is closed, treat as new
						self.emit 'doNewTicket', msgid, form, attachments
		else 
			# ticket ID number not found in subject, new ticket
			self.emit 'doNewTicket', msgid, form, attachments

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
					personal: null

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
					self.emit 'autoReply', results.id, text, true, false, null
					# socket emit for web interface
					self.socket.emit 'ticketAdded', results.id, ticket
					callback null, msg, results
		)

	addMessage: (message, names, suppressSend, callback) =>
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
				# count number of existing messages
				self.db.view 'messages/ids', { reduce: true, startkey: message.ticketid, endkey: message.ticketid }, cb

			, (res, cb) ->
				count = res[0]?.value
				if count and count > self.settings?.maxMessages
					cb "Maximum number of allowed messages reached for ticket " + message.ticketid + ", message ignored."

				else
					# message limit not reached

					cb null

			, (cb) ->
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
					console.log 'Unable to add message. '
					console.log err
					callback err
			else
				ticket._rev = result.rev
				# local emit for autoreply
				if message.private or suppressSend or ticket.recipients.length < 1
					# ignore message
				else
					self.emit 'autoReply', result.id, text, false, false, message
				self.socket.emit('ticketUpdated', ticket._id, ticket)
				callback null, result
		)

	cleanHTML: (html) -> 
		# remove unsafe tags
		clean = sanitizer.sanitize html
		# remove img tags in body (thanks, osx mail)
		clean = clean.replace(/<img[^>]+\>/i, "")		
		# convert safe tags to markdown
		clean = toMarkdown clean
		# Remove all remaining HTML tags.
		clean = clean.replace(/<(?:.|\n)*?>/gm, "")

		return clean



	_doNewReply: (msgid, ticket, form, attachments) =>
		# strip extra quote lines
		form.description = form.description.replace(/^.*On(.|\n|\r)*wrote:/m,'')
		form.description = form.description.replace(/^\>(.*)/gm, '')

		self = @
		message = 
			from: form.email
			private: false
			text: form.description
			fromuser: true
			ticketid: ticket._id

		# add email sender name
		names = ticket?.names or {}
		names[form.email] = form.name

		async.waterfall([
			(cb) ->
				# first add message
				self.addMessage message, names, cb

			(results, cb) ->
				# now add attachments to that ticket
				if attachments.length > 0
					console.log "adding attachments, wooo"
					# remove the first attachment from array as record
					record = attachments.splice(0,1)[0]
					idData = 
						id: results.id
						rev: results.rev

					# setup recursive loop through attachments
					callback = (err, reply) ->
						if err
							# stop here
							console.log "Unable to save attachment!"
							console.log err
							cb err
						else if attachments.length == 0
							# we're done here
							cb null
						else
							idData.rev = reply.rev
							record = attachments.splice(0,1)[0]
							# recursion, baby
							self.db.saveAttachment idData, record, callback

					# save first attachment					
					self.db.saveAttachment idData, record, callback

				else
					# no attachments, we're done here
					cb null

		], (err) ->
			if err
				console.log "adding new email as reply message failed."
				console.log err
			else
				self.emit "emailToTicketSuccess", msgid
		)


	_doNewTicket: (msgid, form, attachments) =>
		self = @
		# clean up old ID strings from subject, if any
		form.subject = form.subject.replace(/\- ID: \<[a-z|A-Z|0-9]*\>/g, "")

		async.waterfall([
			(cb) ->
				# first add ticket
				self.addTicket form, cb

			(msg, results, cb) ->
				# now add attachments to that ticket
				if attachments.length > 0
					# remove the first attachment from array as record
					record = attachments.splice(0,1)[0]
					idData = 
						id: results.id
						rev: results.rev

					# setup recursive loop through attachments
					callback = (err, reply) ->
						if err
							# stop here
							console.log "Unable to save attachment!"
							console.log err
							cb err
						else if attachments.length == 0
							# we're done here
							cb null
						else
							idData.rev = reply.rev
							record = attachments.splice(0,1)[0]
							# recursion, baby
							self.db.saveAttachment idData, record, callback

					# save first attachment					
					self.db.saveAttachment idData, record, callback

				else
					# no attachments, we're done here
					cb null

		], (err) ->
			if err
				console.log "adding new email as ticket failed."
				console.log err
			else
				self.emit "emailToTicketSuccess", msgid
		)
					



module.exports = Joint