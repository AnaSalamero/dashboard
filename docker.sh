#! /bin/bash
sudo apt update
sudo apt-get -y install ca-certificates curl gnupg
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin mysql-client
echo "System packages installed" | sudo tee /var/log/terraform-install.log
sudo systemctl start docker
sudo systemctl enable docker
sudo groupadd docker || true
sudo usermod -aG docker $USER || true
echo "Docker configured" | sudo tee -a /var/log/terraform-install.log
echo "Pulling docker image" | sudo tee -a /var/log/terraform-install.log
sudo docker pull ghcr.io/anasalamero/dashboard:latest
