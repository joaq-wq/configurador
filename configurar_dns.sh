#!/bin/bash

# Script DNS Interativo com dialog e configuração completa

if ! command -v dialog &> /dev/null; then
    echo "Instalando dialog..."
    apt update && apt install -y dialog
fi

if ! dpkg -s bind9 &> /dev/null; then
    echo "Instalando bind9..."
    apt update && apt install -y bind9 bind9utils bind9-doc
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

# Gerenciar /etc/resolv.conf - adicionar e remover entries
gerenciar_resolv_conf() {
    while true; do
        # Lê entries atuais
        NAMESERVERS=($(grep "^nameserver" /etc/resolv.conf | awk '{print $2}'))
        SEARCHES=($(grep "^search" /etc/resolv.conf | awk '{$1=""; print $0}' | xargs -n1))

        # Cria lista pra menu do dialog (index + texto)
        MENU_ITEMS=()
        local i=1
        for ns in "${NAMESERVERS[@]}"; do
            MENU_ITEMS+=($i "nameserver $ns")
            ((i++))
        done
        for s in "${SEARCHES[@]}"; do
            MENU_ITEMS+=($i "search $s")
            ((i++))
        done

        OPCAO=$(dialog --stdout --menu "Gerenciar /etc/resolv.conf" 20 70 15 \
            1 "Adicionar entry" \
            2 "Remover entry" \
            0 "Voltar")

        case $OPCAO in
            1)  # Adicionar
                TIPO=$(dialog --stdout --menu "Adicionar entry" 10 40 2 \
                    1 "nameserver" 2 "search")
                [ -z "$TIPO" ] && continue

                case $TIPO in
                    1)
                        IP_NOVO=$(dialog --stdout --inputbox "Digite o IP do nameserver:" 8 50)
                        [ -z "$IP_NOVO" ] && continue
                        # Remove duplicata
                        sudo sed -i "/^nameserver $IP_NOVO$/d" /etc/resolv.conf  
                        echo "nameserver $IP_NOVO" | sudo tee -a /etc/resolv.conf > /dev/null
                        dialog --msgbox "Nameserver $IP_NOVO adicionado." 6 40
                        ;;
                    2)
                        DOMINIO_NOVO=$(dialog --stdout --inputbox "Digite o domínio para 'search':" 8 50)
                        [ -z "$DOMINIO_NOVO" ] && continue
                        # Remove linhas search atuais e adiciona só essa
                        sudo sed -i '/^search /d' /etc/resolv.conf
                        echo "search $DOMINIO_NOVO" | sudo tee -a /etc/resolv.conf > /dev/null
                        dialog --msgbox "Search domain '$DOMINIO_NOVO' adicionado." 6 50
                        ;;
                esac
                ;;
            2)  # Remover
                if [ ${#MENU_ITEMS[@]} -eq 0 ]; then
                    dialog --msgbox "Não há entries para remover." 6 40
                    continue
                fi
                ESCOLHA=$(dialog --stdout --menu "Selecione entry para remover" 20 70 15 "${MENU_ITEMS[@]}")
                [ -z "$ESCOLHA" ] && continue

                # Ajusta índice para zero-based
                INDEX=$((ESCOLHA-1))
                ENTRY_TO_REMOVE="${MENU_ITEMS[INDEX*2+1]}"

                sudo sed -i "/^$ENTRY_TO_REMOVE$/d" /etc/resolv.conf
                dialog --msgbox "'$ENTRY_TO_REMOVE' removido de /etc/resolv.conf." 6 50
                ;;
            0)
                break
                ;;
        esac
    done
}

# Menu principal
while true; do
    DOMINIO_ATUAL=${DOMINIO:-"nenhuma"}
    REDE_ATUAL=${REDE:-"nenhuma"}

    OPCAO=$(dialog --stdout --menu "📡 Configuração DNS" 20 60 6 \
        1 "Configurar Zona Direta (atual: $DOMINIO_ATUAL)" \
        2 "Configurar Zona Reversa (atual: $REDE_ATUAL)" \
        3 "Configurar named.conf.options" \
        4 "Gerenciar /etc/resolv.conf" \
        5 "Aplicar configurações e reiniciar BIND" \
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
            gerenciar_resolv_conf
            ;;
        5)
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
