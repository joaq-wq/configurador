#!/bin/bash

#=============================
# FTP Installer & Manager
#=============================

# Função para animação de download
download_animation() {
    echo -ne "Baixando vsftpd...\n"
    for i in {1..100}; do
        sleep 0.02
        echo -ne "[$(printf '%0.s#' $(seq 1 $((i/2))))$(printf '%0.s-' $(seq 1 $((50-(i/2)))))] $i%\r"
    done
    echo -e "\nDownload concluído!\n"
}

#=============================
# Instalação
#=============================
install_ftp() {
    clear
    download_animation
    sudo apt update > /dev/null 2>&1
    sudo apt install -y vsftpd > /dev/null 2>&1
    sudo systemctl enable vsftpd
    sudo systemctl start vsftpd
    echo "✅ vsftpd instalado e iniciado com sucesso."
    sleep 2
}

#=============================
# Menu de gerenciamento
#=============================
manage_ftp() {
    while true; do
        clear
        echo "====== Gerenciador FTP (vsftpd) ======"
        echo "1) Ver status do FTP"
        echo "2) Ativar FTP"
        echo "3) Desativar FTP"
        echo "4) Editar configurações principais"
        echo "5) Reiniciar FTP"
        echo "6) Sair"
        echo "======================================="
        read -p "Escolha uma opção: " opcao

        case $opcao in
            1)
                systemctl status vsftpd
                read -p "Pressione ENTER para voltar ao menu..."
                ;;
            2)
                sudo systemctl start vsftpd
                echo "✅ FTP Ativado"
                sleep 2
                ;;
            3)
                sudo systemctl stop vsftpd
                echo "❌ FTP Desativado"
                sleep 2
                ;;
            4)
                config_menu
                ;;
            5)
                sudo systemctl restart vsftpd
                echo "🔄 FTP Reiniciado"
                sleep 2
                ;;
            6)
                echo "Saindo..."
                sleep 1
                break
                ;;
            *)
                echo "Opção inválida!"
                sleep 2
                ;;
        esac
    done
}

#=============================
# Configurações do FTP
#=============================
config_menu() {
    while true; do
        clear
        echo "===== Configurações do vsftpd ====="
        echo "1) Permitir acesso anônimo"
        echo "2) Permitir login de usuários locais"
        echo "3) Restringir usuários às suas pastas (chroot)"
        echo "4) Ativar SSL/TLS"
        echo "5) Alterar porta padrão (21)"
        echo "6) Limitar conexões simultâneas"
        echo "7) Voltar"
        echo "====================================="
        read -p "Escolha uma opção: " conf

        case $conf in
            1)
                toggle_option "anonymous_enable"
                ;;
            2)
                toggle_option "local_enable"
                ;;
            3)
                toggle_option "chroot_local_user"
                ;;
            4)
                configure_ssl
                ;;
            5)
                change_port
                ;;
            6)
                configure_limit
                ;;
            7)
                break
                ;;
            *)
                echo "Opção inválida!"
                sleep 2
                ;;
        esac
    done
}

#=============================
# Funções auxiliares
#=============================
toggle_option() {
    option="$1"
    file="/etc/vsftpd.conf"
    value=$(grep -E "^$option=" "$file" | awk -F= '{print $2}')
    if [[ "$value" == "YES" ]]; then
        sudo sed -i "s/^$option=YES/$option=NO/" $file
        echo "❌ $option desativado."
    else
        sudo sed -i "s/^$option=NO/$option=YES/" $file 2>/dev/null || echo "$option=YES" | sudo tee -a $file > /dev/null
        echo "✅ $option ativado."
    fi
    sudo systemctl restart vsftpd
    sleep 2
}

configure_ssl() {
    echo "Ativando SSL..."
    sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/ssl/private/vsftpd.key \
        -out /etc/ssl/certs/vsftpd.crt \
        -subj "/C=BR/ST=SP/L=SP/O=FTPServer/OU=TI/CN=ftp.local"
    
    sudo sed -i '/^ssl_enable/d' /etc/vsftpd.conf
    echo "ssl_enable=YES" | sudo tee -a /etc/vsftpd.conf > /dev/null
    echo "rsa_cert_file=/etc/ssl/certs/vsftpd.crt" | sudo tee -a /etc/vsftpd.conf > /dev/null
    echo "rsa_private_key_file=/etc/ssl/private/vsftpd.key" | sudo tee -a /etc/vsftpd.conf > /dev/null
    echo "require_ssl_reuse=NO" | sudo tee -a /etc/vsftpd.conf > /dev/null
    echo "ssl_ciphers=HIGH" | sudo tee -a /etc/vsftpd.conf > /dev/null
    echo "✅ SSL ativado!"
    sudo systemctl restart vsftpd
    sleep 2
}

change_port() {
    read -p "Digite a nova porta para o FTP: " porta
    sudo sed -i '/^listen_port/d' /etc/vsftpd.conf
    echo "listen_port=$porta" | sudo tee -a /etc/vsftpd.conf > /dev/null
    sudo ufw allow $porta/tcp
    echo "✅ Porta alterada para $porta"
    sudo systemctl restart vsftpd
    sleep 2
}

configure_limit() {
    read -p "Digite o número máximo de conexões: " conex
    sudo sed -i '/^max_clients/d' /etc/vsftpd.conf
    echo "max_clients=$conex" | sudo tee -a /etc/vsftpd.conf > /dev/null
    echo "✅ Limite de conexões definido para $conex"
    sudo systemctl restart vsftpd
    sleep 2
}

#=============================
# Menu principal
#=============================
while true; do
    clear
    echo "====== Servidor FTP ======"
    echo "1) Instalar FTP"
    echo "2) Gerenciar FTP"
    echo "3) Sair"
    echo "=========================="
    read -p "Escolha uma opção: " main

    case $main in
        1) install_ftp ;;
        2) manage_ftp ;;
        3) echo "Saindo..."; sleep 1; exit ;;
        *) echo "Opção inválida!"; sleep 2 ;;
    esac
done
