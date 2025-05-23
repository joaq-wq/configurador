#!/bin/bash

# =============================
# MENU MASTER DE CONFIGURAÇÃO
# =============================

# Verifica e instala o dialog se não tiver
if ! command -v dialog &> /dev/null; then
    echo "Instalando dialog..."
    apt update | dialog --gauge "Atualizando pacotes..." 10 50 30
    apt install -y dialog | dialog --gauge "Instalando dialog..." 10 50 70
fi

# Loop do menu
while true; do
    OPCAO=$(dialog --stdout --menu "🛠️ Menu de Serviços" 15 60 9 \
    1 "Configurar SSH" \
    2 "Configurar DNS" \
    3 "Configurar FTP" \
    4 "Configurar DHCP" \
    5 "Configurar Proxy" \
    6 "Configurar SQL" \
    7 "Configurar Firewall" \
    8 "Configurar Telnet" \
    0 "Sair")

    case $OPCAO in
        1) bash configurar_ssh.sh ;;
        2) bash configurar_dns.sh ;;
        0) clear; exit ;;
        *) dialog --msgbox "Opção em desenvolvimento" 6 40 ;;
    esac
done
