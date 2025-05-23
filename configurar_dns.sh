#!/bin/bash

# Script DNS Interativo com dialog e configuração completa

# Verifica se dialog está instalado
if ! command -v dialog &> /dev/null; then
    echo "Instalando dialog..."
    apt update && apt install -y dialog
fi

CONF_LOCAL="/etc/bind/named.conf.local"
CONF_OPTIONS="/etc/bind/named.conf.options"
DIR_ZONA="/etc/bind"

# Arquivos temporários para salvar nome zona e rede
ARQ_DOMINIO="/tmp/dns_zona_direta.txt"
ARQ_REDE="/tmp/dns_zona_reversa.txt"

# Carrega domínio e rede salvos
DOMINIO=$( [ -f "$ARQ_DOMINIO" ] && cat "$ARQ_DOMINIO" || echo "" )
REDE=$( [ -f "$ARQ_REDE" ] && cat "$ARQ_REDE" || echo "" )

# Calcula zona reversa padrão a partir da rede
calc_zona_reversa() {
    # espera rede no formato 192.168.0 (3 octetos)
    echo "$REDE" | awk -F. '{print $3"."$2"."$1".in-addr.arpa"}'
}

# Atualiza named.conf.local com as zonas
atualiza_named_conf_local() {
    sudo bash -c "cat > $CONF_LOCAL" <<EOF
// Configuração automática gerada pelo script

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

# Cria arquivo de zona direta
cria_zona_direta() {
    local ip_srv=$(hostname -I | awk '{print $1}')
    sudo bash -c "cat > $DIR_ZONA/db.$DOMINIO" <<EOF
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

# Cria arquivo de zona reversa
cria_zona_reversa() {
    local zona_rev=$(echo $REDE | tr '.' '-')
    local ip_srv=$(hostname -I | awk '{print $1}')
    sudo bash -c "cat > $DIR_ZONA/db.$zona_rev" <<EOF
\$TTL    604800
@       IN      SOA     $DOMINIO. root.$DOMINIO. (
                              2         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      NS      $DOMINIO.
1       IN      PTR     $DOMINIO.
EOF
}

# Configura named.conf.options com IP e rede
configura_named_conf_options() {
    IP_SERVIDOR=$(dialog --stdout --inputbox "Digite o IP do servidor DNS (ex: 192.168.0.1):" 8 50)
    [ -z "$IP_SERVIDOR" ] && return
    REDE_LOCAL=$(dialog --stdout --inputbox "Digite a rede local (ex: 192.168.0.0/24):" 8 50)
    [ -z "$REDE_LOCAL" ] && return

    sudo bash -c "cat > $CONF_OPTIONS" <<EOF
options {
    directory \"/var/cache/bind\";

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
    sudo systemctl restart bind9
}

# Atualiza /etc/resolv.conf para usar o DNS local
configura_resolv_conf() {
    sudo mv /etc/resolv.conf /etc/resolv.conf.bkp
    sudo bash -c "cat > /etc/resolv.conf" <<EOF
nameserver $IP_SERVIDOR
search $DOMINIO
EOF
    dialog --msgbox "/etc/resolv.conf configurado para usar $IP_SERVIDOR" 6 50
}

# Menu principal
while true; do
    DOMINIO_ATUAL=${DOMINIO:-"nenhuma"}
    REDE_ATUAL=${REDE:-"nenhuma"}

    OPCAO=$(dialog --stdout --menu "📡 Configuração DNS" 15 60 5 \
        1 "Configurar Zona Direta (atual: $DOMINIO_ATUAL)" \
        2 "Configurar Zona Reversa (atual: $REDE_ATUAL)" \
        3 "Configurar named.conf.options" \
        4 "Aplicar configurações e reiniciar BIND" \
        0 "Sair")

    case $OPCAO in
        1)
            DOMINIO_NOVO=$(dialog --stdout --inputbox "Informe o nome da zona direta (ex: grau.local):" 8 50 "$DOMINIO")
            [ -z "$DOMINIO_NOVO" ] && continue
            DOMINIO="$DOMINIO_NOVO"
            echo "$DOMINIO" > "$ARQ_DOMINIO"
            cria_zona_direta
            atualiza_named_conf_local
            dialog --msgbox "Zona direta configurada para $DOMINIO" 6 50
            ;;
        2)
            REDE_NOVA=$(dialog --stdout --inputbox "Informe os 3 primeiros octetos da rede (ex: 192.168.0):" 8 50 "$REDE")
            [ -z "$REDE_NOVA" ] && continue
            REDE="$REDE_NOVA"
            echo "$REDE" > "$ARQ_REDE"
            cria_zona_reversa
            atualiza_named_conf_local
            dialog --msgbox "Zona reversa configurada para $(calc_zona_reversa)" 6 60
            ;;
        3)
            configura_named_conf_options
            ;;
        4)
            sudo systemctl restart bind9
            configura_resolv_conf
            dialog --msgbox "Configurações aplicadas e BIND reiniciado!" 6 50
            ;;
        0)
            clear
            exit
            ;;
        *)
            dialog --msgbox "Opção inválida!" 5 40
            ;;
    esac
done
