#!/bin/bash

# Verificar se é root
if [ "$EUID" -ne 0 ]; then
    echo "Execute este script como root."
    exit 1
fi

# Detectar distribuição
if command -v pacman &>/dev/null; then
    DISTRO="arch"
    APACHE_PKG="apache"
    APACHE_SERVICE="httpd"
    HTPASSWD_FILE="/etc/httpd/.htpasswd"
    LOG_FILE="/var/log/httpd/error_log"
elif command -v apt &>/dev/null; then
    DISTRO="debian"
    APACHE_PKG="apache2"
    APACHE_SERVICE="apache2"
    HTPASSWD_FILE="/etc/apache2/.htpasswd"
    LOG_FILE="/var/log/apache2/error.log"
else
    echo "Distribuição não suportada."
    exit 1
fi

# Verificar dependências
instalar_dependencias() {
    if ! command -v dialog &>/dev/null; then
        if [ "$DISTRO" = "arch" ]; then
            pacman -Sy --noconfirm dialog
        else
            apt update && apt install -y dialog
        fi
    fi

    if ! command -v htpasswd &>/dev/null; then
        if [ "$DISTRO" = "arch" ]; then
            pacman -Sy --noconfirm apache
        else
            apt install -y apache2-utils
        fi
    fi
}

# Verificar se Apache está instalado
apache_instalado() {
    if [ "$DISTRO" = "arch" ]; then
        pacman -Q $APACHE_PKG &>/dev/null
    else
        dpkg -l | grep -q $APACHE_PKG
    fi
}

# Instalar Apache
instalar_apache() {
    if apache_instalado; then
        dialog --msgbox "✅ Apache já está instalado." 6 40
    else
        dialog --infobox "Instalando Apache..." 5 40
        if [ "$DISTRO" = "arch" ]; then
            pacman -Sy --noconfirm $APACHE_PKG
        else
            apt update && apt install -y $APACHE_PKG
        fi
        dialog --msgbox "✅ Apache instalado com sucesso." 6 40
    fi
}

# Função status do Apache
apache_status() {
    systemctl is-active $APACHE_SERVICE &>/dev/null && echo "🟢 Ativo" || echo "🔴 Inativo"
}

# Gerenciar usuários
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
            5 "Enable (boot) ✅" \
            6 "Disable ❌" \
            7 "Ver Status 🏷️" \
            8 "Verificar Config 🛠️" \
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
            8) apachectl configtest | dialog --msgbox "$(apachectl configtest 2>&1)" 10 50 ;;
            0) break ;;
        esac
    done
}

# Ver Logs
ver_logs() {
    dialog --textbox "$LOG_FILE" 20 80
}

# Alterar Porta HTTP
alterar_porta() {
    if [ "$DISTRO" = "arch" ]; then
        CONF_FILE="/etc/httpd/conf/httpd.conf"
    else
        CONF_FILE="/etc/apache2/ports.conf"
    fi

    PORTA_ATUAL=$(grep -E '^Listen ' "$CONF_FILE" | awk '{print $2}' | head -n1)

    NOVA_PORTA=$(dialog --stdout --inputbox "Porta atual: $PORTA_ATUAL\nDigite nova porta:" 8 50 "$PORTA_ATUAL")
    if [[ "$NOVA_PORTA" =~ ^[0-9]+$ ]] && [ "$NOVA_PORTA" -ge 1 ] && [ "$NOVA_PORTA" -le 65535 ]; then
        sed -i "s/^Listen .*/Listen $NOVA_PORTA/" "$CONF_FILE"
        dialog --msgbox "✅ Porta alterada para $NOVA_PORTA\nReinicie o Apache para aplicar." 8 50
    else
        dialog --msgbox "❌ Porta inválida." 6 40
    fi
}

# Informações Gerais
info_apache() {
    INFO=$(apachectl -v; echo; apachectl -M)
    echo "$INFO" | dialog --textbox - 25 80
}

# Menu Gerenciar Apache
menu_gerenciar_apache() {
    while true; do
        STATUS=$(apache_status)
        OP=$(dialog --stdout --menu "🖥️ Painel Apache ($STATUS)" 20 70 9 \
            1 "Gerenciar Usuários 🔐" \
            2 "Gerenciar Serviço ⚙️" \
            3 "Ver Logs 📜" \
            4 "Alterar Porta 🌐" \
            5 "Informações Gerais ℹ️" \
            0 "Voltar ❌")

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
}

# Menu Principal
instalar_dependencias

while true; do
    OP=$(dialog --stdout --menu "🚀 Gerenciador Apache" 15 60 3 \
        1 "Instalar Apache" \
        2 "Gerenciar Apache" \
        0 "Sair")

    [ $? -ne 0 ] && break

    case $OP in
        1) instalar_apache ;;
        2)
            if apache_instalado; then
                menu_gerenciar_apache
            else
                dialog --msgbox "❌ Apache não está instalado. Instale primeiro." 6 50
            fi
            ;;
        0) break ;;
    esac
done
