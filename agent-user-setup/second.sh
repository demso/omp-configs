# Проверка текущих монтирований drvfs
mount | grep drvfs
ls -ld /mnt/c /mnt/d

# Проверка разделения прав между пользователями
sudo -u "$SECOND_USERNAME" ls /mnt/c || echo "Access denied as expected"
sudo -u "$SECOND_USERNAME" touch /mnt/d/test && echo "Write access confirmed"
sudo -u "$SECOND_USERNAME" rm /mnt/d/test

# Создание каталога и bind-mount для конфигурации Oh My Pi
mkdir -p "/home/$SECOND_USERNAME/.omp"
sudo mount --bind "/mnt/c/Users/$MAIN_USERNAME/.omp" "/home/$SECOND_USERNAME/.omp"

# Запуск сторонних скриптов настройки
sudo -v && bash wsl-setup.sh

# Перезапуск оболочки для обновления PATH и переменного окружения
exec bash

command -v python fd bat eza fzf rg jq git go psql node npm pnpm bun uv dotnet dotnet-ef csharp-ls