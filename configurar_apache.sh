#!/bin/bash

# Verificar se é root
if [ "$EUID" -ne 0 ]; then
  echo "Execute como root ou com sudo."
  exit 1
fi

# Verificar se 'dialog' está instalado
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

# Função gerenciar serviço do Apache
gerenciar_servico_apache() {
    while true; do
        STATUS=$(systemctl is-active apache2)
        OPCAO=$(dialog --stdout --menu "🔧 Gerenciar Apache (Status: $STATUS)" 15 50 6 \
            1 "Iniciar Apache" \
            2 "Parar Apache" \
            3 "Reiniciar Apache" \
            4 "Status do Apache" \
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

# Função gerenciar usuários (básico para autenticação HTTP)
gerenciar_usuarios_apache() {
    ARQUIVO_HTPASSWD="/etc/apache2/.htpasswd"

    # Garante que o arquivo exista
    [ ! -f "$ARQUIVO_HTPASSWD" ] && touch "$ARQUIVO_HTPASSWD"

    while true; do
        USUARIOS=$(cut -d: -f1 "$ARQUIVO_HTPASSWD" | paste -sd "," -)
        [ -z "$USUARIOS" ] && USUARIOS="Nenhum usuário cadastrado"

        OPCAO=$(dialog --stdout --menu "👤 Gerenciar Usuários Apache\nUsuários: $USUARIOS" 20 60 5 \
            1 "Adicionar usuário" \
            2 "Remover usuário" \
            3 "Listar usuários" \
            0 "Voltar")

        [ $? -ne 0 ] && break

        case $OPCAO in
            1)
                USUARIO=$(dialog --stdout --inputbox "Digite o nome do usuário:" 8 40)
                if [ -n "$USUARIO" ]; then
                    if ! dpkg -l | grep -qw apache2-utils; then
                        apt-get install -y apache2-utils
                    fi
                    htpasswd "$ARQUIVO_HTPASSWD" "$USUARIO"
                    dialog --msgbox "✅ Usuário $USUARIO adicionado." 6 40
                fi
                ;;
            2)
                USUARIO=$(dialog --stdout --inputbox "Digite o nome do usuário para remover:" 8 40)
                if grep -q "^$USUARIO:" "$ARQUIVO_HTPASSWD"; then
                    htpasswd -D "$ARQUIVO_HTPASSWD" "$USUARIO"
                    dialog --msgbox "❌ Usuário $USUARIO removido." 6 40
                else
                    dialog --msgbox "⚠️ Usuário não encontrado." 6 40
                fi
                ;;
            3)
                cut -d: -f1 "$ARQUIVO_HTPASSWD" > /tmp/usuarios_apache.txt
                dialog --textbox /tmp/usuarios_apache.txt 20 50
                rm -f /tmp/usuarios_apache.txt
                ;;
            0)
                break
                ;;
        esac
    done
}

# -------- Menu principal do Apache --------
while true; do
    OPCAO=$(dialog --stdout --menu "🅰️ Menu Apache" 15 60 4 \
        1 "Instalar Apache" \
        2 "Gerenciar Serviço" \
        3 "Gerenciar Usuários" \
        0 "Voltar")

    [ $? -ne 0 ] && break

    case $OPCAO in
        1) instalar_apache ;;
        2) gerenciar_servico_apache ;;
        3) gerenciar_usuarios_apache ;;
        0) break ;;
    esac
done
