# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure('2') do |config|
  config.vm.box = 'betadots/centos8p6'
  config.vm.network 'forwarded_port', guest: 4567, host: 4567, host_ip: '127.0.0.1'

  config.vm.provider 'virtualbox' do |vb|
    vb.memory = '4096'
    vb.cpus = 4
  end

  config.vm.provision 'shell', inline: <<-SHELL
    sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    sudo yum install -y docker-ce docker-ce-cli docker-compose-plugin containerd.io
    sudo mkdir -p /etc/docker
    sudo echo '{ "features": { "buildkit": true } }' > /etc/docker/daemon.json
    sudo systemctl enable --now docker.service
  SHELL
end
