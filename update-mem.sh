#!/bin/bash
cd /scratch/gvantulder/queue-stats
while true
do
  dt=$( date --rfc-3339=seconds --utc )
  dd=${dt:0:10}
  ruby update-mem.rb >> csv-mem/$dd.csv
  find csv-mem/ -type f -name "*.csv" -mtime +7 -exec gzip "{}" ";"
done

