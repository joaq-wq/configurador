#!/bin/bash

# Verificar se é root
if [ "$EUID" -ne 0 ]; then
    echo "Execute este script como root ou com sudo."
    exit 1
fi

# Verificar dependência dialog
if ! command -v dialog &>/dev/null; then
    apt update && apt install -y dialog
fi

CONF_MYSQL="/etc/mysql/mariadb.conf.d/50-server.cnf"

# ========== Função para instalar MySQL ==========
instalar_sql() {
    if dpkg -l | grep -qw mariadb-server; then
        dialog --msgbox "✅ O MariaDB/MySQL já está instalado." 6 50
        return
    fi

    (
        echo "10"; sleep 0.5
        echo "# Atualizando pacotes..."; apt update -y >/dev/null 2>&1
        echo "30"; sleep 0.5
        echo "# Instalando MariaDB..."; apt install -y mariadb-server >/dev/null 2>&1
        echo "80"; sleep 0.5
        echo "# Finalizando instalação..."
        sleep 1
        echo "100"
    ) | dialog --gauge "Instalando servidor SQL (MariaDB/MySQL)..." 10 60 0

    systemctl enable mariadb
    systemctl start mariadb

    dialog --msgbox "✅ MariaDB/MySQL instalado com sucesso!" 6 50
}

# ========== Gerenciar usuários ==========
gerenciar_usuarios() {
    while true; do
        OPCAO=$(dialog --stdout --menu "👥 Gerenciar Usuários SQL" 15 60 6 \
            1 "Listar usuários" \
            2 "Criar usuário" \
            3 "Remover usuário" \
            4 "Alterar senha de usuário" \
            0 "Voltar")

        [ $? -ne 0 ] && break

        case $OPCAO in
            1)
                mysql -e "SELECT User, Host FROM mysql.user;" > /tmp/sql_users
                dialog --textbox /tmp/sql_users 20 60
                ;;
            2)
                USER=$(dialog --stdout --inputbox "Nome do usuário:" 8 40)
                [ -z "$USER" ] && continue

                PASS=$(dialog --stdout --insecure --passwordbox "Senha:" 8 40)
                [ -z "$PASS" ] && continue

                HOST=$(dialog --stdout --inputbox "Host (ex: localhost ou % para qualquer):" 8 40)
                [ -z "$HOST" ] && HOST="localhost"

                mysql -e "CREATE USER '$USER'@'$HOST' IDENTIFIED BY '$PASS';"

                dialog --msgbox "✅ Usuário $USER@$HOST criado." 6 50
                ;;
            3)
                USER=$(dialog --stdout --inputbox "Nome do usuário para remover:" 8 40)
                [ -z "$USER" ] && continue

                HOST=$(dialog --stdout --inputbox "Host do usuário:" 8 40)
                [ -z "$HOST" ] && HOST="localhost"

                mysql -e "DROP USER '$USER'@'$HOST';"
                dialog --msgbox "🗑️ Usuário $USER@$HOST removido." 6 50
                ;;
            4)
                USER=$(dialog --stdout --inputbox "Nome do usuário:" 8 40)
                [ -z "$USER" ] && continue

                HOST=$(dialog --stdout --inputbox "Host do usuário:" 8 40)
                [ -z "$HOST" ] && HOST="localhost"

                PASS=$(dialog --stdout --insecure --passwordbox "Nova senha:" 8 40)
                [ -z "$PASS" ] && continue

                mysql -e "ALTER USER '$USER'@'$HOST' IDENTIFIED BY '$PASS';"
                dialog --msgbox "🔑 Senha de $USER@$HOST alterada." 6 50
                ;;
            0) break ;;
        esac
    done
}

# ========== Gerenciar Bancos de Dados ==========
gerenciar_bancos() {
    while true; do
        OPCAO=$(dialog --stdout --menu "🗄️ Gerenciar Bancos de Dados" 15 60 6 \
            1 "Listar bancos" \
            2 "Criar banco" \
            3 "Remover banco" \
            0 "Voltar")

        [ $? -ne 0 ] && break

        case $OPCAO in
            1)
                mysql -e "SHOW DATABASES;" > /tmp/sql_databases
                dialog --textbox /tmp/sql_databases 20 60
                ;;
            2)
                DB=$(dialog --stdout --inputbox "Nome do banco de dados:" 8 40)
                [ -z "$DB" ] && continue

                mysql -e "CREATE DATABASE $DB;"
                dialog --msgbox "✅ Banco $DB criado." 6 50
                ;;
            3)
                DB=$(dialog --stdout --inputbox "Nome do banco para remover:" 8 40)
                [ -z "$DB" ] && continue

                mysql -e "DROP DATABASE $DB;"
                dialog --msgbox "🗑️ Banco $DB removido." 6 50
                ;;
            0) break ;;
        esac
    done
}

# ========== Backup e Restauração ==========
backup_restore() {
    while true; do
        OPCAO=$(dialog --stdout --menu "💾 Backup e Restauração" 15 60 6 \
            1 "Backup de um banco" \
            2 "Restaurar banco" \
            0 "Voltar")

        [ $? -ne 0 ] && break

        case $OPCAO in
            1)
                DB=$(dialog --stdout --inputbox "Nome do banco para backup:" 8 40)
                [ -z "$DB" ] && continue

                ARQ=$(dialog --stdout --inputbox "Caminho do arquivo destino (.sql):" 8 60)
                [ -z "$ARQ" ] && continue

                mysqldump "$DB" > "$ARQ"
                dialog --msgbox "✅ Backup salvo em $ARQ" 6 60
                ;;
            2)
                ARQ=$(dialog --stdout --fselect ./ 10 60)
                [ -z "$ARQ" ] && continue

                DB=$(dialog --stdout --inputbox "Nome do banco para restaurar:" 8 40)
                [ -z "$DB" ] && continue

                mysql "$DB" < "$ARQ"
                dialog --msgbox "✅ Banco $DB restaurado do arquivo $ARQ" 6 60
                ;;
            0) break ;;
        esac
    done
}

# ========== Configurações ==========
configuracoes_sql() {
    while true; do
        OPCAO=$(dialog --stdout --menu "⚙️ Configurações SQL" 20 70 10 \
            1 "Alterar senha do root" \
            2 "Permitir acesso remoto" \
            3 "Reiniciar serviço SQL" \
            4 "Editar configuração manual (/etc/mysql/mariadb.conf.d/50-server.cnf)" \
            0 "Voltar")

        [ $? -ne 0 ] && break

        case $OPCAO in
            1)
                PASS=$(dialog --stdout --insecure --passwordbox "Nova senha do root:" 8 40)
                [ -z "$PASS" ] && continue

                mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$PASS'; FLUSH PRIVILEGES;"
                dialog --msgbox "🔑 Senha do root alterada." 6 50
                ;;
            2)
                sed -i 's/^bind-address\s*=.*/bind-address = 0.0.0.0/' "$CONF_MYSQL"
                systemctl restart mariadb
                dialog --msgbox "🌐 Acesso remoto habilitado (⚠️ Lembre-se de configurar o firewall)." 7 60
                ;;
            3)
                systemctl restart mariadb
                dialog --msgbox "🔄 Serviço SQL reiniciado." 6 50
                ;;
            4)
                nano "$CONF_MYSQL"
                ;;
            0) break ;;
        esac
    done
}

# ========== Menu Principal ==========
main_menu() {
    while true; do
        OPCAO=$(dialog --stdout --menu "🚀 Gerenciador SQL (MySQL/MariaDB)" 15 60 8 \
            1 "Instalar servidor SQL" \
            2 "Gerenciar usuários" \
            3 "Gerenciar bancos de dados" \
            4 "Backup e restauração" \
            5 "Configurações gerais" \
            0 "Sair")

        [ $? -ne 0 ] && break

        case $OPCAO in
            1) instalar_sql ;;
            2) gerenciar_usuarios ;;
            3) gerenciar_bancos ;;
            4) backup_restore ;;
            5) configuracoes_sql ;;
            0) break ;;
        esac
    done
}

# Executa o menu principal
main_menu
