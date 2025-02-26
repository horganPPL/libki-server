#!/bin/bash

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root."
   exit 1
fi

is_debian_stretch=false
is_debian_bullseye=false
is_debian_buster=false
is_ubuntu_bionic=false
is_ubuntu_focal=false

if [ -e /etc/os-release ]; then
  source /etc/os-release
  dist=$ID
  code="${VERSION_CODENAME-$VERSION_ID}"
  case "${dist}-${code}" in
    ubuntu-bionic)
      is_ubuntu_bionic=true
      ;;
    ubuntu-focal)
      is_ubuntu_focal=true
      ;;
    ubuntu-jammy)
      is_ubuntu_jammy=true
      ;;
    debian-buster)
      is_debian_buster=true
      ;;
    debian-stretch)
      is_debian_stretch=true
      ;;
    debian-9)
      is_debian_stretch=true
      ;;
    debian-bullseye)
      is_debian_bullseye=true
      ;;
    *)
      echo
      echo "ERROR: Distribution \"$PRETTY_NAME\" is not supported!" >&2
      exit 1
      ;;
  esac
fi

# Update and install packages
apt-get update
apt-get upgrade -y

# Install packages depending on Stretch or Bionic.
if [ "$is_debian_stretch" = true ]; then
  apt-get install sudo openssl curl perl make build-essential unzip mysql-server pwgen ntp libimage-magick-perl libxml-parser-perl libxml-libxml-perl cpanminus cups libcups2-dev shared-mime-info -y
elif [ "$is_debian_buster" = true ]; then
  apt-get install sudo openssl curl perl make build-essential unzip mariadb-server pwgen ntp libimage-magick-perl libxml-parser-perl libxml-libxml-perl libnet-ssleay-perl libxml-parser-perl cpanminus cups libcups2-dev shared-mime-info -y
elif [ "$is_debian_bullseye" = true ]; then
  apt-get install sudo openssl curl perl make build-essential unzip mariadb-server pwgen ntp libimage-magick-perl libxml-parser-perl libxml-libxml-perl libnet-ssleay-perl libxml-parser-perl cpanminus cups libcups2-dev shared-mime-info libdbd-mysql-perl -y
elif [ "$is_ubuntu_bionic" = true ]; then
  apt-get install sudo openssl curl perl make build-essential unzip mysql-server pwgen ntp libimage-magick-perl libmysqlclient-dev libxml-parser-perl libxml-libxml-perl cpanminus cups libcups2-dev shared-mime-info -y
elif [ "$is_ubuntu_focal" = true ]; then
  apt-get install sudo openssl curl perl make build-essential unzip mysql-server pwgen ntp libimage-magick-perl libmysqlclient-dev libxml-parser-perl libxml-libxml-perl cpanminus cups libcups2-dev pwgen shared-mime-info -y
elif [ "$is_ubuntu_jammy" = true ]; then
  apt-get install sudo openssl curl perl make build-essential unzip mysql-server pwgen ntp libimage-magick-perl libmysqlclient-dev libxml-parser-perl libxml-libxml-perl cpanminus cups libcups2-dev pwgen shared-mime-info -y

fi

# Auto-created passwords
USERPASS=$(pwgen -B 8 1)
DBPASS=$(pwgen -B 8 1)

# Add libki user
useradd -m -s /bin/bash -p $(openssl passwd -1 $USERPASS) libki

# Copies the folder to /home/libki
mkdir /home/libki/libki-server
cp * /home/libki/libki-server -R
chown libki:libki /home/libki/libki-server -R

# Install cpan perl modules globally
cpanm -n Module::Install
cpanm -n --installdeps .

echo 'export PERL5LIB=$PERL5LIB:/home/libki/libki-server/lib' >> ~/.bashrc
echo 'export PERL5LIB=$PERL5LIB:/home/libki/libki-server/lib' >> /home/libki/.bashrc
export PERL5LIB=$PERL5LIB:/home/libki/libki-server/lib

# Create log files, change ownership to libki
mkdir /var/log/libki
touch /var/log/libki/libki.log
touch /var/log/libki/libki_server.log

chown libki:libki /var/log/libki/libki.log
chown libki:libki /var/log/libki/libki_server.log

cp /home/libki/libki-server/libki_local.conf.example /home/libki/libki-server/libki_local.conf
cp /home/libki/libki-server/log4perl.conf.example /home/libki/libki-server/log4perl.conf

chown libki:libki /home/libki/libki-server/libki_local.conf
chown libki:libki /home/libki/libki-server/log4perl.conf

# Create libki database and database user
mysql <<MYSQL_SCRIPT
CREATE DATABASE libki;
CREATE USER 'libki'@'localhost' IDENTIFIED BY '$DBPASS';
GRANT ALL PRIVILEGES ON libki.* TO 'libki'@'localhost';
FLUSH PRIVILEGES
MYSQL_SCRIPT

# Edit config file to contain database password
sed -i "s/PASSWORD/$DBPASS/g" /home/libki/libki-server/libki_local.conf

# Install the database
perl /home/libki/libki-server/installer/update_db.pl

# Create administrator user
while true; do
  echo
  read -p "Creating the admin user for Libki. Please enter your desired username: " ADMINUSERNAME < /dev/tty

  if [ -z $ADMINUSERNAME ]; then
    echo
    echo "Your username cannot be empty."
  else
    break 2
  fi
done

while true; do
  read -s -p "Please enter your desired password: " ADMINPASSWORD < /dev/tty
  echo
  read -s -p "Please enter your desired password again: " ADMINPASSWORD2 < /dev/tty

  if [[ $ADMINPASSWORD = $ADMINPASSWORD2 ]]; then
    if [[ $ADMINPASSWORD = *[!\ ]* ]]; then
      break 3
    else
      echo
      echo "Your password cannot be empty."
    fi
  else
    echo
    echo "Your passwords did not match. Please try again."
  fi
done

echo
echo "Creating your admin account..."

perl /home/libki/libki-server/script/administration/create_user.pl -u $ADMINUSERNAME -p $ADMINPASSWORD -s > /dev/null 2>&1

# Add the cronjobs
cat installer/cron/libkicron | crontab -u libki -
cat installer/cron/rootcron | crontab -


# Set up the Libki service and ask user for what port to run it on
cp /home/libki/libki-server/init-script-template /etc/init.d/libki

echo

# Reverse proxy setup
echo "Would you like to set up a reverse proxy, so the Libki server can be accessed via a domain name rather than an IP adress?"
echo "If you answer no, you will still be able to access the Libki server via the server's IP adress."

select PROXYANSWER in "Yes" "No"; do
  case "$PROXYANSWER" in
    Yes )

      # Install Apache
      apt-get install apache2 -y

      # Create a variable to check if proxy was chosen later
      PROXYCHECKER="yes"

      # Copy the config file
      rm /etc/apache2/sites-enabled/000-default.conf
      cp /home/libki/libki-server/reverse_proxy.config /etc/apache2/sites-available/libki.conf

      # Set domain name
      read -p "What domain name do you wish to use? " DOMAINNAME < /dev/tty

      sed -i "s/libki.server.org/$DOMAINNAME/g" /etc/apache2/sites-available/libki.conf

      # Enables the new site
      a2ensite libki
      a2enmod proxy
      a2enmod proxy_http
      a2enmod headers

      URL="http://$DOMAINNAME/administration"
      ;;
    No )
      # Set custom port if the user so desires
      while true; do
        read -p "What port would you like to run Libki on? " -i "3000" -e PREFERREDPORT < /dev/tty
        [[ $PREFERREDPORT =~ ^[0-9]+$ ]] && break
        echo
        echo "Your port number must be a number."
      done

      sed -i "s/3000/$PREFERREDPORT/g" /etc/init.d/libki

      update-rc.d libki defaults

      # Get ip address from hostname
      hostname=$(hostname -I)
      ips=( $hostname )

      if [[ $PREFERREDPORT = 80 ]]; then
        URL="http://${ips[0]}/administration"
      else
        URL="http://${ips[0]}:$PREFERREDPORT/administration"
      fi
      ;;
    * )
      echo
      echo "You must choose 1 (Yes) or 2 (No)"
      continue
  esac
  break
done < /dev/tty

# Starting the Libki service
service libki start

# Wait for the service to start
while (( $(ps -ef | grep -v grep | grep "libki" | wc -l) == 0 ))
do
  sleep 1
done

# Starting the Apache service
if [[ $PROXYCHECKER = "yes" ]]; then
  service apache2 start

  # Wait for the service to start
  while (( $(ps -ef | grep -v grep | grep "apache2" | wc -l) == 0 ))
  do
    sleep 1
  done
fi
# Copies the utilities to /usr/local/bin
cp script/utilities/backup.sh /usr/local/bin/libki-backup
cp script/utilities/restore.sh /usr/local/bin/libki-restore
cp script/utilities/translate.sh /usr/local/bin/libki-translate
cp script/utilities/update.sh /usr/local/bin/libki-update

# Report all settings
echo
echo "Congratulations!"
echo
echo "Your Libki server is now installed and up and running."
echo
echo "Here are all your settings. Be sure to write them down somewhere safe."
echo
echo "Your server username: libki"
echo "Your server password: $USERPASS"
echo
echo "Your database username: libki"
echo "Your database password: $DBPASS"
echo "Your database name: libki"
echo
echo "Your Libki administrator account username: $ADMINUSERNAME"
echo "Your Libki administrator account password: $ADMINPASSWORD"
echo
echo "Your log files are located in /var/log/libki/"
echo
echo "Your server can be reached on the following address:"
echo "$URL"
echo

exit 0
