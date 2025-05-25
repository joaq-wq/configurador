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

leia_importante() {
    cat <<'EOF' > /tmp/leia_telnet.txt
==============================
      ⚠️ LEIA IMPORTANTE ⚠️
==============================

Este script gerencia o servidor Telnet.

🕗 Atenção:
- Em versões antigas do Ubuntu (< 22.04), usa-se xinetd + telnetd.
- Em versões mais novas (> 22.04), o xinetd foi removido dos repositórios oficiais.

✅ O script detecta sua versão e permite instalar o método correto:
- Método antigo: telnetd + xinetd
- Método atual: telnetd + alternativas compatíveis

==============================
🚫 Segurança:
- Telnet NÃO é seguro. Toda comunicação é texto puro.
- Recomendado usar somente em redes internas ou para testes.
- Para acesso remoto seguro, use SSH.

==============================
📜 Arquivos importantes:
- /etc/inetd.conf ou /etc/xinetd.d/telnet (versões antigas)
- /etc/default/telnetd ou configuração direta via serviço (novas)

==============================
PASSO A PASSO PARA CONFIGURAR
O que é Telnet?
- Permite acessar outros dispositivos via terminal.
- NÃO é seguro para uso externo, apenas para redes internas ou testes.

Instalar Telnet (Cliente) no Linux:
sudo apt update
sudo apt install -y telnet

Instalar Telnet (Servidor) no Linux:
sudo apt update
sudo apt install -y xinetd telnetd

Configurar Servidor Telnet:
1. Crie o arquivo /etc/xinetd.d/telnet
sudo nano /etc/xinetd.d/telnet

2. Adicione:
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

3. Reinicie o serviço:
sudo systemctl restart xinetd
sudo systemctl enable xinetd

4. Libere no firewall (se ativo):
sudo ufw allow 23

Testar Conexão Telnet:
De outro PC:
telnet <IP>

Exemplo:
telnet 192.168.0.100

Login com usuário e senha do sistema.

Habilitar login root (opcional e inseguro):
1. Edite:
sudo nano /etc/securetty

2. Adicione:
pts/0
pts/1
pts/2

3. Defina senha root:
sudo passwd root

Desativar Telnet:
sudo systemctl stop xinetd
sudo systemctl disable xinetd
sudo ufw deny 23

Observação:
Use Telnet APENAS para testes locais.
Prefira SSH para acesso seguro (porta 22).



==============================
EOF

    dialog --textbox /tmp/leia_telnet.txt 25 80
    rm -f /tmp/leia_telnet.txt
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
