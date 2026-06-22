Vagrant.configure("2") do |config|
  config.vm.box      = "ubuntu/jammy64"
  config.vm.hostname = "kijanikiosk-prod"

  config.vm.provider "virtualbox" do |vb|
    vb.name   = "kijanikiosk-prod"
    vb.memory = "2048"
    vb.cpus   = 2
  end

  config.vm.synced_folder ".", "/vagrant", type: "virtualbox"

  config.vm.provision "shell", inline: <<-SHELL
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
      acl ufw git logrotate nginx curl
    ufw --force enable
    ufw allow 22/tcp
  SHELL
end
