#!/bin/bash

# Função para detectar distro e definir o gerenciador de pacotes e nome do pacote apache
detectar_distro() {
    if [ -f /etc/arch-release ]; then
        DISTRO="arch"
        APACHE_PKG="apache"
        APACHE_SVC="httpd"
        PKG_INSTALL="pacman -Sy --noconfirm"
    elif [ -f /etc/debian_version ]; then
        DISTRO="debian"
        APACHE_PKG="apache2"
        APACHE_SVC="apache2"
        PKG_INSTALL="apt update && apt install -y"
    else
        DISTRO="unknown"
    fi
}

# Verifica se apache está instalado (serviço existe e instalado)
apache_instalado() {
    if systemctl status "$APACHE_SVC" >/dev/null 2>&1; then
        return 0  # instalado
    else
        return 1  # não instalado
    fi
}

# Instalar apache
instalar_apache() {
    if apache_instalado; then
        dialog --msgbox "✅ Apache já está instalado." 6 40
    else
        dialog --yesno "Apache não está instalado.\nDeseja instalar agora?" 7 50
        if [ $? -eq 0 ]; then
            if [ "$DISTRO" = "unknown" ]; then
                dialog --msgbox "Sua distro não é suportada para instalação automática.\nInstale manualmente." 7 50
            else
                dialog --infobox "Instalando Apache, aguarde..." 4 40
                $PKG_INSTALL $APACHE_PKG >/dev/null 2>&1
                if apache_instalado; then
                    dialog --msgbox "✅ Apache instalado com sucesso!" 6 40
                    systemctl enable "$APACHE_SVC"
                    systemctl start "$APACHE_SVC"
                else
                    dialog --msgbox "❌ Falha ao instalar Apache." 6 40
                fi
            fi
        fi
    fi
}

# Iniciar Apache
start_apache() {
    systemctl start "$APACHE_SVC" && dialog --msgbox "✅ Apache iniciado." 6 40 || dialog --msgbox "❌ Falha ao iniciar Apache." 6 40
}

# Parar Apache
stop_apache() {
    systemctl stop "$APACHE_SVC" && dialog --msgbox "✅ Apache parado." 6 40 || dialog --msgbox "❌ Falha ao parar Apache." 6 40
}

# Reiniciar Apache
restart_apache() {
    systemctl restart "$APACHE_SVC" && dialog --msgbox "✅ Apache reiniciado." 6 40 || dialog --msgbox "❌ Falha ao reiniciar Apache." 6 40
}

# Mostrar status completo Apache
status_apache() {
    STATUS=$(systemctl status "$APACHE_SVC" --no-pager)
    dialog --msgbox "$STATUS" 20 80
}

# Menu principal do Apache
menu_apache() {
    while true; do
        OPCAO=$(dialog --stdout --menu "Gerenciamento do Apache ($APACHE_SVC)" 15 60 7 \
            1 "Instalar Apache" \
            2 "Iniciar Apache" \
            3 "Parar Apache" \
            4 "Reiniciar Apache" \
            5 "Status completo Apache" \
            0 "Voltar")
        
        [ $? -ne 0 ] && break
        
        case $OPCAO in
            1) instalar_apache ;;
            2) start_apache ;;
            3) stop_apache ;;
            4) restart_apache ;;
            5) status_apache ;;
            0) break ;;
        esac
    done
}

# Início do script
detectar_distro

# Apenas para teste rápido, rodar o menu do apache diretamente
menu_apache

