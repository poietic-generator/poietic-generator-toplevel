# -*- coding: utf-8 -*-
##############################################################################
#                                                                            #
#  Poietic Generator Reloaded is a multiplayer and collaborative art         #
#  experience.                                                               #
#                                                                            #
#  Copyright (C) 2011-2013 - Gnuside                                         #
#                                                                            #
#  This program is free software: you can redistribute it and/or modify it   #
#  under the terms of the GNU Affero General Public License as published by  #
#  the Free Software Foundation, either version 3 of the License, or (at     #
#  your option) any later version.                                           #
#                                                                            #
#  This program is distributed in the hope that it will be useful, but       #
#  WITHOUT ANY WARRANTY; without even the implied warranty of                #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Affero  #
#  General Public License for more details.                                  #
#                                                                            #
#  You should have received a copy of the GNU Affero General Public License  #
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.     #
#                                                                            #
##############################################################################

require 'thread'
require 'time'
require 'pp'

require 'poieticgen/board'
require 'poieticgen/zone'
require 'poieticgen/palette'
require 'poieticgen/user'
require 'poieticgen/event'
require 'poieticgen/chat_manager'
require 'poieticgen/message'
require 'poieticgen/stroke'
require 'poieticgen/timeline'
require 'poieticgen/update_request'
require 'poieticgen/snapshot_request'
require 'poieticgen/play_request'
require 'poieticgen/session'

module PoieticGen

	class InvalidSession < RuntimeError ; end
	class AdminSessionNeeded < RuntimeError ; end

	#
	# manage a pool of users
	#
	class Manager

		# This constant is the one used to check the leaved user, and generate
		# events. This check is made in the update_data method. It will be done
		# at least every LEAVE_CHECK_TIME_MIN days at a user update_data request.
		LEAVE_CHECK_TIME_MIN = 1

		def initialize config
			@config = config
			@debug = true
			pp config
			# a 16-char long random string

			_session_init
		end


		def restart session, params
			user_id = session[PoieticGen::Api::SESSION_USER]
			user = @session.users.get(user_id)
			
			raise InvalidSession, "No user found with user_id %d in DB" % user_id if user.nil?
			
			raise AdminSessionNeeded, "You have not the right to do that, please login as admin." if not user.is_admin
			
			_session_init
		end

		#
		# generates an unpredictible user id based on session id & user counter
		#
		def join session, params
			req_id = params[:user_id]
			req_session = params[:user_session]
			req_name = params[:user_name]

			is_new = true;
			result = nil


			# FIXME: prevent session from being stolen...
			pp "requesting id=%s, session=%s, name=%s" \
				% [ req_id, req_session, req_name ]

			user = nil
			now = Time.now

			param_name = if req_name.nil? or (req_name.length == 0) then
							 "anonymous"
						 else
							 req_name
						 end
			param_create = {
				:session => @session,
				:name => param_name,
				:zone => -1,
				:created_at => now.to_i,
				:alive_expires_at => (now + @config.user.liveness_timeout).to_i,
				:idle_expires_at => (now + @config.user.idle_timeout).to_i,
				:did_expire => false,
				:last_update_time => now
			}

			User.transaction do

				# reuse user_id if session is still valid
				if req_session != @session.token then
					pp "User is requesting a different session"
					# create new
					user = User.create param_create

					# allocate new zone
					@board.join user

				else
					pp "User is in session"
					param_request = {
						:id => req_id
					}

					user = @session.users.first_or_create param_request, param_create

					tdiff = (now.to_i - user.alive_expires_at)
					pp [ now.to_i, user.alive_expires_at, tdiff ]
					if ( tdiff > 0  ) then
						# The event will be generated elsewhere (in update_data).
						pp "User session expired"
						# create new if session expired
						user = User.create param_create

						@board.join user
					else
						is_new = false;
					end
				end

				# kill all previous users having the same zone

				# update expiration time
				user.idle_expires_at = (now + @config.user.idle_timeout)
				user.alive_expires_at = (now + @config.user.liveness_timeout)
				pp "Set expiring times at %s" % user.alive_expires_at.to_s

				# reset name if requested
				user.name = param_name

				begin
					user.save
				rescue DataMapper::SaveFailureError => e
					STDERR.puts e.resource.errors.inspect
					raise e
				end
				
				@session.users << user
				
				pp user
				session[PoieticGen::Api::SESSION_USER] = user.id
				session[PoieticGen::Api::SESSION_SESSION] = @session.token

				zone = @board[user.zone]

				# FIXME: test request user_id
				# FIXME: test request username

				# return JSON for userid
				if is_new then
					Event.create_join user.id, user.zone, @session
				end

				# clean-up users first
				self.check_expired_users

				# get real users
				users_db = @session.users.all(
					:did_expire.not => true,
					:id.not => user.id,
					:zone.gte => 0
				)
				other_users = users_db.map{ |u| u.to_hash }
				other_zones = users_db.map{ |u|
					puts "requesting zone for %s" % u.inspect
					@board[u.zone].to_desc_hash Zone::DESCRIPTION_FULL
				}
				msg_history_req = Message.all(:user_dst => user.id) + Message.all(:user_src => user.id)
				msg_history = msg_history_req.map{ |msg| msg.to_hash }
				pp "msg_history req : %s" % msg_history.inspect


				result = { :user_id => user.id,
					:user_session => user.session.token,
					:user_name => user.name,
					:user_zone => (zone.to_desc_hash Zone::DESCRIPTION_FULL),
					:other_users => other_users,
					:other_zones => other_zones,
					:zone_column_count => @config.board.width,
					:zone_line_count => @config.board.height,
					:timeline_id => (Timeline.last_id @session),
					:msg_history => msg_history
				}
			end

			rdebug "result : %s" % result.inspect
			pp result

			return result
		end
		
		def admin_join session, params
			req_name = params[:user_name]
			req_password = params[:user_password]

			# FIXME: prevent session from being stolen...
			pp "requesting name=%s" % req_name
			
			user = nil
			now = Time.now

			is_admin = if req_password.nil? or req_name.nil? then false
			           else req_password == @config.server.admin_password and
			                req_name == @config.server.admin_username
			           end
			
			raise AdminSessionNeeded, "Invalid parameters." if not is_admin
			
			param_create = {
				:session => @session,
				:name => req_name,
				:zone => -1,
				:created_at => now.to_i,
				:alive_expires_at => (now + @config.user.liveness_timeout).to_i,
				:idle_expires_at => (now + @config.user.idle_timeout).to_i,
				:did_expire => false,
				:last_update_time => now,
				:is_admin => is_admin
			}

			User.transaction do

				user = User.create param_create

				# kill all previous users having the same zone

				# update expiration time
				user.idle_expires_at = (now + @config.user.idle_timeout)
				user.alive_expires_at = (now + @config.user.liveness_timeout)
				pp "Set expiring times at %s" % user.alive_expires_at.to_s

				begin
					user.save
				rescue DataMapper::SaveFailureError => e
					STDERR.puts e.resource.errors.inspect
					raise e
				end
				
				session[PoieticGen::Api::SESSION_USER] = user.id
				session[PoieticGen::Api::SESSION_SESSION] = @session.token
				
				@session.users << user
			end
		end


		def leave session
			pp "FIXME: LEAVE(session)", session
			# zone_idx = @users[user_id].zone

			session_user_id = session[PoieticGen::Api::SESSION_USER]
			session_token = session[PoieticGen::Api::SESSION_SESSION]
			
			pp "FIXME: LEAVE(session_user_id)", session_user_id

			if session_token == @session.token then
				cur_session = @session
				pp "FIXME: LEAVE(cur_session) current", cur_session
			else
				cur_session = Session.first( :token => session_token )
				pp "FIXME: LEAVE(cur_session) other", cur_session
			end
			
			if cur_session then
				user = cur_session.users.get(session_user_id)
				pp "FIXME: LEAVE(user)", user
			end

			if user then
				user.idle_expires_at = Time.now.to_i
				user.alive_expires_at = Time.now.to_i
				user.did_expire = true
				# create leave event if session is the current one
				if session_token == @session.token and user.zone >= 0 then
					@board.leave user
					Event.create_leave user.id, user.alive_expires_at, user.zone, @session
				end
				user.save
			else
				rdebug "Could not find any user for this request (user=%s)" % session.inspect;
			end

		end


		#
		# If the current user in session is an admin,
		# returns true.
		#
		def admin? session
			user_id = session[PoieticGen::Api::SESSION_USER]
			user = @session.users.get(user_id)
			
			return ((not user.nil?) and user.is_admin)
		end

		#
		# if not expired, update lease
		#
		# no result expected
		#
		def check_lease! session
			now = Time.now.to_i

			user = @session.users.get session[PoieticGen::Api::SESSION_USER]
			pp user, now
			raise InvalidSession, "No user found with session_id %s in DB" % @session.token if user.nil?

			if ( (now >= user.alive_expires_at) or (now >= user.idle_expires_at) ) then
				# expired lease...
				return false
			else
				return true
			end
		end


		#
		# get latest updates from user
		#
		# return latest updates from everyone !
		#
		def update_data session, data

			# parse update request first
			rdebug "updating with : %s" % data.inspect
			req = UpdateRequest.parse data

			# prepare empty result message
			result = nil

			User.transaction do

				user = @session.users.get session[PoieticGen::Api::SESSION_USER]
				now = Time.now.to_i

				self.check_expired_users


				user.alive_expires_at = (now + @config.user.liveness_timeout)
				if not req.strokes.empty? then
					user.idle_expires_at = (now + @config.user.idle_timeout)
				end
				user.save

				@board.update_data user, req.strokes
				@chat.update_data user, req.messages
				
				timelines = @session.timelines.all(
					:id.gt => req.timeline_after
				)

				# rdebug "drawings: (since %s)" % req.timeline_after
				strokes = timelines.strokes.all(
					:zone.not => user.zone
				)
				
				ref_stamp = user.last_update_time - req.update_interval

				strokes_collection = strokes.map{ |d| d.to_hash ref_stamp }

				# rdebug "events: (since %s)" % req.timeline_after
				events = timelines.events
				events_collection = events.map{ |e| e.to_hash @board[e.zone_index], ref_stamp }

				# rdebug "chat: (since %s)" % req.timeline_after
				messages = timelines.messages.all(
					:user_dst => user.id
				)
				messages_collection = messages.map{ |e| e.to_hash }

				user.last_update_time = now
				# FIXME: handle the save
				user.save

				result = {
					:events => events_collection,
					:strokes => strokes_collection,
					:messages => messages_collection,
					:stamp => (now - @session.timestamp), # FIXME: unused by the client
					:idle_timeout => (user.idle_expires_at - now)
				}

				rdebug "returning : %s" % result.inspect

			end
			return result
		end


		#
		# Return a session snapshot
		#
		def snapshot session, params

			rdebug "call with %s" % params.inspect
			req = SnapshotRequest.parse params
			result = nil
			req_session = @session

			User.transaction do

				self.check_expired_users

				# ignore session_id from the viewer point of view but use server one
				# to distinguish old sessions/old users

				now_i = Time.now.to_i - 1
				timeline_id = 0
				date_range = -1
				diffstamp = 0
				timestamp = -1
				
				# we take a snapshot one second in the past to be sure we will get
				# a complete second.
				if req.date == -1 then
					# get the current state, select only this session
					users_db = req_session.users.all(
						:did_expire.not => true
					)
					users = users_db.map{ |u| u.to_hash }
					zones = users_db.map{ |u| @board[u.zone].to_desc_hash Zone::DESCRIPTION_FULL }
					
					timeline_id = Timeline.last_id req_session
				else
					# retrieve the total duration of the game
					date_range = now_i - req_session.timestamp

					# retrieve stroke_max and event_max

					if req.date != 0 then
						if req.date > 0 then
							# get the state from the beginning.

							absolute_time = req_session.timestamp + req.date
						else
							# get the state from now.

							absolute_time = now_i + req.date + 1
						end

						STDOUT.puts "abs_time %d (now %d, date %d)" % [absolute_time, now_i, req.date]

						# The first event before the requested time
						t = req_session.timelines.first(
							:timestamp.lte => absolute_time,
							:order => [ :id.desc ]
						)

						if not t.nil? then
							timeline_id = t.id
							diffstamp = absolute_time - t.timestamp
						end
						
						timestamp = absolute_time - req_session.timestamp
					end

					STDOUT.puts "timeline_id %d" % timeline_id

					# retrieve users and zones
					
					if timeline_id > 0 then
						users, zones = @board.load_board timeline_id, req_session, true
					
						# FIXME: use allocator to test if zone is allocated	
						zones = zones
							.select{ |i,z| not z.user_id.nil? } # only used zones
							.map{ |i,z| z.to_desc_hash Zone::DESCRIPTION_FULL }
					else
						users = zones = [] # no events => no users => no zones
					end
				end

				# return snapshot params (user, zone), start_time, and
				# duration of the session since then.
				result = {
					:users => users, # TODO: unused by the viewer
					:zones => zones,
					:zone_column_count => @config.board.width,
					:zone_line_count => @config.board.height,
					:timeline_id => timeline_id,
					:timestamp => timestamp, # time between the session start and the requested date
					:date_range => date_range, # total time of session
					:diffstamp => diffstamp, # time between the found timeline and the requested date
					:id => req.id
				}

				rdebug "returning : %s" % result.inspect

			end
			return result
		end

		#
		# Get strokes and events for a non-user viewer.
		#
		def play session, params

			rdebug "call with %s" % params.inspect
			req = PlayRequest.parse params
			now_i = Time.now.to_i
			result = nil
			req_session = @session

			# TODO : ignore session_id because it is unknow for the viewer for now
			#raise RuntimeError, "Invalid session" if req.session != req_session.token

			Event.transaction do

				self.check_expired_users

				rdebug "req.timeline_after = %d" % req.timeline_after

				# Get events and strokes between req.timeline_after and req.duration

				strokes_collection = []
				events_collection = []
				timestamp = 0
				next_timeline_id = -1
				max_timestamp = -1

				if req.view_mode == PlayRequest::REAL_TIME_VIEW then
					STDOUT.puts "REAL_TIME_VIEW"
				
					timelines = req_session.timelines.all(
						:id.gte => req.timeline_after
					)
				
					evt_req = timelines.events

					pp evt_req
					
					srk_req = timelines.strokes

					pp srk_req
					
					first_timeline = timelines.first(
						:order => [ :id.asc ]
					)
					
					events_collection = evt_req.map{ |e|
						e.to_hash @board[e.zone_index], first_timeline.timestamp
					}
				
					strokes_collection = srk_req.map{ |s|
						s.to_hash first_timeline.timestamp
					}
					
				elsif req.view_mode == PlayRequest::HISTORY_VIEW then
					
					STDOUT.puts "HISTORY_VIEW"
					
					session_timelines = req_session.timelines
					
					# This stroke is used to compute diffstamps
					since = session_timelines.first(
						:id.gte => req.since,
						:order => [ :id.asc ]
					)
					
					pp since
					
					if not since.nil? then
						
						if req.last_max_timestamp > 0 then
							max_timestamp = req.last_max_timestamp + req.duration * 2
							# Events between the requested timeline and (timeline + duration)
							timelines = session_timelines.all(
								:timestamp.gt => req_session.timestamp + req.last_max_timestamp,
								:timestamp.lte => req_session.timestamp + max_timestamp
							)
						else
							max_timestamp = req.duration * 2
							timelines = session_timelines.all(
								:timestamp.lte => req_session.timestamp + max_timestamp
							)
						end
						
						pp "timelines"
						pp timelines
						
						if not timelines.empty? then
				
							srk_req = timelines.strokes

							strokes_collection = srk_req.map{ |s|
								s.to_hash since.timestamp
							}
					
							STDOUT.puts "Strokes"
							pp srk_req
					
							evt_req = timelines.events

							if not evt_req.empty? then

								STDOUT.puts "Events"
								pp evt_req
					
								users, zones = @board.load_board timelines.last.id, req_session, false
								# FIXME: load_board loads some useless data for what we want
					
								events_collection = evt_req.map{ |e| e.to_hash zones[e.zone_index], since.timestamp }
							end

							timestamp = timelines.first.timestamp - req_session.timestamp
						end
					else
						pp "Invalid since" % req.since
					end
				else
					raise RuntimeError, "Unknown view mode %d" % req.view_mode
				end

				result = {
					:events => events_collection,
					:strokes => strokes_collection,
					:timestamp => timestamp, # relative to the start of the game session
					:max_timestamp => max_timestamp,
					:id => req.id,
				}

				rdebug "returning : %s" % result.inspect
			end
			return result
		end


		#
		#
		#
		def check_expired_users
			# FIXME: TODO: WARNING: the user association in @session is not updated when users are modified!
		
			User.transaction do
				now = Time.now.to_i
				if @leave_mutex.try_lock then
					# remove users without a zone
					users_db = User.all( :did_expire.not => true )
					users_db.each do |u|
						# verify that user really has a zone in that program instance
						has_zone = @board.include? u.zone
						# disable users without a zone
						if not has_zone then
							# kill non-existant user
							rdebug "Killing user with no zone : %s" % u.inspect
							u.idle_expires_at = now
							u.alive_expires_at = now
							u.did_expire = true
							u.save
						end
					end

					# remove expired users that have not yet been declared as expired
					if (@last_leave_check_time + LEAVE_CHECK_TIME_MIN) < now then
						newly_expired_users = User.all(
							:did_expire => false,
							:alive_expires_at.lte => now
						) + User.all(
						:did_expire => false,
						:idle_expires_at.lte => now
						)
						rdebug "New expired list : %s" % newly_expired_users.inspect
						newly_expired_users.each do |leaver|
							fake_session = {}
							fake_session[PoieticGen::Api::SESSION_USER] = leaver.id
							fake_session[PoieticGen::Api::SESSION_SESSION] = leaver.session.token
							self.leave fake_session
						end
						@last_leave_check_time = now
					end
					@leave_mutex.unlock
				else
					rdebug "Leaver updates : Can't update because someone is already working on that"
				end
			end
		end

		private

		def _session_init 
			@session = Session.new

			# total count of users seen (FIXME: get it from db, FIXME: unused)
			@users_seen = 0

			# Create board with the configuration
			@board = Board.new @config.board

			@chat = PoieticGen::ChatManager.new @config.chat

			@last_leave_check_time = Time.now.to_i - LEAVE_CHECK_TIME_MIN
			@leave_mutex = Mutex.new
		end

	end
end
