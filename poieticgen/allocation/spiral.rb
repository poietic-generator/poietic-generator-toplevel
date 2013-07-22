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

require 'poieticgen/allocation/generic'
require 'monitor'

module PoieticGen ; module Allocation
	class Spiral < Generic

		# helper class fir direction
		class V
			attr_accessor :x, :y

			def initialize x, y
				@x, @y = x, y
			end

			def rotate_left!
				@x, @y = -@y, @x
				# rdebug "rotate! now %s" % self
				self
			end

			def rotate_right!
				@x, @y = -@y, @x
				self
			end

			def + v
				raise TypeError unless v.is_a? V
				@x += v.x
				@y += v.y
				self
			end

			def - v
				raise TypeError unless v.is_a? V
				@x -= v.x
				@y -= v.y
				self
			end

			def == v
				return false if v.x != @x
				return false if v.y != @y
				return true
			end

			def to_s
				"(%s, %s)" % [ @x, @y ]
			end

			def to_a
				[ @x, @y ]
			end
		end



		#
		#
		#
		def initialize config
			# map index => Zone object (or nil if unallocated)
			@debug = true
			@zones = {}
			@config = config
			@monitor = Monitor.new

		end


		#
		# return the zone associated with an index
		#
		def [] index
			res = if @zones.include? index then
					  @zones[index]
				  else nil
				  end
			return res
		end

		#
		# get all zones 
		# FIXME: direct access should not be allowed
		#
		def zones
			return @zones
		end

		#
		# replace zones
		#
		def set_zones zones
			@zones = zones
		end

		#
		# return index to position
		#
		def index_to_position idx
			dir = V.new( 1, 0 )
			pos = V.new( 0, 0 )
			# rdebug "%s => %s" % [ 0, pos ]
			idx.times do |cnt|
				pos += dir
				# rdebug "%s => %s" % [ cnt + 1, pos ]
				if pos.x.abs == pos.y.abs then
					unless ( pos.y <= 0 and pos.x == -pos.y ) then
						dir.rotate_left!
					end
				elsif ( pos.y <= 0 and pos.x == -pos.y + 1 ) then
					dir.rotate_left!
				end
			end
			return pos.to_a
		end


		#
		# return position from index
		#
		def position_to_index x, y
			dir = V.new( 1, 0 )
			pos = V.new( 0, 0 )
			idx = 0
			# rdebug "%s => %s" % [ 0, pos ]
			while ( pos.x != x or pos.y != y ) do
				idx += 1
				pos += dir
				# rdebug "%s => %s" % [ cnt + 1, pos ]
				if pos.x.abs == pos.y.abs then
					unless ( pos.y <= 0 and pos.x == -pos.y ) then
						dir.rotate_left!
					end
				elsif ( pos.y <= 0 and pos.x == -pos.y + 1 ) then
					dir.rotate_left!
				end
			end
			return idx
		end


		#
		# allocates and return 
		# a zone                
		#
		def allocate
			@monitor.synchronize do
				index = _next_index()

				zone = Zone.new index, 
					(self.index_to_position index),
					@config.width,
					@config.height

				rdebug "Spiral/allocate zone : ", zone.inspect
				@zones[index] = zone

				return zone
			end
		end


		#
		# test if the zone exists
		# FIXME: use something else than user.nil to test if zone is free
 		#
		def free? zone_idx
			@monitor.synchronize do
				zone = @zones[zone_idx]
				return zone.user_id.nil?
			end
		end

		#
		# disable the zone in the allocator
		# FIXME: why did'nt we remove the zone from the allocator ?
		#
		def free zone_idx
			@monitor.synchronize do
				zone = @zones[zone_idx]
				zone.user_id = nil
				return zone
			end
		end

		private

		# 
		# Find the first allocatable index
		#
		def _next_index 
			result_index = nil

			@monitor.synchronize do
				# find a nil zone first
				nil_zones = @zones.select{ |idx,zone| zone.user_id.nil? }
				if nil_zones.size > 0 then
					# got an unallocated zone !
					result_index = nil_zones.first[0]
				else
					# try the normal method
					result_index = @zones.size
				end
			end
			return result_index
		end

	end
end ; end

