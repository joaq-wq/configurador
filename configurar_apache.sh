#!/bin/bash

# Verificar se é root
if [ "$EUID" -ne 0 ]; then
    echo "Execute este script como root."
    exit 1
fi

APACHE_SERVICE="apache2"
HTPASSWD_FILE="/etc/apache2/.htpasswd"

# Detectar distribuição
if command -v pacman &>/dev/null; then
    APACHE_SERVICE="httpd"
    HTPASSWD_FILE="/etc/httpd/.htpasswd"
    A2ENMOD=""
    A2DISSITE=""
elif command -v apt &>/dev/null; then
    APACHE_SERVICE="apache2"
    A2ENMOD="a2enmod"
    A2DISSITE="a2dissite"
fi

# Verificar dependências
for pkg in apachectl dialog apache2-utils; do
    if ! command -v $pkg &>/dev/null; then
        echo "Instale o pacote '$pkg' antes de continuar."
        exit 1
    fi
done

# Função status do Apache
apache_status() {
    systemctl is-active $APACHE_SERVICE &>/dev/null && echo "🟢 Ativo" || echo "🔴 Inativo"
}

# Gerenciar usuários .htpasswd
gerenciar_usuarios() {
    mkdir -p "$(dirname "$HTPASSWD_FILE")"

    while true; do
        OP=$(dialog --stdout --menu "🔐 Gerenciar Usuários Apache (.htpasswd)" 15 60 5 \
            1 "Adicionar Usuário" \
            2 "Remover Usuário" \
            3 "Listar Usuários" \
            0 "Voltar")

        [ $? -ne 0 ] && break

        case $OP in
            1)
                USR=$(dialog --stdout --inputbox "Digite o nome do usuário:" 8 40)
                [ -z "$USR" ] && continue
                if [ ! -f "$HTPASSWD_FILE" ]; then
                    htpasswd -c "$HTPASSWD_FILE" "$USR"
                else
                    htpasswd "$HTPASSWD_FILE" "$USR"
                fi
                dialog --msgbox "✅ Usuário '$USR' adicionado/atualizado." 6 40
                ;;
            2)
                if [ ! -f "$HTPASSWD_FILE" ]; then
                    dialog --msgbox "❌ Arquivo .htpasswd não existe." 6 40
                    continue
                fi
                USR=$(dialog --stdout --inputbox "Digite o nome do usuário a remover:" 8 40)
                [ -z "$USR" ] && continue
                htpasswd -D "$HTPASSWD_FILE" "$USR"
                dialog --msgbox "❌ Usuário '$USR' removido." 6 40
                ;;
            3)
                if [ ! -f "$HTPASSWD_FILE" ]; then
                    dialog --msgbox "❌ Nenhum usuário encontrado." 6 40
                else
                    dialog --textbox "$HTPASSWD_FILE" 20 60
                fi
                ;;
            0) break ;;
        esac
    done
}

# Gerenciar serviço Apache
gerenciar_servico() {
    while true; do
        STATUS=$(apache_status)
        OP=$(dialog --stdout --menu "⚙️ Serviço Apache ($STATUS)" 20 60 9 \
            1 "Start 🔼" \
            2 "Stop 🔻" \
            3 "Restart ♻️" \
            4 "Reload 🔃" \
            5 "Enable (iniciar junto ao boot) ✅" \
            6 "Disable ❌" \
            7 "Ver Status Atual 🏷️" \
            8 "Verificar Configuração 🛠️" \
            0 "Voltar")

        [ $? -ne 0 ] && break

        case $OP in
            1) systemctl start $APACHE_SERVICE ;;
            2) systemctl stop $APACHE_SERVICE ;;
            3) systemctl restart $APACHE_SERVICE ;;
            4) systemctl reload $APACHE_SERVICE ;;
            5) systemctl enable $APACHE_SERVICE ;;
            6) systemctl disable $APACHE_SERVICE ;;
            7) systemctl status $APACHE_SERVICE | less ;;
            8) apachectl configtest | dialog --msgbox "$(cat)" 10 50 ;;
            0) break ;;
        esac
    done
}

# Ver Logs
ver_logs() {
    LOG_FILE="/var/log/${APACHE_SERVICE}/error.log"
    [ ! -f "$LOG_FILE" ] && LOG_FILE="/var/log/httpd/error_log"
    dialog --textbox "$LOG_FILE" 20 80
}

# Alterar Porta HTTP
alterar_porta() {
    CONF_FILE="/etc/${APACHE_SERVICE}/ports.conf"
    [ ! -f "$CONF_FILE" ] && CONF_FILE="/etc/httpd/conf/httpd.conf"

    PORTA_ATUAL=$(grep -E '^Listen ' "$CONF_FILE" | awk '{print $2}' | head -n1)

    NOVA_PORTA=$(dialog --stdout --inputbox "Porta atual: $PORTA_ATUAL\nDigite a nova porta:" 8 50 "$PORTA_ATUAL")
    if [[ "$NOVA_PORTA" =~ ^[0-9]+$ ]] && [ "$NOVA_PORTA" -ge 1 ] && [ "$NOVA_PORTA" -le 65535 ]; then
        sed -i "s/^Listen .*/Listen $NOVA_PORTA/" "$CONF_FILE"
        dialog --msgbox "✅ Porta alterada para $NOVA_PORTA\nReinicie o Apache para aplicar." 8 50
    else
        dialog --msgbox "❌ Porta inválida." 6 40
    fi
}

# Informações Gerais do Apache
info_apache() {
    INFO=$(apachectl -v; echo; apachectl -M)
    echo "$INFO" | dialog --textbox - 25 80
}

# Menu Principal
while true; do
    STATUS=$(apache_status)
    OP=$(dialog --stdout --menu "🖥️ Painel Apache ($STATUS)" 20 70 9 \
        1 "Gerenciar Usuários 🔐" \
        2 "Gerenciar Serviço ⚙️" \
        3 "Ver Logs 📜" \
        4 "Alterar Porta 🌐" \
        5 "Informações Gerais ℹ️" \
        0 "Sair ❌")

    [ $? -ne 0 ] && break

    case $OP in
        1) gerenciar_usuarios ;;
        2) gerenciar_servico ;;
        3) ver_logs ;;
        4) alterar_porta ;;
        5) info_apache ;;
        0) break ;;
    esac
done
