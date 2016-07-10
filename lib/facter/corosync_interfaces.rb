if File.exists?('/usr/sbin/corosync')
  i = 0
  Facter.value('interfaces').split(/,/).each do |interface|
    if interface != 'lo' && i > 0
	  Facter.add("corosync_#{i}_ip") do
	    setcode do
		  "10.0."+interface[-1..-1]+"."+Facter.value('hostname')[-1..-1]+"0"
	    end
  	  end
	  Facter.add("corosync_#{i}_dev") do
	    setcode do
		  interface
	    end
  	  end
    end
    i=i+1
  end
end