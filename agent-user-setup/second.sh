#SECOND_USERNAME="abobapc"
#MAIN_USERNAME="abobapc"
#WINDOWS_USER=""
#sed -i 's/\r$//' second.sh

if [ -f .env ]; then
    set -a             # Автоматически экспортировать все объявляемые переменные (короткий аналог set -o allexport)
    source .env        # Считать файл конфигурации
    set +a             # Отключить автоэкспорт
fi

# Проверка текущих монтирований drvfs
mount | grep drvfs
ls -ld /mnt/c /mnt/d

# Создание каталога и bind-mount для конфигурации Oh My Pi
sudo mkdir -p /mnt/c/Users/${WINDOWS_USERNAME}/.omp /mnt/c/Users/${WINDOWS_USERNAME}/.agents
sudo mkdir -p /home/${SECOND_USERNAME}/.omp /home/${SECOND_USERNAME}/.agents

sudo chmod -R 777 "/mnt/c/Users/${WINDOWS_USERNAME}/.omp" "/mnt/c/Users/${WINDOWS_USERNAME}/.agents"

sudo mount --bind "/mnt/c/Users/$WINDOWS_USERNAME/.omp" "/home/$SECOND_USERNAME/.omp"
sudo mount --bind "/mnt/c/Users/$WINDOWS_USERNAME/.agents" "/home/$SECOND_USERNAME/.agents"

# 6. Проверка результата
findmnt -nT "/home/${SECOND_USERNAME}/.omp"
findmnt -nT "/home/${SECOND_USERNAME}/.agents"

