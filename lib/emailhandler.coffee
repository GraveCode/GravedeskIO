# required modules
{EventEmitter} = require "events" 
async = require "async"
marked = require "marked"
sanitizer = require "sanitizer"
{toMarkdown} = require "to-markdown"
contextio = require "contextio"


class EmailHandler extends EventEmitter
	constructor: (@joint, @settings) ->
		# define context IO client 
		@ctxioClient = new contextio.Client '2.0', 
			key: @settings.contextIO.key 
			secret: @settings.contextIO.secret
		# variables for contextIO account
		@ctxioID = ""
		@ctxioemail = ""
		# starting timestamp
		@timestamp = 1
		## control flow
		# call sync and trigger a full mailbox check when ID retrieved
		@on "getIDSuccess", @_sync
		@on "getIDSuccess", @_listMessages
		# call sync when prompted by timeout
		@on "doSync", @_sync
		# call list when prompted by timeout
		@on "doList", @_listMessages
		# after messages listed, check to see which are unread
		@on "listMessagesSuccess", @_filterNewMessages
		# filtered list of new messages found, ask to be flagged and processed
		@on "filterNewMessagesSuccess", @_checkNewMessages
		# marked as read ok, now get message
		@on "flagMessageSuccess", @_getMessage
		# message read ok, now get any attachments
		@on "getMessageSuccess", @_getMessageAttachments
		# attachments retrieved, now process
		@on "getMessageAttachmentsSuccess", @_processMessage 
		# message pared down to only required info, hand off to create ticket
		@on "processMessageSuccess", @joint.emailToTicket


	# PUBLIC FUNCTIONS
	getID: (callback) =>
		self = @
		self.ctxioemail = self.settings.contextIO.email
		self.ctxioClient.accounts().get
			email: self.ctxioemail
			status_ok: 1
		, (err, response) ->
			if err 
				callback err
			else 
				if response.body?.length > 0
					self.ctxioID = response.body[0].id 
					self.emit "getIDSuccess", self.ctxioID
					callback null
				else
					callback "Working ContextIO ID for " + self.ctxioemail + " could not be found."
	
	
	flagMessage: (msgid) =>
		self = @
		# first, we flag as read to stop duplicate attempts on the same message
		self.ctxioClient.accounts(self.ctxioID).messages(msgid).flags().post
			seen: 1
		, (err, response) ->
			if err or !response.body.success
				self.emit "flagMessageError", err
				console.log err
				console.log response
			else
				self.emit "flagMessageSuccess", msgid
	
	
	# INTERNAL FUNCTIONS

	_sync: =>
		self = @
		# after 1 minute trigger the next sync
		setTimeout (->
			self.emit "doSync"
		), (60 * 1000)	

		# tell contextio to sync all mail records for account
		self.ctxioClient.accounts(self.ctxioID).sync().post (err, response) ->
			if err
				console.log err
				console.log response
				self.emit "SyncFailure", self.ctxioID
			self.emit "SyncSuccess" unless err

	_listMessages: =>
		self = @
		# after 10 minutes trigger the next full list check - this is just belt and braces 
		# the webhook should notify us of new messages as they occur
		setTimeout (->
			self.emit "doList"
		), (10 * 60 * 1000)	
		# get list of recent messages in inbox
		self.ctxioClient.accounts(self.ctxioID).messages().get
			"folder": self.settings.contextIO.inbox
			"indexed_after": self.timestamp
		, (err, response) ->
			if err
				console.log err
				console.log response
				self.emit "listMessagesError", "unable to find new messages: " + err
			else
				self.emit "listMessagesSuccess", response.body 

	_filterNewMessages: (list) =>
		self = @
		testIsRead = (msg, callback) ->
			# contextio doesn't save message flags, so each message will be checked against imap
			self.ctxioClient.accounts(self.ctxioID).messages(msg.message_id).flags().get (err, response) ->
				# in the event of an error, best to just ignore the message
				callback true if err
				# otherwise send back status of 'seen' flag 
				callback response.body.seen unless err

		async.reject list, testIsRead, (filteredlist) ->
			# results is now a list of unread message objects
			self.emit "filterNewMessagesSuccess", filteredlist

	_checkNewMessages: (list) =>
		self = @
		# for each new message, call to flag as read (and retrieve and process) on each message
		iterator = (msg, callback) ->
			self.flagMessage msg.message_id
			callback null
		async.forEach list, iterator, (err) ->
			self.emit "checkNewMessagesError" if err

	_getMessage: (msgid) =>
		self = @
		# retrieve email message context from contextio, with body retrieved on our behalf
		self.ctxioClient.accounts(self.ctxioID).messages(msgid).get
			include_body: 1
		, (err, response) ->
			if err 
				self.emit "getMessageError", err, msgid, response.body
			else
				# update timestamp to latest message indexed
				if self.timestamp < response.body.date_indexed
					self.timestamp = response.body.date_indexed
				self.emit "getMessageSuccess", msgid, response.body

	_getMessageAttachments: (msgid, msg) =>
		self = @
		retrieveFile = (fileHeader, callback) ->
			self.ctxioClient.accounts(self.ctxioID).files(fileHeader.file_id).content().get (err, filecontent) ->
				if err
					callback err
				else
					file = 
						"name": fileHeader.file_name
						"Content-Type": fileHeader.type
						"body": filecontent.body
					callback null, file

		if msg?.files
			async.mapSeries msg.files, retrieveFile, (err, results) ->
				if err 
					self.emit "getMessageAttachmentsError", err, msgid
				else
					self.emit "getMessageAttachmentsSuccess", msgid, msg, results
		else self.emit "getMessageAttachmentsSuccess", msgid, msg, []

	_processMessage: (msgid, msg, files) =>
		checkbodytype = (obj) ->
			if obj.type is "text/plain"
				form.text += obj.content
			else if obj.type is "text/html"
				form.html += obj.content
			return null

		self = @
		form = 
			email: msg.addresses.from?.email or null
			name: msg.addresses.from?.name or null
			subject: msg?.subject or null
			priority: 1
			team: 0
			text: ""
			html: ""
		
		attachments = files or []

		checkbodytype obj for obj in msg.body
		self.emit "processMessageSuccess", msgid, form, attachments


	###
	_moveMessage: (msgid, destination) ->
		ctxioClient.accounts(@ctxioID).messages(msgid).post
			dst_folder: destination
			move: 1
		, (err, response) =>
			if err 
				@emit "moveMessageError", err
			else
				# TODO - gmail leaves message in inbox, need to force it
				@emit "moveMessageSuccess", msgid


	_autoReply: (id, isNew) ->
		outmail = {}
		tickethandler.findById id, (err, ticket) =>
			if err
				@emit "autoReplyError", err, id
			else		
				outmail.to = ticket.from
				if isNew
					outmail.subject = "RE: " + ticket.subject + " - " + lang.newAutoReply.subject + " - ID: <" + id + ">"
					outmail.html = "<html><header></header><body>"+lang.newAutoReply.body + ticket.description + "</body></html>"
				else
					outmail.subject = "RE: " + ticket.subject + " - " + lang.existingAutoReply.subject + " - ID: <" + id + ">"	
					outmail.html = "<html><header></header><body>" + lang.existingAutoReply.body + "</body></html>"				
				@emit "sendMail", outmail, id
	###

module.exports = EmailHandler