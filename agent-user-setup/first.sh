MAIN_USERNAME="user"
SECOND_USERNAME="agent"
GIT_NAME="Agent"
GIT_EMAIL="agent@example.com"

# 1. Создание пользователя
sudo useradd -m -s /bin/bash "$SECOND_USERNAME"
sudo usermod -aG sudo "$SECOND_USERNAME"

# 2. Задание пароля для нового пользователя
sudo passwd "$SECOND_USERNAME"

# 3. Настройка sudoers NOPASSWD
echo "$SECOND_USERNAME ALL=(ALL) NOPASSWD: /usr/bin/apt, /usr/bin/apt-get, /usr/bin/systemctl" | sudo tee "/etc/sudoers.d/$SECOND_USERNAME"
sudo chmod 440 "/etc/sudoers.d/$SECOND_USERNAME"

# 4. Проверка конфига sudoers
sudo visudo -c

# 5. Установка пакетов
sudo apt update
sudo apt install -y build-essential git curl acl

# 6. Настройка Git от имени SECOND_USERNAME
sudo -u "$SECOND_USERNAME" git config --global user.name "$GIT_NAME"
sudo -u "$SECOND_USERNAME" git config --global user.email "$GIT_EMAIL"
sudo -u "$SECOND_USERNAME" git config --global core.autocrlf input
sudo -u "$SECOND_USERNAME" git config --global alias.hist 'log --pretty=format:"%Cred%h%Creset %C(green)(%ad)%Creset
%s%C(yellow)%d%Creset  %C(bold blue)[%an] " --graph --date=format-local:"%d-%m-%Y %H:%M"'
sudo -u "$SECOND_USERNAME" git config --global alias.tree 'log --graph --pretty=format:"%C(yellow)%h %Creset%Cgreen(%ad) %cr
%C(blue)<%an>%Creset%d%n%s%n" --abbrev-commit --date=format-local:"%d-%m-%Y %H:%M"'
sudo -u "$SECOND_USERNAME" git config --global alias.st status
sudo -u "$SECOND_USERNAME" git config --global alias.c 'commit -m'
sudo -u "$SECOND_USERNAME" git config --global init.defaultBranch main
sudo -u "$SECOND_USERNAME" git config --global color.status always
sudo -u "$SECOND_USERNAME" git config --global status.short false
sudo -u "$SECOND_USERNAME" git config --global status.branch true

# Настройка ACL для доступа MAIN_USERNAME к папке SECOND_USERNAME
sudo setfacl -R -m "u:${MAIN_USERNAME}:rwx,m:rwx" "/home/$SECOND_USERNAME/"
sudo setfacl -R -d -m "u:${MAIN_USERNAME}:rwx,m:rwx" "/home/$SECOND_USERNAME/"

# 7. Права на домашнюю директорию
sudo chmod 755 "/home/$SECOND_USERNAME"
sudo chmod -R a+rX "/home/$SECOND_USERNAME"

# Права на домашнюю директорию основного пользователя
chmod 750 "/home/$MAIN_USERNAME"
# Ограничение доступа к смонтированному диску C
chmod 750 /mnt/c

# 9. Проверка
getfacl "/home/$SECOND_USERNAME"