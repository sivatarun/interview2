package 'unzip' do
  action :install
end

package  'libwww-perl'  do
  action :install
end

package 'libdatetime-perl' do
  action :install
end

http_request 'install scripts' do
  url 'http://aws-cloudwatch.s3.amazonaws.com/downloads/CloudWatchMonitoringScripts-1.2.2.zip'
  action :get
end

execute 'unzip scripts' do
  command 'unzip CloudWatchMonitoringScripts-1.2.2.zip'
end

execute 'change directory' do
  command 'cd aws-scripts-mon'
end


execute 'copy data' do
  command 'cp awscreds.template awscreds.conf'
end

cron 'to collect metrics' do
  minute '*/5'
  command '~/aws-scripts-mon/mon-put-instance-data.pl --mem-used-incl-cache-buff --mem-util --disk-space-util --disk-path=/ --from-cron'
end

template '~/aws-scripts-mon/etc/motd' do
  source 'config.erb'
  owner 'root'
  group 'root'
  mode '0755'
end
