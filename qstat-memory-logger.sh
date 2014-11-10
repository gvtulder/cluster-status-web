#!/bin/bash
cd /scratch/gvantulder/queue-stats
while true
do
  ruby qstat-memory-logger.rb
  # find csv-mem/ -type f -name "*.sqlite3" -mtime +7 -exec gzip "{}" ";"
done

