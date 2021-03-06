-- This is done in the Makefile. Uncomment if using the file directly.
-- SET @the_month = '2015-10-01';

-- find "missing" calls: those scheduled but not observed
DROP TABLE IF EXISTS missing_calls;
CREATE TABLE missing_calls (
    `trip_index` int(11) NOT NULL,
    `rds_index` INTEGER NOT NULL,
    `datetime` datetime NOT NULL,
    KEY a (`trip_index`, `rds_index`, `datetime`)
);

INSERT INTO missing_calls
SELECT
    g.`trip_index`,
    g.`rds_index`,
    g.`datetime`
FROM
    hw_gtfs g
    LEFT JOIN calls c ON (
        g.`trip_index` = c.`trip_index`
        AND g.`rds_index` = c.`rds_index`
        AND DATE(c.`call_time`) = DATE(g.`datetime`)
    )
WHERE
    YEAR(g.`datetime`) = YEAR(@the_month)
    AND MONTH(g.`datetime`) = MONTH(@the_month)
    AND c.`rds_index` IS NULL;

DROP TABLE IF EXISTS hw_observed_conservative;
CREATE TABLE hw_observed_conservative (
    `rds_index` INTEGER NOT NULL,
    `trip_index` int(11) NOT NULL,
    `call_time` datetime NOT NULL,
    headway SMALLINT UNSIGNED NOT NULL,
    KEY a (`trip_index`, `rds_index`, `call_time`)
);

SET @prev_rds = NULL;

INSERT hw_observed_conservative
SELECT
    rds_index,
    trip_index,
    call_time,
    headway
FROM (
    SELECT
        rds_index,
        trip_index,
        call_time,
        @headway := IF(`rds_index` = @prev_rds, TIME_TO_SEC(TIMEDIFF(depart_time(call_time, dwell_time), @prev_depart)), NULL) AS headway,
        @prev_rds := rds_index,
        @prev_depart := depart_time(call_time, dwell_time)
    FROM (
        SELECT * FROM (
            SELECT trip_index, rds_index, call_time, dwell_time FROM calls UNION
            SELECT trip_index, rds_index, datetime call_time, NULL dwell_time FROM missing_calls
        ) a
        WHERE DATE(call_time) BETWEEN @the_month AND DATE_SUB(DATE_ADD(@the_month, INTERVAL 1 MONTH), INTERVAL 1 DAY)
        ORDER BY
            rds_index,
            depart_time(call_time, dwell_time) ASC
    ) b
) c
WHERE headway IS NOT NULL;

DROP TABLE IF EXISTS ewt_conservative;
CREATE TABLE ewt_conservative (
    `rds_index` INTEGER NOT NULL,
    `trip_index` int(11) NOT NULL,
    `call_time` datetime NOT NULL,
    `headway_sched` SMALLINT UNSIGNED NOT NULL,
    `headway_obs` SMALLINT UNSIGNED NOT NULL,
    KEY a (`rds_index`, `trip_index`, `call_time`)
);

-- conservative observed headways
INSERT ewt_conservative
SELECT
    o.`rds_index`,
    o.`trip_index`,
    o.`call_time`,
    g.headway AS headway_sched,
    o.headway AS headway_obs
FROM
    hw_observed_conservative o
    LEFT JOIN hw_gtfs g ON (g.`trip_index` = o.`trip_index` AND g.`rds_index` = o.`rds_index` AND DATE(o.`call_time`) = DATE(g.`datetime`))
    LEFT JOIN rds_indexes r ON (r.`rds_index` = o.`rds_index`)
WHERE
    o.`call_time` BETWEEN @the_month AND DATE_SUB(DATE_ADD(@the_month, INTERVAL 1 MONTH), INTERVAL 1 DAY);

DROP TABLE IF EXISTS cewt_avg;
CREATE TABLE cewt_avg (
    `route` varchar(5),
    `period` int(11) DEFAULT NULL,
    `sched` decimal(7,2) DEFAULT NULL,
    `obs` decimal(7,2) DEFAULT NULL,
    `count` bigint(10) NOT NULL DEFAULT '0',
    `count_cewt` bigint(10) NOT NULL DEFAULT '0',
    `ewt_avg` decimal(8,2) DEFAULT NULL,
    KEY `route` (`route`, `period`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;

INSERT cewt_avg
SELECT
    r.route,
    day_period(a.call_time) period,
    ROUND(AVG(a.headway_sched/60), 2) sched,
    ROUND(AVG(a.headway_obs/60), 2) obs,
    COUNT(*) count,
    COUNT(IF(a.headway_obs > a.headway_sched, 1, NULL)) count_cewt,
    ROUND(AVG(CAST(a.headway_obs - a.headway_sched AS SIGNED)), 2) ewt_avg
FROM
    `ewt_conservative` a
    LEFT JOIN rds_indexes r ON (a.rds_index = r.rds_index)
WHERE
    DATE(a.call_time) BETWEEN @the_month AND DATE_SUB(DATE_ADD(@the_month, INTERVAL 1 MONTH), INTERVAL 1 DAY)
    AND WEEKDAY(a.call_time) < 5
GROUP BY 1, 2;
