#!/bin/bash

# =============================
# Script Master de DNS Interativo
# =============================

# Verifica se o dialog está instalado
if ! command -v dialog &> /dev/null; then
    echo "Instalando dialog..."
    apt update && apt install -y dialog
fi

# Instala Bind9 se não tiver
if ! dpkg -l | grep -q bind9; then
    dialog --title "Instalação do DNS" --msgbox "O Bind9 não está instalado. Instalando agora..." 7 50
    apt update && apt install -y bind9 bind9utils bind9-doc
fi

# Arquivos importantes
CONF_LOCAL="/etc/bind/named.conf.local"
DIR_ZONA="/etc/bind"
ARQ_DOMINIO="/tmp/dns_zona_direta.txt"
ARQ_REDE="/tmp/dns_zona_reversa.txt"

# Carrega configurações anteriores
DOMINIO=$( [ -f "$ARQ_DOMINIO" ] && cat "$ARQ_DOMINIO" || echo "" )
REDE=$( [ -f "$ARQ_REDE" ] && cat "$ARQ_REDE" || echo "" )
ZONA_REVERSE=$( [ -n "$REDE" ] && echo "$REDE" | awk -F. '{print $3"."$2"."$1".in-addr.arpa"}' )

# =========================
# Funções
# =========================

# Configura named.conf.options
ajustar_named_conf_options() {
    local IP_SERVIDOR REDE_LOCAL
    IP_SERVIDOR=$(dialog --stdout --inputbox "Digite o IP do servidor DNS (ex: 192.168.0.1):" 8 50)
    [ -z "$IP_SERVIDOR" ] && return
    REDE_LOCAL=$(dialog --stdout --inputbox "Digite a rede local com máscara (ex: 192.168.0.0/24):" 8 50)
    [ -z "$REDE_LOCAL" ] && return

    sudo bash -c "cat > /etc/bind/named.conf.options" <<EOF
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

    dialog --msgbox "Arquivo named.conf.options configurado!" 6 50
    sudo systemctl restart bind9
}

# Atualiza ou cria a zona direta
configurar_zona_direta() {
    local DOMINIO_NOVO
    DOMINIO_NOVO=$(dialog --stdout --inputbox "Nome da Zona Direta (ex: empresa.local):" 8 50 "$DOMINIO")
    [ -z "$DOMINIO_NOVO" ] && return

    if [[ "$DOMINIO_NOVO" != "$DOMINIO" && -n "$DOMINIO" ]]; then
        # Se mudou o nome da zona, remove anterior
        sudo sed -i "/zone \"$DOMINIO\"/,/};/d" "$CONF_LOCAL"
        sudo rm -f "$DIR_ZONA/db.$DOMINIO"
    fi

    DOMINIO="$DOMINIO_NOVO"
    echo "$DOMINIO" > "$ARQ_DOMINIO"

    ZONA_DIR="$DIR_ZONA/db.$DOMINIO"

    if [ ! -f "$ZONA_DIR" ]; then
        cat <<EOF | sudo tee "$ZONA_DIR" > /dev/null
\$TTL    604800
@       IN      SOA     ns.$DOMINIO. root.$DOMINIO. (
                              2         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      NS      ns.$DOMINIO.
ns      IN      A       $(hostname -I | awk '{print $1}')
EOF
    fi

    if ! grep -q "zone \"$DOMINIO\"" "$CONF_LOCAL"; then
        echo "zone \"$DOMINIO\" {
    type master;
    file \"$ZONA_DIR\";
};" | sudo tee -a "$CONF_LOCAL" > /dev/null
    fi

    dialog --msgbox "Zona direta configurada: $DOMINIO" 6 50
}

# Atualiza ou cria a zona reversa
configurar_zona_reversa() {
    local REDE_NOVA
    REDE_NOVA=$(dialog --stdout --inputbox "IP da rede para zona reversa (ex: 192.168.0):" 8 50 "$REDE")
    [ -z "$REDE_NOVA" ] && return

    local ZONA_REVERSE_NOVA
    ZONA_REVERSE_NOVA=$(echo "$REDE_NOVA" | awk -F. '{print $3"."$2"."$1".in-addr.arpa"}')

    if [[ "$REDE_NOVA" != "$REDE" && -n "$REDE" ]]; then
        # Remove zona reversa anterior
        sudo sed -i "/zone \"$ZONA_REVERSE\"/,/};/d" "$CONF_LOCAL"
        sudo rm -f "$DIR_ZONA/db.$(echo $REDE | tr '.' '-')"
    fi

    REDE="$REDE_NOVA"
    echo "$REDE" > "$ARQ_REDE"

    ZONA_REVERSE="$ZONA_REVERSE_NOVA"
    ZONA_REV="$DIR_ZONA/db.$(echo $REDE | tr '.' -)"

    if [ ! -f "$ZONA_REV" ]; then
        cat <<EOF | sudo tee "$ZONA_REV" > /dev/null
\$TTL    604800
@       IN      SOA     ns.$DOMINIO. root.$DOMINIO. (
                              2         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      NS      ns.$DOMINIO.
EOF
    fi

    if ! grep -q "zone \"$ZONA_REVERSE\"" "$CONF_LOCAL"; then
        echo "zone \"$ZONA_REVERSE\" {
    type master;
    file \"$ZONA_REV\";
};" | sudo tee -a "$CONF_LOCAL" > /dev/null
    fi

    dialog --msgbox "Zona reversa configurada: $ZONA_REVERSE" 6 60
}

# Adiciona registros DNS
adicionar_registros_dns() {
    if [ -z "$DOMINIO" ] || [ -z "$REDE" ]; then
        dialog --msgbox "Configure antes a zona direta e reversa!" 7 50
        return
    fi

    ZONA_DIR="$DIR_ZONA/db.$DOMINIO"
    ZONA_REV="$DIR_ZONA/db.$(echo $REDE | tr '.' -)"

    while true; do
        OPCAO=$(dialog --stdout --menu "Adicionar registros DNS" 15 60 6 \
            1 "Registro A" \
            2 "CNAME (Alias)" \
            3 "MX (E-mail)" \
            4 "Finalizar" \
            0 "Voltar")

        case $OPCAO in
            1)
                HOST=$(dialog --stdout --inputbox "Nome do host (ex: www):" 8 50)
                IP=$(dialog --stdout --inputbox "IP do host:" 8 50)
                echo "$HOST    IN      A       $IP" | sudo tee -a "$ZONA_DIR" > /dev/null

                ULT_OCT=$(echo $IP | awk -F. '{print $4}')
                echo "$ULT_OCT    IN      PTR     $HOST.$DOMINIO." | sudo tee -a "$ZONA_REV" > /dev/null
                ;;
            2)
                ALIAS=$(dialog --stdout --inputbox "Alias (ex: app):" 8 50)
                ALVO=$(dialog --stdout --inputbox "Aponta para (ex: www):" 8 50)
                echo "$ALIAS    IN      CNAME    $ALVO.$DOMINIO." | sudo tee -a "$ZONA_DIR" > /dev/null
                ;;
            3)
                MXHOST=$(dialog --stdout --inputbox "Servidor MX (ex: mail):" 8 50)
                PRIORIDADE=$(dialog --stdout --inputbox "Prioridade MX (ex: 10):" 8 50)
                echo "@    IN      MX      $PRIORIDADE    $MXHOST.$DOMINIO." | sudo tee -a "$ZONA_DIR" > /dev/null
                ;;
            4)
                break
                ;;
            0)
                break
                ;;
        esac
    done

    sudo named-checkconf
    sudo named-checkzone "$DOMINIO" "$ZONA_DIR"
    sudo named-checkzone "$ZONA_REVERSE" "$ZONA_REV"
    sudo systemctl restart bind9
    dialog --msgbox "Registros aplicados e Bind9 reiniciado!" 6 50
}

# =========================
# Menu Principal
# =========================

while true; do
    OPCAO=$(dialog --stdout --menu "Menu DNS Master" 15 60 6 \
        1 "Configurar options (named.conf.options)" \
        2 "Zona direta (atual: ${DOMINIO:-nenhuma})" \
        3 "Zona reversa (atual: ${ZONA_REVERSE:-nenhuma})" \
        4 "Adicionar registros DNS" \
        0 "Sair")

    case $OPCAO in
        1) ajustar_named_conf_options ;;
        2) configurar_zona_direta ;;
        3) configurar_zona_reversa ;;
        4) adicionar_registros_dns ;;
        0) clear; exit ;;
    esac
done
