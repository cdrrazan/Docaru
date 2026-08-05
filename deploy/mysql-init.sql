-- Runs once, on first boot of an empty MySQL data directory.
--
-- The official image's MYSQL_USER is granted rights over MYSQL_DATABASE only.
-- This application uses four databases — its own, plus separate ones for the
-- Solid Cache, Queue and Cable tables — so without these grants the first
-- `db:prepare` fails trying to create the queue database, and the reminder
-- sweep never runs.
--
-- The wildcard is scoped to this application's own prefix rather than *.*, so
-- the account cannot reach anything else that later shares the server.

CREATE DATABASE IF NOT EXISTS `renewaru_production`
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS `renewaru_production_cache`
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS `renewaru_production_queue`
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS `renewaru_production_cable`
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

GRANT ALL PRIVILEGES ON `renewaru\_%`.* TO 'renewaru'@'%';
FLUSH PRIVILEGES;
