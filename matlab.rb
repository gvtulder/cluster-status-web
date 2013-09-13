require "rubygems"

class MatlabLicense
  def self.toolboxes
    txt = IO.popen("/cm/shared/apps/matlab/v716/bin/glnxa64/lmutil lmstat -a -c /cm/shared/apps/matlab/v716/licenses/network.lic") do |io|
      io.read
    end

    toolboxes = []
    current_toolbox = nil
    txt.each_line do |line|
      case line
      when /^Users of ([^:]+):\s*\(Total of ([0-9]+) licenses? issued;\s+Total of ([0-9]+) licenses? in use\)/
        current_toolbox = {
          :toolbox=>$1,
          :licenses_issued=>$2,
          :licenses_used=>$3,
          :users=>[]
        }
        toolboxes << current_toolbox
      when /^    (\S+) .+ \(matlab\.erasmusmc\.nl/
        if current_toolbox
          current_toolbox[:users] << $1
        end
      end
    end

    toolboxes
  end
end

