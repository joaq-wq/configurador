#!/bin/bash

# Verificar se é root
if [ "$EUID" -ne 0 ]; then
    echo "Execute como root ou com sudo."
    exit 1
fi

# Verificar dependência 'dialog'
if ! command -v dialog &>/dev/null; then
    echo "Instalando dependência 'dialog'..."
    apt-get update && apt-get install -y dialog
fi

# Função instalar Apache
instalar_apache() {
    if ! dpkg -l | grep -qw apache2; then
        dialog --infobox "Instalando Apache..." 5 40
        apt-get update -qq
        apt-get install -y apache2
        dialog --msgbox "✅ Apache instalado com sucesso!" 6 50
    else
        dialog --msgbox "✅ Apache já está instalado." 6 50
    fi
}

# Função pegar status do Apache formatado
status_apache() {
    STATUS=$(systemctl is-active apache2)
    case $STATUS in
        active)
            echo "🟢 Ativo"
            ;;
        inactive)
            echo "🔴 Inativo"
            ;;
        failed)
            echo "❌ Falhou"
            ;;
        *)
            echo "⚠️ Desconhecido"
            ;;
    esac
}

# Função gerenciar serviço do Apache
gerenciar_servico_apache() {
    while true; do
        STATUS_ATUAL=$(status_apache)

        OPCAO=$(dialog --stdout --menu "🔧 Gerenciar Apache (Status: $STATUS_ATUAL)" 15 60 6 \
            1 "Iniciar Apache" \
            2 "Parar Apache" \
            3 "Reiniciar Apache" \
            4 "Ver status completo" \
            0 "Voltar")

        [ $? -ne 0 ] && break

        case $OPCAO in
            1)
                systemctl start apache2
                dialog --msgbox "✅ Apache iniciado." 6 40
                ;;
            2)
                systemctl stop apache2
                dialog --msgbox "🛑 Apache parado." 6 40
                ;;
            3)
                systemctl restart apache2
                dialog --msgbox "🔄 Apache reiniciado." 6 40
                ;;
            4)
                systemctl status apache2 > /tmp/apache_status.txt
                dialog --textbox /tmp/apache_status.txt 20 70
                rm -f /tmp/apache_status.txt
                ;;
            0)
                break
                ;;
        esac
    done
}

# -------- Menu principal do Apache --------
while true; do
    STATUS_MENU=$(status_apache)

    OPCAO=$(dialog --stdout --menu "🅰️ Menu Apache (Status: $STATUS_MENU)" 15 60 4 \
        1 "Instalar Apache" \
        2 "Gerenciar Serviço" \
        0 "Voltar")

    [ $? -ne 0 ] && break

    case $OPCAO in
        1) instalar_apache ;;
        2) gerenciar_servico_apache ;;
        0) break ;;
    esac
done
