/*
 * Use this script when inne has been down for a long time (over a day) so
 * that the dates are updated correctly.
 *
 * Usage: sqlite3 inne.db < db/boot.sql
 * Date format: 2020-02-18 21:00:00 +0100
 *
 * My (Eddy) .sqliterc file (SQLite booting file):
 * .header on
 * .mode column
 * .timer on
 * .width 2 20 25
 * .open inne.db
 */

UPDATE global_properties
SET value = '2020-02-18 21:00:00 +0100'
WHERE key = 'next_level_update';

UPDATE global_properties
SET value = '2020-02-18 21:00:00 +0100'
WHERE key = 'next_score_update';

UPDATE global_properties
SET value = '2020-02-23 21:00:00 +0100'
WHERE key = 'next_episode_update';
