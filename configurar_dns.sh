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

# Arquivos para armazenar domínios atuais (temporários)
ARQ_DOMINIO="/tmp/dns_zona_direta.txt"
ARQ_REDE="/tmp/dns_zona_reversa.txt"

# Lê domínio atual salvo, ou vazio
DOMINIO=$( [ -f "$ARQ_DOMINIO" ] && cat "$ARQ_DOMINIO" || echo "" )
REDE=$( [ -f "$ARQ_REDE" ] && cat "$ARQ_REDE" || echo "" )
ZONA_REVERSE=""

if [[ -n "$REDE" ]]; then
    ZONA_REVERSE=$(echo $REDE | awk -F. '{print $3"."$2"."$1".in-addr.arpa"}')
fi

# Função para renomear zona existente
renomear_zona() {
    local nome_antigo="$1"
    local nome_novo

    nome_novo=$(dialog --stdout --inputbox "Digite o novo nome para a zona '$nome_antigo':" 8 50)
    [ -z "$nome_novo" ] && return 1

    # Verifica se já existe zona com o nome novo
    if grep -q "zone \"$nome_novo\"" "$CONF_LOCAL"; then
        dialog --msgbox "❌ Já existe uma zona chamada '$nome_novo'. Tente outro nome." 6 50
        return 1
    fi

    # Substitui no named.conf.local
    sudo sed -i "s/zone \"$nome_antigo\"/zone \"$nome_novo\"/g" "$CONF_LOCAL"

    # Renomeia arquivo da zona direta
    if [ -f "$DIR_ZONA/db.$nome_antigo" ]; then
        sudo mv "$DIR_ZONA/db.$nome_antigo" "$DIR_ZONA/db.$nome_novo"
    fi

    # Atualiza variável DOMINIO e arquivo temporário
    DOMINIO="$nome_novo"
    echo "$DOMINIO" > "$ARQ_DOMINIO"

    dialog --msgbox "✅ Zona renomeada de '$nome_antigo' para '$nome_novo'." 6 50
    return 0
}

# Função para ajustar named.conf.options
ajustar_named_conf_options() {
    local IP_SERVIDOR=""
    local REDE_LOCAL=""

    IP_SERVIDOR=$(dialog --stdout --inputbox "Digite o IP do servidor DNS (ex: 192.168.0.1):" 8 50 "$IP_SERVIDOR")
    [ -z "$IP_SERVIDOR" ] && return

    REDE_LOCAL=$(dialog --stdout --inputbox "Digite a rede local com máscara (ex: 192.168.0.0/24):" 8 50 "$REDE_LOCAL")
    [ -z "$REDE_LOCAL" ] && return

    sudo bash -c "cat > /etc/bind/named.conf.options" <<EOF
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

    dialog --msgbox "Arquivo /etc/bind/named.conf.options atualizado com sucesso!" 6 60
    sudo systemctl restart bind9
}

# Função para configurar zona direta
configurar_zona_direta() {
    local DOMINIO_NOVO=""
    DOMINIO_NOVO=$(dialog --stdout --inputbox "Digite o nome da Zona Direta (ex: empresa.com):" 8 50 "$DOMINIO")
    [ -z "$DOMINIO_NOVO" ] && return

    # Se o nome novo for igual ao atual, só confirma
    if [[ "$DOMINIO_NOVO" == "$DOMINIO" ]]; then
        dialog --msgbox "Zona direta permanece como '$DOMINIO'." 6 50
        return
    fi

    # Se já existir no named.conf.local, pergunta se quer renomear
    if grep -q "zone \"$DOMINIO_NOVO\"" "$CONF_LOCAL"; then
        dialog --yesno "A zona '$DOMINIO_NOVO' já existe. Deseja renomear a zona atual '$DOMINIO' para outro nome?" 7 60
        if [ $? -eq 0 ]; then
            # Tenta renomear
            if ! renomear_zona "$DOMINIO"; then
                dialog --msgbox "Não foi possível renomear a zona. Cancelando operação." 6 50
                return
            fi
        else
            dialog --msgbox "Operação cancelada." 6 50
            return
        fi
    fi

    # Atualiza zona direta
    DOMINIO="$DOMINIO_NOVO"
    echo "$DOMINIO" > "$ARQ_DOMINIO"
    ZONA_DIR="$DIR_ZONA/db.$DOMINIO"

    # Se arquivo da zona não existe, cria base
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

    # Verifica se a zona já está no named.conf.local e adiciona se não estiver
    if ! grep -q "zone \"$DOMINIO\"" "$CONF_LOCAL"; then
        echo "zone \"$DOMINIO\" {
    type master;
    file \"$ZONA_DIR\";
};" | sudo tee -a "$CONF_LOCAL" > /dev/null
    fi

    dialog --msgbox "Zona direta configurada para $DOMINIO" 6 50
}

# Função para configurar zona reversa
configurar_zona_reversa() {
    local REDE_NOVA=""
    REDE_NOVA=$(dialog --stdout --inputbox "Digite o IP da rede para a Zona Reversa (ex: 192.168.1):" 8 50 "$REDE")
    [ -z "$REDE_NOVA" ] && return

    REDE="$REDE_NOVA"
    echo "$REDE" > "$ARQ_REDE"

    ZONA_REVERSE=$(echo $REDE | awk -F. '{print $3"."$2"."$1".in-addr.arpa"}')
    ZONA_REV="$DIR_ZONA/db.$(echo $REDE | tr '.' '-')"

    # Se arquivo da zona reversa não existe, cria base
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

    # Verifica se a zona reversa está no named.conf.local e adiciona se não estiver
    if ! grep -q "zone \"$ZONA_REVERSE\"" "$CONF_LOCAL"; then
        echo "zone \"$ZONA_REVERSE\" {
    type master;
    file \"$ZONA_REV\";
};" | sudo tee -a "$CONF_LOCAL" > /dev/null
    fi

    dialog --msgbox "Zona reversa configurada para $ZONA_REVERSE" 6 60
}

# Função para adicionar registros DNS
adicionar_registros_dns() {
    if [ -z "$DOMINIO" ] || [ -z "$REDE" ]; then
        dialog --msgbox "⚠️ Configure antes a zona direta e reversa!" 7 50
        return
    fi

    ZONA_DIR="$DIR_ZONA/db.$DOMINIO"
    ZONA_REV="$DIR_ZONA/db.$(echo $REDE | tr '.' '-')"

    while true; do
        OPCAO=$(dialog --stdout --menu "Adicione registros DNS" 15 60 6 \
            1 "Adicionar Registro A" \
            2 "Adicionar CNAME (Alias)" \
            3 "Adicionar MX (E-mail)" \
            4 "Finalizar" \
            0 "Voltar")

        case $OPCAO in
            1)
                HOST=$(dialog --stdout --inputbox "Nome do host (ex: www, ftp, apache):" 8 50)
                [ -z "$HOST" ] && continue
                IP=$(dialog --stdout --inputbox "IP do host:" 8 50)
                [ -z "$IP" ] && continue

                echo "$HOST    IN      A       $IP" | sudo tee -a "$ZONA_DIR" > /dev/null

                # Atualiza zona reversa
                ULT_OCT=$(echo $IP | awk -F. '{print $4}')
                echo "$ULT_OCT    IN      PTR     $HOST.$DOMINIO." | sudo tee -a "$ZONA_REV" > /dev/null

                dialog --msgbox "Registro A adicionado." 5 40
                ;;
            2)
                ALIAS=$(dialog --stdout --inputbox "Nome do Alias (ex: app):" 8 50)
                [ -z "$ALIAS" ] && continue
                ALVO=$(dialog --stdout --inputbox "Host alvo do alias (ex: www):" 8 50)
                [ -z "$ALVO" ] && continue

                echo "$ALIAS    IN      CNAME    $ALVO.$DOMINIO." | sudo tee -a "$ZONA_DIR" > /dev/null
                dialog --msgbox "Registro CNAME adicionado." 5 40
                ;;
            3)
                MXHOST=$(dialog --stdout --inputbox "Hostname do servidor de e-mail (ex: mail):" 8 50)
                [ -z "$MXHOST" ] && continue
                PRIORIDADE=$(dialog --stdout --inputbox "Prioridade do MX (ex: 10):" 8 50)
                [ -z "$PRIORIDADE" ] && continue

                echo "@    IN      MX      $PRIORIDADE    $MXHOST.$DOMINIO." | sudo tee -a "$ZONA_DIR" > /dev/null
                dialog --msgbox "Registro MX adicionado." 5 40
                ;;
            4)
                break
                ;;
            0)
                break
                ;;
            *)
                dialog --msgbox "Opção inválida!" 5 40
                ;;
        esac
    done

    # Verifica sintaxe
    sudo named-checkconf
    sudo named-checkzone "$DOMINIO" "$ZONA_DIR"
    sudo named-checkzone "$ZONA_REVERSE" "$ZONA_REV"

    # Reinicia bind9
    sudo systemctl restart bind9
    dialog --msgbox "✅ Registros aplicados e Bind9 reiniciado!" 6 50
}

# Menu principal do DNS
while true; do
    OPCAO=$(dialog --stdout --menu "🛠️ Menu Master DNS" 15 60 6 \
        1 "Configurar options (named.conf.options)" \
        2 "Configurar zona direta (atual: ${DOMINIO:-nenhuma})" \
        3 "Configurar zona reversa (atual: ${ZONA_REVERSE:-nenhuma})" \
        4 "Adicionar registros DNS" \
        0 "Sair")

    case $OPCAO in
        1) ajustar_named_conf_options ;;
        2) configurar_zona_direta ;;
        3) configurar_zona_reversa ;;
        4) adicionar_registros_dns ;;
        0) clear; exit ;;
        *) dialog --msgbox "Opção inválida!" 5 40 ;;
    esac
done
