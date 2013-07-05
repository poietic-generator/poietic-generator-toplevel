/******************************************************************************/
/*                                                                            */
/*  Poietic Generator Reloaded is a multiplayer and collaborative art         */
/*  experience.                                                               */
/*                                                                            */
/*  Copyright (C) 2011 - Gnuside                                              */
/*                                                                            */
/*  This program is free software: you can redistribute it and/or modify it   */
/*  under the terms of the GNU Affero General Public License as published by  */
/*  the Free Software Foundation, either version 3 of the License, or (at     */
/*  your option) any later version.                                           */
/*                                                                            */
/*  This program is distributed in the hope that it will be useful, but       */
/*  WITHOUT ANY WARRANTY; without even the implied warranty of                */
/*  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Affero  */
/*  General Public License for more details.                                  */
/*                                                                            */
/*  You should have received a copy of the GNU Affero General Public License  */
/*  along with this program.  If not, see <http://www.gnu.org/licenses/>.     */
/*                                                                            */
/******************************************************************************/

/*jslint nomen:true*/
/*global document, window, noconsole, jQuery, PoieticGen*/

// vim: set ts=4 sw=4 et:

(function (PoieticGen, $) {
	"use strict";

	var VIEW_SESSION_URL_JOIN = "/api/session/snapshot",
		VIEW_SESSION_URL_UPDATE = "/api/session/play",

		VIEW_SESSION_UPDATE_INTERVAL = 1000,
		VIEW_PLAY_UPDATE_INTERVAL = VIEW_SESSION_UPDATE_INTERVAL / 1000,

		STATUS_INFORMATION = 1,
		STATUS_SUCCESS = 2,
		STATUS_REDIRECTION = 3,
		STATUS_SERVER_ERROR = 4,
		STATUS_BAD_REQUEST = 5,
		
		REAL_TIME_VIEW = 0,
		HISTORY_VIEW = 1;


	function ViewSession(callback) {
		var console = window.console,
			self = this,
			_current_stroke_id = 0,
			_current_event_id = 0,
			_init_stroke_id = 0,
			_observers = null,
			_slider = null,

			// _server_start_date = 0, // in seconds, since jan, 1, 1970
			// _server_elapsed_time = 0, // in seconds, since server start

			_local_start_date = 0, // date Object
			// _local_start_offset = 0, // seconds between server_start & js_start

			_timer = null,
			_play_speed = 1,
			_get_elapsed_time_fn,
			// _get_server_date_fn,
			// _set_local_start_date_fn,
			_view_type = REAL_TIME_VIEW,
			_last_update_timestamp = 0;

		this.zone_column_count = null;
		this.zone_line_count = null;


		/*
		 * Date utilities 
		 */
		/* _set_local_start_date_fn = function (serverDate, serverElapsed) {
			var localDateSec;
				
			_local_start_date = new Date();
			//_server_start_date = serverDate;
			localDateSec = Math.floor(_local_start_date.getTime() / 1000);
			_local_start_offset = localDateSec - serverDate;
		}; */


		// FIXME: in seconds
		_get_elapsed_time_fn = function () {
			var local_time = (new Date()).getTime();
			return Math.floor((local_time - _local_start_date.getTime()) / 1000);
		};

		/* _get_server_date_fn = function (offset_seconds) {
			var server_time,
				local_time,
				local_server_diff,
				local_time_sec,
				elapsed_time,
				offset;

			elapsed_time = _get_elapsed_time_fn();
			server_time = _server_start_date - local_time_sec;

			return (server_time + offset_seconds);
		}; */


		/**
		 * Semi-Constructor
		 */
		this.initialize = function (date) {

			_observers = [];

			self.join_view_session(date);
			
			self.dispatch_interval(1);
			
			if (_view_type == HISTORY_VIEW) {
				$(".slider").show();
				
				$(".ui-slider").bind("vmouseup", function (event) {
					date = _slider.value();
					console.log('User history change: ' + date);
					self.clear_observers();
					self.clearTimer();
					_last_update_timestamp = date;
					self.join_view_session(date);
				});
				
				_slider.start_animation();
			} else {
				$(".slider").hide();
			}
		};
		
		this.join_view_session = function(date) {

			if (date != -1) {
				_view_type = HISTORY_VIEW;
			} else {
				_view_type = REAL_TIME_VIEW;
			}
		
			// get session info from
			$.ajax({
				url: VIEW_SESSION_URL_JOIN,
				data: {
					date: date,
					session: "default"
				},
				dataType: "json",
				type: 'GET',
				context: self,
				success: function (response) {
					var i;

					console.log('view_session/join response : ' + JSON.stringify(response));

					this.zone_column_count = response.zone_column_count;
					this.zone_line_count = response.zone_line_count;

					// _set_local_start_date_fn(response.start_date);
					_local_start_date = new Date();

					_current_event_id = response.event_id;
					_current_stroke_id = _init_stroke_id = response.stroke_id;
					// console.log('view_session/join response mod : ' + JSON.stringify(this) );

					self.other_zones = response.zones;

					callback(self);

					//console.log('view_session/join post-callback ! observers = ' + JSON.stringify( _observers ));
					// handle other zone events
					for (i = 0; i < self.other_zones.length; i += 1) {
						console.log('view_session/join on zone ' + JSON.stringify(self.other_zones[i]));
						self.dispatch_strokes(self.other_zones[i].content);
					}
					
					if (_view_type == HISTORY_VIEW) {
						_slider.set_range(0, response.date_range);
					}

					self.setTimer(self.update, VIEW_SESSION_UPDATE_INTERVAL);

					console.log('view_session/join end');
				}
			});
		};
		
		this.set_slider = function (slider) {
			_slider = slider;
		}


		/**
		 * Treat not ok Status (!STATUS_SUCCESS)
		 */
		this.treat_status_nok = function (response) {
			switch (response.status[0]) {
			case STATUS_INFORMATION:
				break;
			case STATUS_SUCCESS:
				// ???
				break;
			case STATUS_REDIRECTION:
				// We got redirected for some reason, we do execute ourselfs
				console.log("STATUS_REDIRECTION --> Got redirected to :" + response.status[2]);
				document.location.href = response.status[2];
				break;
			case STATUS_SERVER_ERROR:
				// FIXME : We got a server error, we should try to reload the page.
				break;
			case STATUS_BAD_REQUEST:
				// FIXME : OK ???
				break;
			}
			return null;
		};


		/**
		 *
		 */
		this.update = function () {

			var req;

			// assign real values if objects are present
			if (_observers.length < 1) {
				self.setTimer(self.update, VIEW_SESSION_UPDATE_INTERVAL);
				return null;
			}

			req = {
				session: "default",
				
			        strokes_after : _current_stroke_id,
				events_after : _current_event_id,
				
				duration: VIEW_PLAY_UPDATE_INTERVAL * _play_speed,
				since_stroke : _init_stroke_id
			};

			console.log("view_session/update: req = " + JSON.stringify(req));
			$.ajax({
				url: VIEW_SESSION_URL_UPDATE,
				dataType: "json",
				data: req,
				type: 'GET',
				context: self,
				success: function (response) {
					
					if (response.status === null || response.status[0] !== STATUS_SUCCESS) {
						self.treat_status_nok(response);
					} else {
						if (response.strokes.length > 0) {
							var i, seconds = 0;
						
							if (_view_type == REAL_TIME_VIEW) {
								// We want the first stroke now and the others synchronized
								seconds = parseInt(response.strokes[0].diffstamp);
								
								// Search min diffstamp
								for (i = 1; i < response.strokes.length; i += 1) {
									if (seconds > parseInt(response.strokes[i].diffstamp)) {
										seconds = parseInt(response.strokes[i].diffstamp);
									}
								}
							

							} else {
								// diffstamps are relative to the local start date
								seconds = _get_elapsed_time_fn();
							}
							
							// console.log('view_session/update seconds : ' + seconds);
							
							for (i = 0; i < response.strokes.length; i += 1) {
								response.strokes[i].diffstamp -= seconds;
							}
						}
						// console.log('view_session/update response : ' + JSON.stringify(response));
						
						_last_update_timestamp = response.timestamp;
						
						// self.dispatch_events(response.events);
						self.dispatch_strokes(response.strokes);
					}
					
					self.setTimer(self.update, VIEW_SESSION_UPDATE_INTERVAL);
				},
				error: function (response) {
					self.setTimer(self.update, VIEW_SESSION_UPDATE_INTERVAL);
				}
			});

		};
		
		this.last_update_timestamp = function () {
			return _last_update_timestamp;
		}


		this.dispatch_events = function (events) {
			var i, o;
			for (i = 0; i < events.length; i += 1) {
			        if ((events[i].id) || (_current_event_id < events[i].id)) {
					_current_event_id = events[i].id;
				}
				for (o = 0; o < _observers.length; o += 1) {
					if (_observers[o].handle_event) {
						_observers[o].handle_event(events[i]);
					}
				}
			}
		};

		this.dispatch_strokes = function (strokes) {
			var i, o;
			for (i = 0; i < strokes.length; i += 1) {
			        if ((strokes[i].id) || (_current_stroke_id < strokes[i].id)) {
					_current_stroke_id = strokes[i].id;
				}
				for (o = 0; o < _observers.length; o += 1) {
					if (_observers[o].handle_stroke) {
						_observers[o].handle_stroke(strokes[i]);
					}
				}
			}
		};
		
		this.dispatch_interval = function (interval) {
			var o;
			for (o = 0; o < _observers.length; o += 1) {
				if (_observers[o].update_interval) {
					_observers[o].update_interval(interval);
				}
			}
		};
		
		this.clear_observers = function (events) {
			var o;
			for (o = 0; o < _observers.length; o += 1) {
				if (_observers[o].throw_strokes) {
					_observers[o].throw_strokes();
				}
			}
		};

		this.dispatch_reset = function () {
			var o;
			for (o = 0; o < _observers.length; o += 1) {
				if (_observers[o].handle_reset) {
					_observers[o].handle_reset();
				}
			}
		};

		this.register = function (p_observer) {
			_observers.push(p_observer);
		};


		this.clearTimer = function () {
			if (null !== _timer) {
				window.clearTimeout(_timer);
				_timer = null;
			}
		};

		this.setTimer = function (fn, interval) {
			this.clearTimer();
			_timer = window.setTimeout(fn, interval);
		};


		/**
		 * Play from current position
		 */
		this.current = function () {
			console.log("view_session/current");
			this.clearTimer();
			this.initialize(-1);
			this.dispatch_reset(this);
		};

		/**
		 * Replay from beginning
		 */
		this.restart = function () {
			console.log("view_session/restart");
			this.clearTimer();
			this.initialize(0);
			this.dispatch_reset(this);
		};

		this.initialize(-1);
	}

	// expose scope objects
	PoieticGen.ViewSession = ViewSession;

}(PoieticGen, jQuery));

