
#!/bin/bash

# Verifica se dialog está instalado
if ! command -v dialog &> /dev/null; then
    echo "Instalando dialog..."
    apt update && apt install -y dialog
fi

# Loop do menu principal
while true; do
    OPCAO=$(dialog --stdout --menu "🛠️ MENU PRINCIPAL - CONFIGURADOR DE SERVIÇOS" 15 60 9 \
    1 "Configurar SSH" \
    2 "Configurar DNS" \
    3 "Configurar DHCP" \
    4 "Configurar FTP" \
    5 "Configurar Proxy" \
    6 "Configurar Firewall" \
    7 "Configurar SQL (Banco de Dados)" \
    8 "Configurar Telnet" \
    0 "Sair")

    case $OPCAO in
        1) bash configurar_ssh.sh ;;   # Script do SSH
        2) bash configurar_dns.sh ;;   # Script do DNS
        3) bash configurar_dhcp.sh ;;  # Script do DHCP
        4) bash configurar_ftp.sh ;;   # Script do FTP
        5) bash configurar_proxy.sh ;; # Script do Proxy
        6) bash configurar_firewall.sh ;; # Script do Firewall
        7) bash configurar_sql.sh ;;   # Script do SQL
        8) bash configurar_telnet.sh ;;# Script do Telnet
        0) clear; exit ;;             # Sair do programa
    esac
done
