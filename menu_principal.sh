#!/bin/bash

# ===========================
# MENU MASTER DE SERVIÇOS
# ===========================

# Verifica se é root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Execute como root ou usando sudo."
    exit 1
fi

# Verifica e instala o dialog, se necessário
if ! command -v dialog &> /dev/null; then
    (
    echo 20; echo "Atualizando pacotes..."; sleep 1
    apt update -y &>/dev/null
    echo 60; echo "Instalando Dialog..."; sleep 1
    apt install -y dialog &>/dev/null
    echo 100; echo "Finalizando..." ; sleep 1
    ) | dialog --gauge "⏳ Instalando dependências..." 10 60 0
fi

while true; do
    OPCAO=$(dialog --stdout --menu "🛠️ MENU MASTER DE CONFIGURAÇÃO" 20 70 9 \
    1 "Configurar SSH" \
    2 "Configurar DNS" \
    3 "Configurar FTP" \
    4 "Configurar DHCP" \
    5 "Configurar Proxy" \
    6 "Configurar SQL" \
    7 "Configurar Firewall" \
    8 "Configurar Telnet" \
    0 "Sair")

    RET=$?

    # Se cancelar ou apertar ESC, dialog retorna código != 0, então sai do script
    if [ $RET -ne 0 ]; then
        clear
        exit 0
    fi

    case $OPCAO in
        1) bash ./configurar_ssh.sh ;;
        2) dialog --msgbox "🚧 Em construção..." 6 40 ;;
        3) dialog --msgbox "🚧 Em construção..." 6 40 ;;
        4) dialog --msgbox "🚧 Em construção..." 6 40 ;;
        5) dialog --msgbox "🚧 Em construção..." 6 40 ;;
        6) dialog --msgbox "🚧 Em construção..." 6 40 ;;
        7) dialog --msgbox "🚧 Em construção..." 6 40 ;;
        8) dialog --msgbox "🚧 Em construção..." 6 40 ;;
        0) clear; exit 0 ;;
        *) dialog --msgbox "❌ Opção inválida!" 6 40 ;;
    esac
done
