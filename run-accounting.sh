#!/bin/bash
while true
do
  ruby accounting.rb db/chart-data-21.json 21
  ruby accounting.rb db/chart-data-2.json  2
  date
  sleep 3600
  date
done

