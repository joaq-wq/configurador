#!/bin/bash

# Script DNS Interativo com instalação e configuração via dialog + barra de progresso real

# Verificar root
if [ "$EUID" -ne 0 ]; then
    echo "Execute como root ou com sudo."
    exit 1
fi

# Verificar se dialog está instalado
if ! command -v dialog &> /dev/null; then
    echo "Instalando dialog..."
    apt update && apt install dialog
fi

# Variáveis
CONF_LOCAL="/etc/bind/named.conf.local"
CONF_OPTIONS="/etc/bind/named.conf.options"
DIR_ZONA="/etc/bind"

ARQ_DOMINIO="/tmp/dns_zona_direta.txt"
ARQ_REDE="/tmp/dns_zona_reversa.txt"

DOMINIO=$( [ -f "$ARQ_DOMINIO" ] && cat "$ARQ_DOMINIO" || echo "" )
REDE=$( [ -f "$ARQ_REDE" ] && cat "$ARQ_REDE" || echo "" )

# Calcula zona reversa
calc_zona_reversa() {
    echo "$REDE" | awk -F. '{print $3"."$2"."$1".in-addr.arpa"}'
}

# Instala o bind9 com barra de progresso real
instalar_bind9() {
    if dpkg -s bind9 &>/dev/null; then
        dialog --msgbox "BIND9 já está instalado." 6 40
        return
    fi

    apt update -qq

    (
    apt install -y bind9 bind9utils bind9-doc > /tmp/bind_install.log 2>&1 &
    PID=$!

    {
        while kill -0 $PID 2>/dev/null; do
            for i in $(seq 0 100); do
                echo $i
                sleep 0.05
                kill -0 $PID 2>/dev/null || break
            done
        done
        echo 100
    } | dialog --gauge "Instalando BIND9 DNS Server..." 10 60 0

    wait $PID
    RET=$?

    if [ $RET -eq 0 ]; then
        dialog --msgbox "BIND9 instalado com sucesso!" 6 50
    else
        dialog --msgbox "Erro na instalação. Veja /tmp/bind_install.log" 8 60
        exit 1
    fi
    )
}

# Atualiza named.conf.local
atualiza_named_conf_local() {
    cat > "$CONF_LOCAL" <<EOF
// Arquivo gerado automaticamente

zone "$DOMINIO" {
    type master;
    file "$DIR_ZONA/db.$DOMINIO";
};

zone "$(calc_zona_reversa)" {
    type master;
    file "$DIR_ZONA/db.$(echo $REDE | tr '.' '-')"; 
};
EOF
}

# Cria zona direta
cria_zona_direta() {
    local ip_srv=$(hostname -I | awk '{print $1}')
    cat > "$DIR_ZONA/db.$DOMINIO" <<EOF
\$TTL    604800
@       IN      SOA     $DOMINIO. root.$DOMINIO. (
                              2         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      NS      $DOMINIO.
@       IN      A       $ip_srv
www     IN      A       $ip_srv
ftp     IN      A       $ip_srv
EOF
}

# Cria zona reversa
cria_zona_reversa() {
    local zona_rev=$(echo $REDE | tr '.' '-')
    local ip_srv=$(hostname -I | awk '{print $1}')
    local ult_octeto=$(echo $ip_srv | awk -F. '{print $4}')
    cat > "$DIR_ZONA/db.$zona_rev" <<EOF
\$TTL    604800
@       IN      SOA     $DOMINIO. root.$DOMINIO. (
                              2         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      NS      $DOMINIO.
$ult_octeto       IN      PTR     $DOMINIO.
EOF
}

# Configura named.conf.options
configura_named_conf_options() {
    IP_SERVIDOR=$(dialog --stdout --inputbox "Digite o IP do servidor DNS (ex: 192.168.0.1):" 8 50)
    [ -z "$IP_SERVIDOR" ] && return
    REDE_LOCAL=$(dialog --stdout --inputbox "Digite a rede local (ex: 192.168.0.0/24):" 8 50)
    [ -z "$REDE_LOCAL" ] && return

    cat > "$CONF_OPTIONS" <<EOF
options {
    directory "/var/cache/bind";

    recursion yes;
    allow-recursion { 127.0.0.1; $REDE_LOCAL; };
    allow-query { 127.0.0.1; $REDE_LOCAL; };

    listen-on { 127.0.0.1; $IP_SERVIDOR; };

    forwarders {
        8.8.8.8;
        8.8.4.4;
    };

    dnssec-validation auto;

    auth-nxdomain no;
    listen-on-v6 { any; };
};
EOF

    dialog --msgbox "Arquivo named.conf.options atualizado." 6 50
    systemctl restart bind9
}

# Gerenciar resolv.conf
gerenciar_resolv_conf() {
    OP=$(dialog --stdout --menu "Gerenciar /etc/resolv.conf" 12 50 4 \
        1 "Adicionar DNS" \
        2 "Remover DNS" \
        0 "Voltar")

    case $OP in
        1)
            DNS_DOM=$(dialog --stdout --inputbox "Informe o domínio (ex: grau.local):" 8 40)
            DNS_IP=$(dialog --stdout --inputbox "Informe o IP do servidor (ex: 192.168.0.1):" 8 40)
            echo "nameserver $DNS_IP" >> /etc/resolv.conf
            echo "search $DNS_DOM" >> /etc/resolv.conf
            dialog --msgbox "DNS $DNS_IP ($DNS_DOM) adicionado ao resolv.conf" 6 50
            ;;
        2)
            TEMP=$(mktemp)
            grep -v "nameserver" /etc/resolv.conf | grep -v "search" > "$TEMP"
            mv "$TEMP" /etc/resolv.conf
            dialog --msgbox "Entradas removidas de resolv.conf" 6 50
            ;;
        0) ;;
    esac
}

# Menu principal
while true; do
    OPCAO=$(dialog --stdout --menu "📡 Gerenciamento DNS" 15 60 5 \
        1 "Instalar DNS" \
        2 "Configurar DNS" \
        0 "Sair")

    case $OPCAO in
        1)
            instalar_bind9
            ;;
        2)
            OP2=$(dialog --stdout --menu "Configurar DNS" 15 60 6 \
                1 "Configurar Zona Direta" \
                2 "Configurar Zona Reversa" \
                3 "Configurar named.conf.options" \
                4 "Gerenciar resolv.conf" \
                5 "Aplicar configurações e reiniciar" \
                0 "Voltar")
            case $OP2 in
                1)
                    DOMINIO=$(dialog --stdout --inputbox "Informe o domínio (ex: grau.local):" 8 50 "$DOMINIO")
                    echo "$DOMINIO" > "$ARQ_DOMINIO"
                    cria_zona_direta
                    atualiza_named_conf_local
                    dialog --msgbox "Zona direta configurada para $DOMINIO" 6 50
                    ;;
                2)
                    REDE=$(dialog --stdout --inputbox "Informe os 3 primeiros octetos da rede (ex: 192.168.0):" 8 50 "$REDE")
                    echo "$REDE" > "$ARQ_REDE"
                    cria_zona_reversa
                    atualiza_named_conf_local
                    dialog --msgbox "Zona reversa configurada para $(calc_zona_reversa)" 6 50
                    ;;
                3)
                    configura_named_conf_options
                    ;;
                4)
                    gerenciar_resolv_conf
                    ;;
                5)
                    systemctl restart bind9
                    dialog --msgbox "BIND9 reiniciado e configurações aplicadas." 6 50
                    ;;
                0) ;;
            esac
            ;;
        0)
            clear
            exit
            ;;
    esac
done
