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
				# Save board periodically
				# before the update because the first snapshot
				# must starts at stroke_id = 0
				
				if @stroke_count == 0 then
					last_timeline_id = Timeline.last_id
					if BoardSnapshot.first(:timeline => last_timeline_id).nil? then
						self.save last_timeline_id, user.session
					end
				end
				
				@stroke_count = (@stroke_count + drawing.length) % STROKE_COUNT_BETWEEN_QFRAMES;

				STDOUT.puts "stroke_count %d" % [@stroke_count]
				
				# Update the zone
			
				zone = @allocator[user.zone]
				unless zone.nil? then
					zone.apply user, drawing
				else
					#FIXME: return an error to the user ?
				end
			end
		end

		def save last_timeline, session_id
			BoardSnapshot.new @allocator.zones, last_timeline, session_id
		end
		
		#
		# Get the board state at timeline_id.
		# FIXME: load_board is not static because it depends on @config.
		#
		def load_board timeline_id
			
			if timeline_id < 0 then
				timeline_id = 0
			end
		
			# The first snap before timeline_id
			snap = BoardSnapshot.first(
				:timeline.lte => timeline_id,
				:order => [ :timeline.desc ]
			)
			
			if snap.nil? then
				# FIXME: the first snapshot isn't the first state of the game (but almost)
				snap = BoardSnapshot.first(
					:order => [ :timeline.asc ]
				)
			
				if snap.nil? then
					# FIXME: start from an empty board
					raise RuntimeError, "No snapshot found for timeline %d" % timeline_id
				end
			end
			
			STDOUT.puts "snap"
			pp snap
			
			# get the session associated to the snapshot
			users_db = User.all(
				:session => snap.session
			)
			
			STDOUT.puts "users_db"
			pp users_db
			
			timelines = Timeline.all(
				:id.gt => snap.timeline,
				:id.lte => timeline_id,
				:order => [ :id.asc ]
			)
			
			strokes_db = timelines.strokes
			
			STDOUT.puts "strokes_db"
			pp strokes_db
		
			events_db = timelines.events
			
			STDOUT.puts "events_db"
			pp events_db
			
			# Create zones from snapshot
			zones_snap = {}
			
			snap.zone_snapshots.each do |zs|
				zones_snap[zs.index] = Zone.from_snapshot zs
			end
			
			STDOUT.puts "zones_snap"
			pp zones_snap
			
			# Put zones from snapshot in allocator
			allocator = ALLOCATORS[@config.allocator].new @config
			allocator.set_zones zones_snap
			
			STDOUT.puts "Allocator snapshot"
			pp allocator
			
			# Add/Remove zones since the snapshot
			events_db.each do |event|
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
			strokes = strokes_db.map{ |s| s.to_hash s.timestamp } # strokes with diffstamp = 0 (not important)
			zones = allocator.zones
			
			# Apply strokes
			zones.each do |index,zone|
				if zone.user_id != nil then
					zone.apply_local strokes.select{ |s| s["zone"] == zone.index }
				end
			end

			STDOUT.puts "users, zones and strokes"
			pp users
			pp zones
			pp strokes
			
			return users, zones
		end
	end

end

