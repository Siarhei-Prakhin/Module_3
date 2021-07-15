#!/bin/bash
echo "Enter the TOMCAT_COUNT variable value:"
read tomcat

# Create serverX.xml files for Tomcat servers
for ((i=1; i <= $tomcat; i++))
do
servername="server"$i".xml"
ipadd="192.168.10."$((i+5))
cp base_serverxml $servername
sed -i "s/xx.xx.xx.xx/$ipadd/g" $servername
done

# Create workers.properties file for HTTPD server
cat << EOF > workers.properties
# Define the load_balancer and JK-manager names
worker.list=loadbalancer,status

# Define the properties of first tomcat workers
EOF
for ((i=1; i <= $tomcat; i++))
do
echo "worker.tomcat$i.port=8009
worker.tomcat$i.host=192.168.10.$((i+5))
worker.tomcat$i.type=ajp13
worker.tomcat$i.lbfactor=1" >> workers.properties

tomcatlist=$tomcatlist"tomcat"$i","
done
tomcatlist=${tomcatlist::-1}
echo "
# Defines the properties of load_balancer.
worker.loadbalancer.type=lb
worker.loadbalancer.balance_workers=$tomcatlist

# Defines the properties of JK-manager.
worker.status.type=status" >> workers.properties


# Create Vagrantfile

cat << EOF > Vagrantfile
Vagrant.configure("2") do |config|
TOMCAT_COUNT = $tomcat
  config.vm.box = "centos/8"
  config.vm.box_check_update = false
  config.vm.define "HTTPD-node" do |node1|
    node1.vm.provider "virtualbox" do |vb|
      vb.name = "HTTPD-VBnode"
    end
    node1.vm.hostname = "HTTPD-VMnode"
    node1.vm.network "private_network", ip: "192.168.10.5"
    node1.vm.network "forwarded_port", guest: 80, host: 4444, host_ip: "127.0.0.1"
    node1.vm.provision "shell", inline: "
        yum install httpd wget httpd-devel gcc make redhat-rpm-config -y
        setenforce 0
        sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
        wget -P /home/vagrant/ https://downloads.apache.org/tomcat/tomcat-connectors/jk/tomcat-connectors-1.2.48-src.tar.gz
        tar xf tomcat-connectors*.tar.gz
        cd /home/vagrant/tomcat-connectors-1.2.48-src/native/
        /home/vagrant/tomcat-connectors-1.2.48-src/native/configure --with-apxs=/usr/bin/apxs
        make && make install
        chmod 755 /usr/lib64/httpd/modules/mod_jk.so
        chmod -R 777 /etc/httpd/

    "
    node1.vm.provision "file", source: "./workers.properties", destination: "/home/vagrant/"
    node1.vm.provision "shell", inline: "mv /home/vagrant/workers.properties /etc/httpd/conf/"
    node1.vm.provision "file", source: "./httpd.conf", destination: "/home/vagrant/"
    node1.vm.provision "shell", inline: "mv /home/vagrant/httpd.conf /etc/httpd/conf/"
    node1.vm.provision "shell", inline: "systemctl restart httpd"

  end

  (1.. TOMCAT_COUNT ).each do |i|
    config.vm.define "Tomcat-node-#{i}" do |node|
      node.vm.provider "virtualbox" do |vb|
        vb.name = "Tomcat-VBnode#{i}"
      end
      node.vm.hostname = "Tomcat-VMnode#{i}name"
      node.vm.network "private_network", ip: "192.168.10.#{i+5}"
      node.vm.provision "shell", inline: "
          setenforce 0
          sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
          yum install java-1.8.0-openjdk-devel wget  -y
          wget -P /home/vagrant/ https://ftp.byfly.by/pub/apache.org/tomcat/tomcat-9/v9.0.50/bin/apache-tomcat-9.0.50.tar.gz
          tar -xvf apache-tomcat-9.0.50.tar.gz
          mv apache-tomcat-9.0.50 tomcat9
          echo 'export CATALINA_HOME='/home/vagrant/tomcat9'' >> ~/.bashrc
          /home/vagrant/tomcat9/bin/startup.sh
          mkdir /home/vagrant/tomcat9/webapps/test
          chmod -R 777 /home/vagrant/tomcat9/
          echo 'net.ipv6.conf.all.disable_ipv6 = 1
          net.ipv6.conf.default.disable_ipv6 = 1' >> /etc/sysctl.conf
          sysctl -p
          systemctl restart NetworkManager
          nmcli networking off; nmcli networking on
      "
      node.vm.provision "file", source: "./server#{i}.xml", destination: "/home/vagrant/tomcat9/conf/server.xml"
      node.vm.provision "file", source: "./index.html", destination: "/home/vagrant/tomcat9/webapps/test/"
      node.vm.provision "shell", inline: "
          /home/vagrant/tomcat9/bin/shutdown.sh
          /home/vagrant/tomcat9/bin/startup.sh
      "


    end
  end
end

EOF

vagrant up
