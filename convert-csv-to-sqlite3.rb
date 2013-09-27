require "rubygems"
require "./history"

Dir["csv-mem/*.csv"].each do |csv_filename|
  timestamps = Hash.new{|h,k|h[k] = {}}

  puts "Reading #{ csv_filename }"

  File.open(csv_filename) do |f|
    while line = f.gets
      parts = line.strip.split("\t")
      # 0          1         2           3      4       5            6   7   8   9   10  11         12
      # timestamp job_number task_number owner job_name vmem_request cpu mem io iow vmem maxvmem job_project
      if parts[0] =~ /^[0-9]+$/
        timestamps[parts[0].to_i][parts[1]] ||= {
          "JB_owner"=>parts[3],
          "JB_job_name"=>parts[4],
          "vmem_request"=>parts[5],
          "JB_project"=>parts[12],
          "tasks"=>{}
        }
        timestamps[parts[0].to_i][parts[1]]["tasks"][parts[2]] = {
          "cpu"=>parts[6],
          "mem"=>parts[7],
          "io"=>parts[8],
          "iow"=>parts[9],
          "vmem"=>parts[10],
          "maxvmem"=>parts[11],
        }
      end
    end
  end

  puts "Saving"
  per_date = Hash.new{|h,k|h[k] = {}}
  timestamps.each do |t,jobs|
    per_date[Time.at(t).strftime("%Y-%m-%d")][t] = jobs
  end

  per_date.each do |date, timestamps|
    History.for_date(date) do |history|
      timestamps.each do |timestamp, jobs|
        history.store_job_stats(jobs, timestamp)
      end
    end
  end
end

