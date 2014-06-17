#
# Cookbook Name:: wordpress
# Recipe:: default
#
# Copyright 2009-2010, Opscode, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_recipe "php"

# On Windows PHP comes with the MySQL Module and we use IIS on Windows
unless platform? "windows"
  include_recipe "php::module_mysql"
  include_recipe "apache2"
  include_recipe "apache2::mod_php5"
end

include_recipe "wordpress::database"

::Chef::Recipe.send(:include, Opscode::OpenSSL::Password)
node.set_unless['wordpress']['keys']['auth'] = secure_password
node.set_unless['wordpress']['keys']['secure_auth'] = secure_password
node.set_unless['wordpress']['keys']['logged_in'] = secure_password
node.set_unless['wordpress']['keys']['nonce'] = secure_password
node.set_unless['wordpress']['salt']['auth'] = secure_password
node.set_unless['wordpress']['salt']['secure_auth'] = secure_password
node.set_unless['wordpress']['salt']['logged_in'] = secure_password
node.set_unless['wordpress']['salt']['nonce'] = secure_password
node.save unless Chef::Config[:solo]

directory node['wordpress']['dir'] do
  action :create
  recursive true
  if platform_family?('windows')
    rights :read, 'Everyone'
  else
    owner node['wordpress']['install']['user']
    group node['wordpress']['install']['group']
    mode  '00755'
  end
end

archive = platform_family?('windows') ? 'wordpress.zip' : 'wordpress.tar.gz'

if platform_family?('windows')
  windows_zipfile node['wordpress']['parent_dir'] do
    source node['wordpress']['url']
    action :unzip
    not_if {::File.exists?("#{node['wordpress']['dir']}\\index.php")}
  end
else
  tar_extract node['wordpress']['url'] do
    target_dir node['wordpress']['dir']
    creates File.join(node['wordpress']['dir'], 'index.php')
    user node['wordpress']['install']['user']
    group node['wordpress']['install']['group']
    tar_flags [ '--strip-components 1' ]
  end
  directory "#{node['wordpress']['dir']}/wp-content/uploads" do
    action :create
    recursive true
    owner node['wordpress']['install']['user']
    group node['wordpress']['install']['group']
    mode  '00766'
  end
  directory "#{node['wordpress']['dir']}/wp-content/plugins" do
    action :create
    recursive true
    owner node['wordpress']['install']['user']
    group node['wordpress']['install']['group']
    mode  '00766'
  end
  directory "#{node['wordpress']['dir']}/wp-content/themes" do
    action :create
    recursive true
    owner node['wordpress']['install']['user']
    group node['wordpress']['install']['group']
    mode  '00766'
  end
end

template "#{node['wordpress']['dir']}/wp-config.php" do
  source 'wp-config.php.erb'
  mode 0644
  variables(
    :db_name          => node['wordpress']['db']['name'],
    :db_user          => node['wordpress']['db']['user'],
    :db_password      => node['wordpress']['db']['pass'],
    :db_host          => node['wordpress']['db']['host'],
    :db_prefix        => node['wordpress']['db']['prefix'],
    :auth_key         => node['wordpress']['keys']['auth'],
    :secure_auth_key  => node['wordpress']['keys']['secure_auth'],
    :logged_in_key    => node['wordpress']['keys']['logged_in'],
    :nonce_key        => node['wordpress']['keys']['nonce'],
    :auth_salt        => node['wordpress']['salt']['auth'],
    :secure_auth_salt => node['wordpress']['salt']['secure_auth'],
    :logged_in_salt   => node['wordpress']['salt']['logged_in'],
    :nonce_salt       => node['wordpress']['salt']['nonce'],
    :lang             => node['wordpress']['languages']['lang'],
    :allow_multisite  => node['wordpress']['allow_multisite']
  )
  owner node['wordpress']['install']['user']
  group node['wordpress']['install']['group']
  action :create
end

if platform?('windows')

  include_recipe 'iis::remove_default_site'

  iis_pool 'WordpressPool' do
    no_managed_code true
    action :add
  end

  iis_site 'Wordpress' do
    protocol :http
    port 80
    path node['wordpress']['dir']
    application_pool 'WordpressPool'
    action [:add,:start]
  end
else
  web_app "wordpress" do
    template "wordpress.conf.erb"
    docroot node['wordpress']['dir']
    server_name node['wordpress']['server_name']
    server_aliases node['wordpress']['server_aliases']
    server_port node['apache']['listen_ports']
    enable true
  end
end
