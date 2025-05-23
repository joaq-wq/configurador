#!/bin/bash

# Verificar root
if [ "$EUID" -ne 0 ]; then
    echo "Execute este script como root ou com sudo."
    exit 1
fi

instalar_ssh() {
    # Atualiza lista de pacotes (sem mostrar saída)
    apt-get update -qq

    # Executa a instalação do openssh-server em background e captura o PID
    apt-get install -y openssh-server > /tmp/ssh_install.log 2>&1 &
    PID=$!

    # Função para mostrar a barra de progresso animada enquanto o apt instala
    {
        while kill -0 $PID 2>/dev/null; do
            for i in $(seq 0 100); do
                echo $i
                sleep 0.05
                # Se o processo terminou, sai do loop
                kill -0 $PID 2>/dev/null || break
            done
        done
        echo 100
    } | dialog --gauge "Instalando OpenSSH Server..." 10 60 0

    wait $PID
    RET=$?

    if [ $RET -eq 0 ]; then
        dialog --msgbox "OpenSSH Server instalado com sucesso!" 6 40
    else
        dialog --msgbox "Erro na instalação do OpenSSH Server. Veja /tmp/ssh_install.log" 8 60
    fi
}

# Garante usuário sshd
if ! id sshd &>/dev/null; then
    echo "Criando usuário sshd..."
    useradd -r -s /usr/sbin/nologin sshd
fi

# Função reiniciar ssh com checagem
reiniciar_ssh() {
    if sshd -t 2>/tmp/sshd_err.log; then
        systemctl restart ssh.service
        dialog --msgbox "SSH reiniciado com sucesso!" 6 40
    else
        dialog --msgbox "Erro na configuração SSH:\n$(cat /tmp/sshd_err.log)" 10 50
    fi
    rm -f /tmp/sshd_err.log
}

# Função para pegar valor atual ou padrão
get_ssh_conf_value() {
    grep -i "^$1" /etc/ssh/sshd_config | awk '{print $2}' | tail -n 1
}

while true; do
    # Pega valores atuais ou usa padrão
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

    OPCAO=$(dialog --stdout --menu "⚙️ Configurar SSH - Valores atuais entre parênteses" 22 80 7 \
        1 "Alterar porta SSH (atual $PORTA_ATUAL)" \
        2 "Permitir login root (atual $ROOT_ATUAL)" \
        3 "Ativar/desativar senha (PasswordAuthentication) (atual $PASS_ATUAL)" \
        4 "Ativar/desativar autenticação por chave pública (atual $PUBKEY_ATUAL)" \
        5 "Ativar/desativar log verboso (atual $LOG_ATUAL)" \
        6 "Reiniciar SSH" \
        0 "Voltar")

    RET=$?
    if [ $RET -ne 0 ]; then
        break
    fi

    case $OPCAO in
        1)
            PORTA_NOVA=$(dialog --stdout --inputbox "Porta atual: $PORTA_ATUAL\nDigite a nova porta (1-65535):" 8 50 "$PORTA_ATUAL")
            if [ $? -eq 0 ] && [[ "$PORTA_NOVA" =~ ^[0-9]+$ ]] && [ "$PORTA_NOVA" -ge 1 ] && [ "$PORTA_NOVA" -le 65535 ]; then
                sed -i '/^Port /d' /etc/ssh/sshd_config
                echo "Port $PORTA_NOVA" >> /etc/ssh/sshd_config
                dialog --msgbox "Porta SSH alterada para $PORTA_NOVA." 6 40
            else
                dialog --msgbox "Porta inválida ou operação cancelada." 6 40
            fi
            ;;
        2)
            ROOT_OPCAO=$(dialog --stdout --menu "PermitRootLogin está '$ROOT_ATUAL'. Escolha:" 10 40 2 \
                1 "yes" \
                2 "no")
            if [ $? -eq 0 ]; then
                NOVO_VALOR="no"
                [ "$ROOT_OPCAO" == "1" ] && NOVO_VALOR="yes"
                sed -i '/^PermitRootLogin /d' /etc/ssh/sshd_config
                echo "PermitRootLogin $NOVO_VALOR" >> /etc/ssh/sshd_config
                dialog --msgbox "PermitRootLogin alterado para $NOVO_VALOR." 6 40
            else
                dialog --msgbox "Operação cancelada." 6 40
            fi
            ;;
        3)
            PASS_OPCAO=$(dialog --stdout --menu "PasswordAuthentication está '$PASS_ATUAL'. Escolha:" 10 40 2 \
                1 "yes" \
                2 "no")
            if [ $? -eq 0 ]; then
                NOVO_VALOR="no"
                [ "$PASS_OPCAO" == "1" ] && NOVO_VALOR="yes"
                sed -i '/^PasswordAuthentication /d' /etc/ssh/sshd_config
                echo "PasswordAuthentication $NOVO_VALOR" >> /etc/ssh/sshd_config
                dialog --msgbox "PasswordAuthentication alterado para $NOVO_VALOR." 6 40
            else
                dialog --msgbox "Operação cancelada." 6 40
            fi
            ;;
        4)
            PUBKEY_OPCAO=$(dialog --stdout --menu "PubkeyAuthentication está '$PUBKEY_ATUAL'. Escolha:" 10 40 2 \
                1 "yes" \
                2 "no")
            if [ $? -eq 0 ]; then
                NOVO_VALOR="no"
                [ "$PUBKEY_OPCAO" == "1" ] && NOVO_VALOR="yes"
                sed -i '/^PubkeyAuthentication /d' /etc/ssh/sshd_config
                echo "PubkeyAuthentication $NOVO_VALOR" >> /etc/ssh/sshd_config
                dialog --msgbox "PubkeyAuthentication alterado para $NOVO_VALOR." 6 40
            else
                dialog --msgbox "Operação cancelada." 6 40
            fi
            ;;
        5)
            LOG_OPCAO=$(dialog --stdout --menu "LogLevel atual: $LOG_ATUAL. Escolha:" 10 40 3 \
                1 "INFO (padrão)" \
                2 "VERBOSE" \
                3 "QUIET")
            if [ $? -eq 0 ]; then
                case $LOG_OPCAO in
                    1) NOVO_LOG="INFO" ;;
                    2) NOVO_LOG="VERBOSE" ;;
                    3) NOVO_LOG="QUIET" ;;
                    *) NOVO_LOG="INFO" ;;
                esac
                sed -i '/^LogLevel /d' /etc/ssh/sshd_config
                echo "LogLevel $NOVO_LOG" >> /etc/ssh/sshd_config
                dialog --msgbox "LogLevel alterado para $NOVO_LOG." 6 40
            else
                dialog --msgbox "Operação cancelada." 6 40
            fi
            ;;
        6)
            reiniciar_ssh
            ;;
        0)
            break
            ;;
        *)
            dialog --msgbox "Opção inválida!" 6 40
            ;;
    esac
done
