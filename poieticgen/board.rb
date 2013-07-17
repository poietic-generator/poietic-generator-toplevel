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

require 'poieticgen/update_request'
require 'poieticgen/zone'
require 'poieticgen/user'
require 'poieticgen/timeline'
require 'poieticgen/board_snapshot'
require 'poieticgen/session'

require 'poieticgen/allocation/spiral'
require 'poieticgen/allocation/random'

require 'monitor'

module PoieticGen

	#
	# A class that manages the global drawing
	#
	class Board

		STROKE_COUNT_BETWEEN_QFRAMES = 5

		attr_reader :config

		ALLOCATORS = {
			"spiral" => PoieticGen::Allocation::Spiral,
			"random" => PoieticGen::Allocation::Random,
		}


		def initialize config
			@debug = true
			rdebug "using allocator %s" % config.allocator
			@config = config
			@allocator = ALLOCATORS[config.allocator].new config
			pp @allocator
			@monitor = Monitor.new
			@stroke_count = 0
		end


		#
		# Get access to zone with given index
		#
		def [] idx
			return @allocator[idx]
		end

		def include? idx
			@monitor.synchronize do
				val = @allocator[idx]
				return (not val.nil?)
			end
		end


		#
		# make the user join the board
		#
		def join user
			zone = nil
			@monitor.synchronize do
				zone = @allocator.allocate
				zone.user_id = user.id
				user.zone = zone.index
				zone.save
				user.save
			end
			return zone
		end


		#
		# disconnect user from the board
		#
		def leave user
			@monitor.synchronize do
				# reset zone
				@allocator[user.zone].reset
				# unallocate it
				@allocator.free user.zone
			end
		end


		def update_data user, drawing
			return if drawing.empty?
		
			@monitor.synchronize do
				
				# Update the zone
			
				zone = @allocator[user.zone]
				unless zone.nil? then
					zone.apply user, drawing
				else
					#FIXME: return an error to the user ?
				end
				
				# Save board periodically
				
				if @stroke_count == 0 then
					self.save user.session
				end
				
				@stroke_count = (@stroke_count + drawing.length) % STROKE_COUNT_BETWEEN_QFRAMES;

				STDOUT.puts "stroke_count %d" % [@stroke_count]
			end
		end

		def save session
			BoardSnapshot.new @allocator.zones, (Timeline.create_now session), session
		end
		
		#
		# Get the board state at timeline_id.
		# FIXME: load_board is not static because it depends on @config.
		#
		def load_board timeline_id, session, apply_strokes
			
			snap = _get_snapshot timeline_id, session
			zones_snap = {}
			
			if snap.nil? then			
				STDOUT.puts "no snap found"
				
				# no snapshot: the board is empty
				snap_timeline = 0
			else
				STDOUT.puts "snap"
				pp snap
			
				snap_timeline = snap.timeline
				
				# Create zones from snapshot
				snap.zone_snapshots.each do |zs|
					zones_snap[zs.index] = Zone.from_snapshot zs
				end
			end
			
			STDOUT.puts "zones_snap"
			pp zones_snap
			
			# Put zones from snapshot in allocator
			allocator = ALLOCATORS[@config.allocator].new @config
			allocator.set_zones zones_snap
			
			STDOUT.puts "Allocator snapshot"
			pp allocator
			
			# get the session associated to the snapshot
			users_db = session.users
			
			# get events since the snapshot
			timelines = session.timelines.all(
				:id.gt => snap_timeline,
				:id.lte => timeline_id,
				:order => [ :id.asc ]
			)
			
			STDOUT.puts "users_db"
			pp users_db
			
			STDOUT.puts "strokes_db"
			pp timelines.strokes
			
			STDOUT.puts "events_db"
			pp timelines.events
			
			# Add/Remove zones since the snapshot
			timelines.events.each do |event|
				zone_index = event.zone_index
				user_id = event.zone_user
				
				STDOUT.puts "%s user_id = %d, zone_index = %d" % [ event.type, user_id, zone_index ]
				if event.type == "join" then
					zone = allocator.allocate
					zone.user_id = user_id
				elsif event.type == "leave" then
					# reset zone
					allocator[zone_index].reset
					# unallocate it
					allocator.free zone_index
				else
					raise RuntimeError, "Unknown event type %s" % event.type
				end
			end
			
			STDOUT.puts "Allocator after events"
			pp allocator
			
			users = users_db.map{ |u| u.to_hash } # FIXME: All users in the session are returned
			zones = allocator.zones
			
			if apply_strokes then
				strokes = timelines.strokes # strokes with diffstamp = 0 (not important)
			
				# Apply strokes
				zones.each do |index,zone|
					if zone.user_id != nil then
						zone.apply_local strokes.select{ |s| s.zone == zone.index }
					end
				end
			end

			STDOUT.puts "users and zones"
			pp users
			pp zones
			
			return users, zones
		end
		
		private

		def _get_snapshot timeline_id, session
			# The first snap before timeline_id
			timeline = session.timelines.first(
				:id.lte => timeline_id,
				:order => [ :id.desc ]
			)
			
			return timeline.board_snapshot
		end
	end

end

