# required modules
{EventEmitter} = require "events" 
async = require "async"
marked = require "marked"
bleach = require "bleach"

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
		@on "emailNewTicket", @_emailNewTicket
		@on "emailReply", @_emailReply		

	addMessage: (data, names, suppressSend, callback) =>
		self = @
		clean = self.cleanHTML(data.text) or "Error cleaning message text."
		message = 
			from: data.from
			private: data.private
			rawtext: data.text
			text: toMarkdown(clean)
			html: marked(clean)
			fromuser: data.fromuser
			ticketid: data.ticketid

		async.waterfall([
			(cb) ->
				# check we're under max messages count
				self._countMessages data.ticketid, cb

			, (cb) ->
				# save message to db
				self._createMessage message, cb

			, (results, message, cb) ->
				message._id = results.id
				message._rev = results.rev
				self.socket.emit('messageAdded', message.ticketid, message)

				self._updateTicket data.ticketid, names, message, (err, res, ticket) ->
					cb err, res, ticket, clean, message

		], (err, result, ticket, text, message) ->
			if err
					console.log 'Unable to add message. '
					console.log err
					callback err
			else
				ticket._rev = result.rev
				self.socket.emit('ticketUpdated', ticket._id, ticket)
				# local emit for autoreply
				if message.private or suppressSend or ticket.recipients.length < 1
					# ignore message
				else
					#self.emit 'autoReply', result.id, text, false, false, message
				callback null, result
		)

	addTicket: (data, callback) =>
		self = @
		async.waterfall([
			(cb) -> 
				nameObj = {}
				if data?.name
					nameObj[data.email] = data.name
				# Add proper name for server user
				nameObj[self.settings.serverEmail.email] = self.settings.serverEmail.name
			
				ticket = 
					title: data.subject or "No subject"
					group: +data.team
					recipients: [data.email] or null
					names: nameObj 
					priority: +data.priority
					personal: data.personal or null
				# add ticket to db
				self._createTicket ticket, cb

			, (results, final_ticket, cb) ->
				clean = self.cleanHTML(data.description) or "Error cleaning message text."
				message = 
					from: data.email
					private: false
					rawtext: data.description
					text: toMarkdown(clean)
					html: marked(clean)
					fromuser: true
					ticketid: results.id

				# add first message to db	
				self._createMessage message, (err, res, final_message) ->
					cb err, results, final_ticket, clean
					
		], (err, results, ticket, text) ->
			if err 
				msg = 'Unable to save ticket to database! '
				console.log msg + err
				callback msg
			else
				msg = 'Ticket added to system. '
				console.log msg + "ID: " + results.id
				# local emit for autoreply
				#self.emit 'autoReply', results.id, text, true, false, null
				# socket emit for web interface
				self.socket.emit 'ticketAdded', results.id, ticket
				callback null, msg
		)

	cleanHTML: (html) -> 
		clean = ""
		whitelist = ("font strong em b i p code pre tt samp kbd var sub q sup dfn cite big small address hr br div span h1 h2 h3 h4 h5 h6 ul ol li dl dt dd abbr acronym a img blockquote del ins table caption tbody tfoot thead tr th td article aside canvas details figcaption figure footer header hgroup menu nav section summary time mark").split(" ")
		options = 
			mode: 'white'
			list: whitelist

		try
			# remove unsafe tags
			clean = bleach.sanitize html, options
		catch
			console.log "error sanitizing html:"
			console.log clean
			return null
		finally
			return clean			

	closeWithEmail: (ticketid, message) =>
		self = @
		if message 
			message = self.cleanHTML(message)
		@emit 'autoReply', ticketid, message, false, true, null
	
	emailToTicket: (msgid, form, attachments) =>
		self = @
		# new ticket or reply?
		if form.subject
			searchstring = form.subject.match(/\<[a-z|A-Z|0-9]*\>/g) 
		else 
			searchstring = null
		if searchstring 
			# ticket ID like number found in subject, strip < and >
			substring = searchstring.pop().slice(1,-1)
			self.db.get substring, (err, results) ->
				if err
					# ticket not found, create as new
					self.emit 'emailNewTicket', msgid, form, attachments
				else
					# ticket with that id found
					if !results.closed
						# and ticket still open
						self.emit 'emailReply', msgid, results, form, attachments
					else
						# old ticket is closed, treat as new
						self.emit 'emailNewTicket', msgid, form, attachments
		else 
			# ticket ID number not found in subject, new ticket
			self.emit 'emailNewTicket', msgid, form, attachments





	_countMessages: (id, callback) =>
		self = @
		# count number of existing messages
		self.db.view 'messages/ids', { reduce: true, startkey: id, endkey: id }, (err, res) ->
			if err
				callback err
			else
				count = + res[0]?.value
				if count and count > self.settings?.maxMessages
					callback "Maximum number of allowed messages reached for ticket " + id + ", message ignored."
				else
					# message limit not reached
					callback null

	_createTicket: (ticket, callback) =>
		timestamp = Date.now() - 1000
		ticket.type = 'ticket'
		ticket.created = timestamp
		ticket.modified = timestamp
		ticket.status = 0
		ticket.closed = false
		@db.save ticket, (err, res) ->
			callback err, res, ticket

	_createMessage: (message, callback) =>
		timestamp = Date.now() - 1000
		message.type = 'message'
		message.date = timestamp

		@db.save message, (err, res) ->
			callback err, res, message

	_emailNewTicket: (msgid, data, attachments) =>
		self = @
		async.waterfall([
			(cb) ->
				nameObj = {}
				if data?.name
					nameObj[data.email] = data.name
					# Add proper name for server user
					nameObj[self.settings.serverEmail.email] = self.settings.serverEmail.name

				ticket = 
					title: "No subject"
					group: 1
					recipients: [data.email] or null
					names: nameObj 
					priority: 1
					personal: null
				# clean up old ID strings from subject, if any
				if data.subject
					ticket.title = data.subject.replace(/\- ID: \<[a-z|A-Z|0-9]*\>/g, "")
	
					# add ticket to db
				self._createTicket ticket, cb

			, (results, final_ticket, cb) ->
				cleantext = self.cleanHTML(data.rawtext) or null
				cleanhtml = self.cleanHTML(data.rawhtml) or null
				message = 
					from: data.email
					private: false
					rawtext: data.rawtext
					rawhtml: data.rawhtml
					text: cleantext or toMarkdown(cleanhtml)
					html: cleanhtml or marked(cleantext)
					ticketid: results.id
					fromuser: true

				# add first message to db	
				self._createMessage message, (err, res, final_message) ->
					cb err, results, final_ticket
					
			, (results, ticket, cb) ->
				msg = 'Ticket added to system. '
				console.log msg + "ID: " + results.id
				self.socket.emit 'ticketAdded', results.id, ticket
				# autoreply with message text

				# now add attachments to that ticket
				if attachments.length > 0
					self._emailTicketAttachments results, attachments, cb
				else
					# no attachments, we're done here
					cb null

		], (err, res) ->
			if err
				console.log "adding new ticket from email has failed."
				console.log err
			else
				self.emit "emailToTicketSuccess", msgid
		)

	_emailReply: (msgid, ticket, data, attachments) =>
		self = @
		# strip quoted lines we put in
		cleantext = self.cleanHTML(data.rawtext) or null
		cleantext = cleantext.replace(/^.*Please only type your reply above this line(.|\n|\r)*/m,'')	
		cleanhtml = self.cleanHTML(data.rawhtml) or null
		cleanhtml = cleanhtml.replace(/^.*Please only type your reply above this line(.|\n|\r)*/m,'')	
		message = 
			from: data.email
			private: false
			rawtext: data.rawtext
			rawhtml: data.rawhtml
			text: cleantext or toMarkdown(cleanhtml)
			html: cleanhtml or marked(cleantext)
			ticketid: ticket._id
			fromuser: true

		async.waterfall([
			(cb) ->
				# check we're under max message count
				self._countMessages ticket._id, cb

			, (cb) ->
				# add message
				self._createMessage message, cb

			, (results, final_message, cb) ->
				final_message._id = results.id
				final_message._rev = results.rev
				self.socket.emit('messageAdded', final_message.ticketid, final_message)
				# now add attachments to that ticket
				if attachments.length > 0
					console.log "adding attachments"
					self._emailTicketAttachments ticket, attachments, (err, res) ->
						cb err, res.id, final_message
				else 
					cb null, final_message.ticketid, final_message

			, (id, message, cb) ->
				self._updateTicket id, [], message, cb

		], (err, result, ticket) ->
			if err
				console.log "adding new email as reply message failed."
				console.log err
			else
				console.log "Message added from email."
				ticket._rev = result.rev
				self.socket.emit('ticketUpdated', ticket._id, ticket)
				self.emit "emailToTicketSuccess", msgid
		)
					
	_emailTicketAttachments: (ticket, attachments, cb) =>
		idData =
			id: ticket._id
			rev: ticket._rev
		self = @
		# remove the first attachment from array as record
		record = attachments.splice(0,1)[0]
		# setup recursive loop through attachments
		callback = (err, reply) ->
			if err
				# stop here
				console.log "Unable to save attachment!"
				console.log err
				cb err
			else if attachments.length == 0
				# we're done here
				cb null, idData
			else
				idData.rev = reply.rev
				record = attachments.splice(0,1)[0]
				# recursion, baby
				self.db.saveAttachment idData, record, callback
		# save first attachment					
		self.db.saveAttachment idData, record, callback

	_updateTicket: (id, names, message, callback) =>
		self = @
		self.db.get id, (err, ticket) ->
			if err 
				callback err
			else
				timestamp = Date.now() - 1000
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
					callback err, res, ticket


module.exports = Joint