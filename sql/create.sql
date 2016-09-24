DROP TABLE IF EXISTS rds_indexes;
CREATE TABLE `rds_indexes` (
  rds_index INTEGER NOT NULL,
  route VARCHAR(5) NOT NULL,
  direction CHAR(1) NOT NULL,
  stop_id INTEGER NOT NULL,
  KEY rds (rds_index)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;

DROP TABLE IF EXISTS trip_indexes;
CREATE TABLE trip_indexes (
  trip_index INT(11) NOT NULL,
  gtfs_trip VARCHAR(64) DEFAULT NULL,
  KEY t (trip_index)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;

-- From: Nathan Johnson

-- So, at some point I did dump, compress, and upload some "calls" data - the inferred
-- stop times that forms the basis of the performance analysis (along with the schedule data).
-- I don't want to put them on a public website since I have concerns about the accuracy of
-- some of the dwell times. However, you can download them. I uploaded monthly data for
-- August 2014 to August 2015. The August 2015 data is available here:
-- https://s3.amazonaws.com/data2.mytransit.nyc/bus_calls/2015/calls_2015-08.tsv.xz.
-- You can guess the URLs of the earlier months (they take the same form). The files
-- are quite large (300-400 MB/month compressed; 2-3 GB/month uncompressed). The files
-- are tab-delimited (\t) with unix (\n) line endings. Here is the SQL schema:

-- (trip_index is more "route index") - NF
CREATE TABLE IF NOT EXISTS calls (
    vehicle_id smallint not null,
    trip_index int not null,
    stop_sequence tinyint not null,
    call_time datetime not null,
    dwell_time smallint not null,
    source char(1) not null,
    rds_index smallint not null,
    deviation smallint not null,
    INDEX rds (rds_index)
);

-- In my wisdom, I reindexed the GTFS trip_ids as integers (trip_index), but I'm
-- not sure where I put the lookup table, so it won't be possible to match the
-- trip_index up with the GTFS trip_id (and thus the route, direction, scheduled times, etc.)
-- However, you can use this as a sample for starting to work with the data - future data
-- dumps will take the same form (and will be accompanied by a lookup table for trip_ids).
-- The stop_ids do directly match the GTFS (and numbers displayed at bus stops), though.
-- • The "vehicle_id" is the number painted on the bus and reported by Bus Time.
-- • "Stop_sequence" should be self-explanatory and matches the GTFS.
-- • "Call_time" is the time the bus was inferred to have served or passed the stop - I'm pretty
--   sure it's in local time (and not UTC), but will have to double-check when I have more time.
-- • "Dwell_time" is the number of seconds the bus spent at the stop, although maybe it was stuck
--   in traffic near the stop; or maybe if it says zero seconds, it did stop for a few seconds,
--   but was too brief to be captured. Dwell times work better in aggregate. However, there is an issue
--   which causes (a lot less than) <1% of dwell times to be over-estimated, which is why I wouldn't use
--   it for metrics yet.
-- • "Source" describes how the call_time was inferred: "C" means it was captured directly; "I" is
--    interpolated (proportional with scheduled times) between adjacent captures; "S" is extrapolated
--    backwards (also proportional with scheduled times) from the first capture of the run, and "E"
--    is extrapolated forwards (also proportional) from the final capture of the run. Most extrapolations
--    are actually interpolations as they take into account bus movements before or after the run
-- • "Deviation" is the number of seconds the call_time deviated from the scheduled time - negative means
--   early; positive means late.
-- Sorry this is so messy, and especially that the trip_id lookup data is missing, but at least this
-- should give you a start on being able to work with the data. Also, maybe don't load all months
-- because I might not find the trip_id lookup tables for these, but can relatively easily generate
-- more dumps (in the same form, but with different trip_index, but that are accompanied by trip_id
-- lookup tables).

-- From: Nathan Johnson

-- I've uploaded all calls data (inferred actual stop/pass times) for August 2014 
-- through February 2016. The URLs to download the files are in the format 
-- https://s3.amazonaws.com/data2.mytransit.nyc/bus_calls/YYYY/calls_YYYY-MM.tsv.xz

-- Since the calls data also includes deviations from schedule, that should be all 
-- that is needed to calculate terminal departure on time performance (OTP) 
-- (taking into consideration that OTP should not be measured using extrapolated 
-- times - indicated by source='S'/'E' in the calls tables).

-- To calculate the other metrics, a list of scheduled departures is required. 
-- This information can be gleaned from the MTA's published GTFS feeds (archived 
-- here and here). For your convenience, I've compiled and uploaded a complete 
-- list of scheduled stop times and a date-to-trip lookup table (derived from GTFS 
-- calendar files) covering the same period as the calls files. I've also uploaded 
-- a schedule summary per route-stop-hour for each month. The schedule summaries 
-- can be downloaded in the format 
-- https://s3.amazonaws.com/data2.mytransit.nyc/bus_schedule/YYYY/schedule_YYYY-MM.
-- tsv.xz (again, for August 2014 to February 2016).

-- The additional schemas are:

CREATE TABLE IF NOT EXISTS stop_times (
    trip_index int not null,
    time time not null, 
    time_public time not null,
    stop_id int not null,
    stop_sequence tinyint unsigned not null,
    pickup_type tinyint not null,
    drop_off_type tinyint not null, 
    rds_index smallint unsigned not null,
    PRIMARY KEY (trip_index, stop_sequence)
);

CREATE TABLE IF NOT EXISTS date_trips (
    date date not null,
    trip_index int not null,
    PRIMARY KEY (date, trip_index)
);

CREATE TABLE IF NOT EXISTS schedule (
    date date not null,
    rds_index smallint unsigned not null,
    hour tinyint not null,
    scheduled tinyint not null,
    pickups tinyint not null,
    exception tinyint not null,
    PRIMARY KEY (date, rds_index, hour)
);

-- "stop_times" includes both the original GTFS times and rounded times 
-- (time_public), since the times advertised at the bus stop are rounded to the 
-- nearest minute when compared to the contents of the MTA's GTFS stop_times.txt. 
-- I've used time_public when calculating metrics since that is the time presented 
-- to the rider. Note that published arrival and departure times are always the 
-- same in the MTA's GTFS. Keep in mind that GTFS stop times can pass 24:00:00, so 
-- a trip with a service date of 2016-01-01 and stop time of 24:01:00, for 
-- example, will serve the stop at 2016-01-02 00:01:00.

-- "schedule" (schedule summaries) shows the number of scheduled buses (which 
-- includes arrivals/drop off only) and number of scheduled pickups (which should 
-- generally be used for calculating metrics). It also includes a boolean column 
-- (exception) indicating whether a route-stop-hour should be excepted from 
-- measurement due to lack of data or a snowstorm/shutdown - this is the same 
-- information as in the Exceptions table in the NYC Bus Performance Database.