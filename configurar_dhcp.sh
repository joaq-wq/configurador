#!/bin/bash

CONF_DHCP="/etc/dhcp/dhcpd.conf"
BACKUP_DHCP="/etc/dhcp/dhcpd.conf.bak.$(date +%F-%H%M%S)"
INTERFACES_FILE="/etc/default/isc-dhcp-server"

backup_conf() {
    cp "$CONF_DHCP" "$BACKUP_DHCP"
    dialog --msgbox "Backup criado: $BACKUP_DHCP" 6 50
}

validar_ip() {
    local ip=$1
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        for octet in $(echo $ip | tr '.' ' '); do
            if (( octet < 0 || octet > 255 )); then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

validar_mac() {
    local mac=$1
    [[ $mac =~ ^([A-Fa-f0-9]{2}:){5}[A-Fa-f0-9]{2}$ ]]
}

instalar_dhcp() {
    if ! dpkg -l | grep -qw isc-dhcp-server; then
        apt-get update && apt-get install -y isc-dhcp-server
        dialog --msgbox "ISC DHCP Server instalado com sucesso!" 6 50
    else
        dialog --msgbox "ISC DHCP Server já está instalado." 6 50
    fi
}

configurar_interface() {
    dialog --inputbox "Interfaces de rede disponíveis:\n$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo)" 10 50 2> /tmp/interface
    INTERFACE=$(< /tmp/interface)

    if [ -n "$INTERFACE" ]; then
        sed -i "s/^INTERFACESv4=.*/INTERFACESv4=\"$INTERFACE\"/" $INTERFACES_FILE
        dialog --msgbox "Interface configurada para $INTERFACE" 6 50
    fi
}

configurar_subnet() {
    REDE=$(dialog --stdout --inputbox "Informe a rede (ex: 192.168.1.0):" 8 40)
    validar_ip "$REDE" || { dialog --msgbox "IP de rede inválido!" 6 40; return; }

    MASCARA=$(dialog --stdout --inputbox "Informe a máscara de sub-rede (ex: 255.255.255.0):" 8 40)
    validar_ip "$MASCARA" || { dialog --msgbox "Máscara inválida!" 6 40; return; }

    RANGE_INI=$(dialog --stdout --inputbox "Informe o IP inicial do range:" 8 40)
    validar_ip "$RANGE_INI" || { dialog --msgbox "IP inicial inválido!" 6 40; return; }

    RANGE_FIM=$(dialog --stdout --inputbox "Informe o IP final do range:" 8 40)
    validar_ip "$RANGE_FIM" || { dialog --msgbox "IP final inválido!" 6 40; return; }

    GATEWAY=$(dialog --stdout --inputbox "Informe o gateway:" 8 40)
    validar_ip "$GATEWAY" || { dialog --msgbox "Gateway inválido!" 6 40; return; }

    DNS=$(dialog --stdout --inputbox "Informe o servidor DNS:" 8 40)
    validar_ip "$DNS" || { dialog --msgbox "DNS inválido!" 6 40; return; }

    backup_conf

    cat <<EOF >> $CONF_DHCP

subnet $REDE netmask $MASCARA {
    range $RANGE_INI $RANGE_FIM;
    option routers $GATEWAY;
    option subnet-mask $MASCARA;
    option domain-name-servers $DNS;
}
EOF

    dialog --msgbox "Configuração de subnet adicionada." 6 40
    systemctl restart isc-dhcp-server
}

adicionar_reserva() {
    HOSTNAME=$(dialog --stdout --inputbox "Informe o nome do host:" 8 40)
    MAC=$(dialog --stdout --inputbox "Informe o endereço MAC:" 8 40)
    validar_mac "$MAC" || { dialog --msgbox "MAC inválido!" 6 40; return; }

    IP_FIXO=$(dialog --stdout --inputbox "Informe o IP fixo:" 8 40)
    validar_ip "$IP_FIXO" || { dialog --msgbox "IP inválido!" 6 40; return; }

    backup_conf

    cat <<EOF >> $CONF_DHCP

host $HOSTNAME {
    hardware ethernet $MAC;
    fixed-address $IP_FIXO;
}
EOF

    dialog --msgbox "Reserva de IP adicionada para $HOSTNAME." 6 40
    systemctl restart isc-dhcp-server
}

visualizar_configuracao() {
    dialog --textbox $CONF_DHCP 20 70
}

gerenciar_servico() {
    OP=$(dialog --stdout --menu "Gerenciar serviço DHCP" 10 40 3 \
        1 "Iniciar" \
        2 "Parar" \
        3 "Reiniciar")

    case $OP in
        1) systemctl start isc-dhcp-server && dialog --msgbox "DHCP iniciado!" 6 40 ;;
        2) systemctl stop isc-dhcp-server && dialog --msgbox "DHCP parado!" 6 40 ;;
        3) systemctl restart isc-dhcp-server && dialog --msgbox "DHCP reiniciado!" 6 40 ;;
    esac
}

desinstalar_dhcp() {
    dialog --yesno "Tem certeza que deseja desinstalar o DHCP?" 6 40
    if [ $? -eq 0 ]; then
        apt-get remove --purge -y isc-dhcp-server
        dialog --msgbox "ISC DHCP Server desinstalado!" 6 40
    fi
}

while true; do
    OPCAO=$(dialog --stdout --menu "⚙️ Gerenciar DHCP (versão melhorada)" 15 50 8 \
        1 "Instalar DHCP" \
        2 "Configurar Interface de Rede" \
        3 "Configurar Subnet (Range de IP)" \
        4 "Adicionar Reserva de IP (por MAC)" \
        5 "Ver Configuração Atual" \
        6 "Gerenciar Serviço (Start/Stop/Restart)" \
        7 "Desinstalar DHCP" \
        0 "Sair")

    [ $? -ne 0 ] && break

    case $OPCAO in
        1) instalar_dhcp ;;
        2) configurar_interface ;;
        3) configurar_subnet ;;
        4) adicionar_reserva ;;
        5) visualizar_configuracao ;;
        6) gerenciar_servico ;;
        7) desinstalar_dhcp ;;
        0) clear; exit 0 ;;
    esac
done
