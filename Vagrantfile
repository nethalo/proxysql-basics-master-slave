Vagrant.configure("2") do |config|

  config.vm.provider "virtualbox" do |v|
    v.memory = 512
    v.cpus = 2
    v.linked_clone = true
  end

  config.vm.define "app", primary: true do |app_config|
     app_config.vm.box = "generic/rhel9"
     app_config.vm.box_check_update = false
     app_config.vbguest.auto_update = true
     app_config.vm.hostname = "app"
     app_config.vm.network "private_network", ip: "192.168.70.200"
     app_config.vm.network "forwarded_port", guest: 6080, host: 6080
     app_config.hostmanager.enabled = true
     app_config.hostmanager.manage_guest = true
     app_config.hostmanager.ignore_private_ip = false
     app_config.vm.synced_folder ".", "/vagrant", type: "virtualbox"

     app_config.vm.provision "shell", inline: <<-SHELL
       sudo python3 -m ensurepip --upgrade
       sudo /usr/local/bin/pip3 install ansible
     SHELL

     app_config.vm.provision "ansible_local" do |ansible|
       ansible.playbook = "proxysql.yml"
       ansible.verbose = true
       ansible.install = true
       ansible.limit = "all"
       ansible.inventory_path = "inventory"
     end
  end

  (1..3).each do |i|
    config.vm.define "mysql#{i}" do |node|
      node.vm.box = "generic/rhel9"
      node.vm.box_check_update = false
      node.vbguest.auto_update = true
      node.vm.hostname = "mysql#{i}"
      node.vm.network "private_network", ip: "192.168.70.#{i}0"
      node.hostmanager.enabled = true
      node.hostmanager.manage_guest = true
      node.hostmanager.ignore_private_ip = false
      node.vm.synced_folder ".", "/vagrant", type: "virtualbox"

      node.vm.provision "shell", inline: <<-SHELL
        sudo python3 -m ensurepip --upgrade
        sudo /usr/local/bin/pip3 install ansible
      SHELL

      node.vm.provision "ansible_local" do |ansible|
        ansible.playbook = "mysql.yml"
        ansible.verbose = true
        ansible.install = true
        ansible.limit = "all"
        ansible.inventory_path = "inventory"
      end

    end
  end

end
