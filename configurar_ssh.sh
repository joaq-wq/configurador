#!/bin/bash

# Verificar se é root
if [ "$EUID" -ne 0 ]; then
    echo "Execute este script como root ou com sudo."
    exit 1
fi

# -------- Função para instalar OpenSSH com barra de progresso real --------
instalar_ssh() {
    apt-get update -qq

    mkfifo /tmp/apt_progress_pipe
    trap "rm -f /tmp/apt_progress_pipe" EXIT

    apt-get install -y openssh-server 2>/tmp/ssh_install.log &
    APT_PID=$!

    (
        SPIN='-\|/'
        i=0
        PROGRESS=0

        while kill -0 $APT_PID 2>/dev/null; do
            # Usa o número de linhas do log como estimativa de progresso
            if [ -f /tmp/ssh_install.log ]; then
                LINE_COUNT=$(wc -l < /tmp/ssh_install.log)
                PROGRESS=$((LINE_COUNT * 3))  # Ajuste de multiplicador

                if [ $PROGRESS -gt 95 ]; then
                    PROGRESS=95
                fi
            fi

            i=$(( (i + 1) % 4 ))
            echo "$PROGRESS"
            echo "Instalando OpenSSH Server... ${SPIN:$i:1}"
            sleep 0.2
        done

        # Finaliza com 100%
        echo "100"
        echo "Finalizando instalação..."
    ) | dialog --gauge "Preparando instalação..." 10 60 0

    wait $APT_PID
    RET=$?

    if [ $RET -eq 0 ]; then
        dialog --msgbox "OpenSSH Server instalado com sucesso!" 6 50
    else
        dialog --msgbox "Erro na instalação. Veja /tmp/ssh_install.log" 8 60
        exit 1
    fi
}

# -------- Função garantir usuário sshd --------
garantir_usuario_sshd() {
    if ! id sshd &>/dev/null; then
        useradd -r -s /usr/sbin/nologin sshd
    fi
}

# -------- Reiniciar SSH --------
reiniciar_ssh() {
    if sshd -t 2>/tmp/sshd_err.log; then
        systemctl restart ssh.service
        dialog --msgbox "SSH reiniciado com sucesso!" 6 40
    else
        dialog --msgbox "Erro na configuração SSH:\n$(cat /tmp/sshd_err.log)" 10 50
    fi
    rm -f /tmp/sshd_err.log
}

# -------- Pega valores do sshd_config --------
get_ssh_conf_value() {
    grep -i "^$1" /etc/ssh/sshd_config | awk '{print $2}' | tail -n 1
}

# -------- Menu principal --------
while true; do
    OPCAO=$(dialog --stdout --menu "Menu Principal" 15 60 5 \
        1 "Instalar OpenSSH Server" \
        2 "Configurar SSH" \
        0 "Sair")

    [ $? -ne 0 ] && break

    case $OPCAO in
        1)
            instalar_ssh
            garantir_usuario_sshd
            ;;
        2)
            while true; do
                PORTA_ATUAL=$(get_ssh_conf_value Port)
                [ -z "$PORTA_ATUAL" ] && PORTA_ATUAL="22"

                ROOT_ATUAL=$(get_ssh_conf_value PermitRootLogin)
                [ -z "$ROOT_ATUAL" ] && ROOT_ATUAL="no"

                PASS_ATUAL=$(get_ssh_conf_value PasswordAuthentication)
                [ -z "$PASS_ATUAL" ] && PASS_ATUAL="yes"

                PUBKEY_ATUAL=$(get_ssh_conf_value PubkeyAuthentication)
                [ -z "$PUBKEY_ATUAL" ] && PUBKEY_ATUAL="yes"

                LOG_ATUAL=$(get_ssh_conf_value LogLevel)
                [ -z "$LOG_ATUAL" ] && LOG_ATUAL="INFO"

                SUB_OPCAO=$(dialog --stdout --menu "⚙️ Configurar SSH" 22 80 8 \
                    1 "Alterar porta SSH (atual $PORTA_ATUAL)" \
                    2 "Permitir login root (atual $ROOT_ATUAL)" \
                    3 "Ativar/desativar senha (PasswordAuthentication) (atual $PASS_ATUAL)" \
                    4 "Ativar/desativar autenticação por chave pública (atual $PUBKEY_ATUAL)" \
                    5 "Ativar/desativar log verboso (atual $LOG_ATUAL)" \
                    6 "Reiniciar SSH" \
                    0 "Voltar")

                [ $? -ne 0 ] && break

                case $SUB_OPCAO in
                    1)
                        PORTA_NOVA=$(dialog --stdout --inputbox "Digite nova porta (1-65535):" 8 50 "$PORTA_ATUAL")
                        if [[ "$PORTA_NOVA" =~ ^[0-9]+$ ]] && [ "$PORTA_NOVA" -ge 1 ] && [ "$PORTA_NOVA" -le 65535 ]; then
                            sed -i '/^Port /d' /etc/ssh/sshd_config
                            echo "Port $PORTA_NOVA" >> /etc/ssh/sshd_config
                            dialog --msgbox "Porta alterada para $PORTA_NOVA" 6 40
                        else
                            dialog --msgbox "Porta inválida." 6 40
                        fi
                        ;;
                    2)
                        ROOT=$(dialog --stdout --menu "PermitRootLogin (atual $ROOT_ATUAL)" 10 40 2 \
                            yes "Permitir" no "Negar")
                        [ $? -eq 0 ] && {
                            sed -i '/^PermitRootLogin /d' /etc/ssh/sshd_config
                            echo "PermitRootLogin $ROOT" >> /etc/ssh/sshd_config
                            dialog --msgbox "PermitRootLogin alterado para $ROOT" 6 40
                        }
                        ;;
                    3)
                        PASS=$(dialog --stdout --menu "PasswordAuthentication (atual $PASS_ATUAL)" 10 40 2 \
                            yes "Ativar" no "Desativar")
                        [ $? -eq 0 ] && {
                            sed -i '/^PasswordAuthentication /d' /etc/ssh/sshd_config
                            echo "PasswordAuthentication $PASS" >> /etc/ssh/sshd_config
                            dialog --msgbox "PasswordAuthentication alterado para $PASS" 6 40
                        }
                        ;;
                    4)
                        PUBKEY=$(dialog --stdout --menu "PubkeyAuthentication (atual $PUBKEY_ATUAL)" 10 40 2 \
                            yes "Ativar" no "Desativar")
                        [ $? -eq 0 ] && {
                            sed -i '/^PubkeyAuthentication /d' /etc/ssh/sshd_config
                            echo "PubkeyAuthentication $PUBKEY" >> /etc/ssh/sshd_config
                            dialog --msgbox "PubkeyAuthentication alterado para $PUBKEY" 6 40
                        }
                        ;;
                    5)
                        LOG=$(dialog --stdout --menu "LogLevel (atual $LOG_ATUAL)" 10 40 3 \
                            INFO "Normal" VERBOSE "Detalhado" QUIET "Silencioso")
                        [ $? -eq 0 ] && {
                            sed -i '/^LogLevel /d' /etc/ssh/sshd_config
                            echo "LogLevel $LOG" >> /etc/ssh/sshd_config
                            dialog --msgbox "LogLevel alterado para $LOG" 6 40
                        }
                        ;;
                    6)
                        reiniciar_ssh
                        ;;
                    0)
                        break
                        ;;
                esac
            done
            ;;
        0)
            break
            ;;
    esac
done
