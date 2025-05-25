#!/bin/bash

# Verificar se é root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Execute este script como root ou com sudo."
    exit 1
fi

# Verificar se dialog está instalado
if ! command -v dialog &> /dev/null; then
    apt update && apt install -y dialog
fi

TELNET_CONF_OLD="/etc/xinetd.d/telnet"
TELNET_CONF_NEW="/etc/inetd.conf"

# ========== Função para detectar a versão ==========
verificar_versao() {
    VERSAO=$(lsb_release -rs | cut -d. -f1)
    echo "$VERSAO"
}

# ========== Instalar Telnet ==========
instalar_telnet() {
    VERSAO=$(verificar_versao)

    OPCAO=$(dialog --stdout --menu "Escolha sua versão do Ubuntu/Debian" 15 60 4 \
        1 "Versões antigas (até Ubuntu 22.04)" \
        2 "Versões novas (Ubuntu 24.04 ou superior)" \
        0 "Voltar")

    [ $? -ne 0 ] && return

    case $OPCAO in
        1)
            (
                echo "10"; sleep 0.5
                echo "# Atualizando pacotes..."; apt update >/dev/null 2>&1
                echo "30"; sleep 0.5
                echo "# Instalando telnetd e xinetd..."; apt install -y telnetd xinetd >/dev/null 2>&1
                echo "80"; sleep 0.5
                echo "# Habilitando telnet..."
                cat <<EOF > $TELNET_CONF_OLD
service telnet
{
    disable         = no
    flags           = REUSE
    socket_type     = stream
    wait            = no
    user            = root
    server          = /usr/sbin/in.telnetd
    log_on_failure  += USERID
}
EOF
                systemctl restart xinetd
                echo "100"
            ) | dialog --gauge "Instalando Telnet (modo antigo)..." 10 60 0

            dialog --msgbox "✅ Telnet instalado com sucesso nas versões antigas." 7 50
            ;;
        2)
            (
                echo "10"; sleep 0.5
                echo "# Atualizando pacotes..."; apt update >/dev/null 2>&1
                echo "40"; sleep 0.5
                echo "# Instalando telnetd e inetutils-inetd..."; apt install -y telnetd inetutils-inetd >/dev/null 2>&1
                echo "80"; sleep 0.5
                echo "# Habilitando telnet..."
                sed -i '/^telnet/d' $TELNET_CONF_NEW 2>/dev/null
                echo "telnet  stream  tcp     nowait  telnetd /usr/sbin/telnetd telnetd" >> $TELNET_CONF_NEW
                systemctl restart inetutils-inetd
                echo "100"
            ) | dialog --gauge "Instalando Telnet (modo novo)..." 10 60 0

            dialog --msgbox "✅ Telnet instalado com sucesso nas versões novas." 7 50
            ;;
        0) return ;;
    esac
}

# ========== Gerenciar Telnet ==========
gerenciar_telnet() {
    OPCAO=$(dialog --stdout --menu "🔧 Gerenciar Telnet" 15 60 6 \
        1 "Ativar Telnet" \
        2 "Desativar Telnet" \
        3 "Reiniciar Serviço Telnet" \
        4 "Ver status do Telnet" \
        0 "Voltar")

    [ $? -ne 0 ] && return

    VERSAO=$(verificar_versao)

    case $OPCAO in
        1)
            if [ "$VERSAO" -lt 24 ]; then
                sed -i 's/disable.*/disable = no/' $TELNET_CONF_OLD
                systemctl restart xinetd
                dialog --msgbox "✅ Telnet ativado (modo antigo)." 6 50
            else
                sed -i '/^telnet/d' $TELNET_CONF_NEW 2>/dev/null
                echo "telnet  stream  tcp     nowait  telnetd /usr/sbin/telnetd telnetd" >> $TELNET_CONF_NEW
                systemctl restart inetutils-inetd
                dialog --msgbox "✅ Telnet ativado (modo novo)." 6 50
            fi
            ;;
        2)
            if [ "$VERSAO" -lt 24 ]; then
                sed -i 's/disable.*/disable = yes/' $TELNET_CONF_OLD
                systemctl restart xinetd
                dialog --msgbox "🚫 Telnet desativado (modo antigo)." 6 50
            else
                sed -i '/^telnet/d' $TELNET_CONF_NEW
                systemctl restart inetutils-inetd
                dialog --msgbox "🚫 Telnet desativado (modo novo)." 6 50
            fi
            ;;
        3)
            if [ "$VERSAO" -lt 24 ]; then
                systemctl restart xinetd
            else
                systemctl restart inetutils-inetd
            fi
            dialog --msgbox "🔄 Telnet reiniciado." 6 40
            ;;
        4)
            if [ "$VERSAO" -lt 24 ]; then
                systemctl status xinetd | tee /tmp/status_telnet
            else
                systemctl status inetutils-inetd | tee /tmp/status_telnet
            fi
            dialog --textbox /tmp/status_telnet 20 70
            ;;
        0) return ;;
    esac
}

# ========== LEIA IMPORTANTE ==========
leia_importante() {
    dialog --textbox <(cat <<'EOF'
==============================
      ⚠️ LEIA IMPORTANTE ⚠️
==============================

Este script gerencia o servidor TELNET.

🚫 Telnet não é seguro, pois transmite dados e senhas em texto puro. Use apenas em redes privadas e com firewall.

==============================
💡 Diferença entre versões:

🕗 VERSÕES ANTIGAS (Ubuntu até 22.04, Debian anteriores):
- Usa o serviço `xinetd` para gerenciar conexões.
- Arquivo de configuração: /etc/xinetd.d/telnet

🆕 VERSÕES NOVAS (Ubuntu 24.04+, Debian Bookworm+):
- Usa `inetutils-inetd` ou substituto.
- Arquivo de configuração: /etc/inetd.conf
- `xinetd` foi removido dos repositórios.

==============================
🚀 Como acessar:
- No cliente, use: telnet <ip-servidor>

==============================
🔒 RECOMENDAÇÃO:
- Use SSH sempre que possível.
- Bloqueie portas Telnet na internet.

==============================
EOF
) 25 80
}

# ========== Menu Principal ==========
main_menu() {
    while true; do
        OPCAO=$(dialog --stdout --menu "🚀 Gerenciador Telnet" 15 60 6 \
            1 "Instalar Telnet" \
            2 "Gerenciar Telnet" \
            3 "📜 LEIA IMPORTANTE" \
            0 "Sair")

        [ $? -ne 0 ] && break

        case $OPCAO in
            1) instalar_telnet ;;
            2) gerenciar_telnet ;;
            3) leia_importante ;;
            0) break ;;
        esac
    done
}

main_menu
