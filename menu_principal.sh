#!/bin/bash

# ===========================
# MENU MASTER DE SERVIÇOS
# ===========================

# Verifica e instala o dialog, se necessário
if ! command -v dialog &> /dev/null; then
    (
    echo 20; echo "Atualizando pacotes..."; sleep 1
    apt update -y &>/dev/null
    echo 60; echo "Instalando Dialog..."; sleep 1
    apt install -y dialog &>/dev/null
    echo 100; echo "Finalizando..."; sleep 1
    ) | dialog --gauge "⏳ Instalando dependências..." 10 60 0
fi

# Loop do menu
while true; do
    OPCAO=$(dialog --stdout --menu "🛠️ MENU MASTER DE CONFIGURAÇÃO" 15 60 9 \
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
        3) dialog --msgbox "🚧 Em construção..." 6 40 ;;
        4) dialog --msgbox "🚧 Em construção..." 6 40 ;;
        5) dialog --msgbox "🚧 Em construção..." 6 40 ;;
        6) dialog --msgbox "🚧 Em construção..." 6 40 ;;
        7) dialog --msgbox "🚧 Em construção..." 6 40 ;;
        8) dialog --msgbox "🚧 Em construção..." 6 40 ;;
        0) clear; exit ;;
        *) dialog --msgbox "❌ Opção inválida!" 6 40 ;;
    esac
done
