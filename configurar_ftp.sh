#!/bin/bash

# Verificar se é root
if [ "$EUID" -ne 0 ]; then
    echo "Execute este script como root ou com sudo."
    exit 1
fi

# Verificar dependência dialog
if ! command -v dialog &>/dev/null; then
    apt-get update && apt-get install -y dialog
fi

LOG="/tmp/ftp_install.log"

# Função para instalar o vsftpd com barra de progresso
instalar_ftp() {
    rm -f "$LOG"

    (
        apt-get update -qq
        apt-get install -y vsftpd >"$LOG" 2>&1
    ) &
    PID=$!

    (
        SPIN='-\|/'
        i=0
        PROGRESS=5

        while kill -0 $PID 2>/dev/null; do
            if [ -f "$LOG" ]; then
                LINES=$(wc -l < "$LOG")
                TARGET=$((LINES * 3))
                [ "$TARGET" -gt 90 ] && TARGET=90
            else
                TARGET=10
            fi

            if [ "$PROGRESS" -lt "$TARGET" ]; then
                PROGRESS=$((PROGRESS + 1))
            fi

            i=$(( (i + 1) % 4 ))
            echo "$PROGRESS"
            echo "Instalando vsftpd... ${SPIN:$i:1}"
            sleep 0.2
        done

        while [ "$PROGRESS" -lt 100 ]; do
            PROGRESS=$((PROGRESS + 2))
            echo "$PROGRESS"
            echo "Finalizando instalação..."
            sleep 0.1
        done
    ) | dialog --gauge "Instalando vsftpd..." 10 70 0

    wait $PID
    RET=$?

    if [ $RET -eq 0 ]; then
        dialog --msgbox "✅ vsftpd instalado com sucesso!" 6 50
    else
        dialog --msgbox "❌ Erro na instalação. Verifique $LOG" 8 60
        exit 1
    fi
}

# Função para editar configuração do vsftpd
editar_configuracao() {
    nano /etc/vsftpd.conf
}

# Função para aplicar algumas configurações básicas via menu
configurar_ftp() {
    while true; do
        SUB_OPCAO=$(dialog --stdout --menu "⚙️ Configurar FTP" 20 70 10 \
            1 "Permitir conexões anônimas (padrão: NO)" \
            2 "Ativar login de usuários locais" \
            3 "Permitir upload" \
            4 "Ativar chroot (travar usuário na pasta)" \
            5 "Editar manualmente (nano)" \
            6 "Reiniciar FTP" \
            0 "Voltar")

        [ $? -ne 0 ] && break

        case $SUB_OPCAO in
            1)
                sed -i '/^anonymous_enable=/d' /etc/vsftpd.conf
                dialog --yesno "Permitir conexões anônimas?" 7 50
                if [ $? -eq 0 ]; then
                    echo "anonymous_enable=YES" >> /etc/vsftpd.conf
                else
                    echo "anonymous_enable=NO" >> /etc/vsftpd.conf
                fi
                ;;
            2)
                sed -i '/^local_enable=/d' /etc/vsftpd.conf
                echo "local_enable=YES" >> /etc/vsftpd.conf
                dialog --msgbox "✅ Login de usuários locais ativado." 6 40
                ;;
            3)
                sed -i '/^write_enable=/d' /etc/vsftpd.conf
                dialog --yesno "Permitir upload e escrita?" 7 50
                if [ $? -eq 0 ]; then
                    echo "write_enable=YES" >> /etc/vsftpd.conf
                    dialog --msgbox "✅ Upload ativado." 6 40
                else
                    echo "write_enable=NO" >> /etc/vsftpd.conf
                    dialog --msgbox "🚫 Upload desativado." 6 40
                fi
                ;;
            4)
                sed -i '/^chroot_local_user=/d' /etc/vsftpd.conf
                echo "chroot_local_user=YES" >> /etc/vsftpd.conf
                dialog --msgbox "🔐 Usuários agora estão presos em suas pastas home." 6 50
                ;;
            5)
                editar_configuracao
                ;;
            6)
                systemctl restart vsftpd
                dialog --msgbox "🔄 FTP reiniciado com sucesso." 6 40
                ;;
            0)
                break
                ;;
        esac
    done
}

# Menu principal FTP
while true; do
    OPCAO=$(dialog --stdout --menu "Menu FTP" 15 60 5 \
        1 "Instalar vsftpd" \
        2 "Configurar FTP" \
        0 "Voltar")

    [ $? -ne 0 ] && break

    case $OPCAO in
        1)
            instalar_ftp
            ;;
        2)
            configurar_ftp
            ;;
        0)
            break
            ;;
    esac
done
