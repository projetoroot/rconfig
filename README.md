# rConfig - Scripts de Instalação

Scripts de instalação automatizada para o **rConfig V8 Core**, preparados pelo [Projeto Root](https://github.com/projetoroot) para facilitar a implantação da ferramenta em servidores Linux.

O objetivo deste projeto é simplificar a preparação do sistema operacional e a instalação das dependências necessárias para executar o rConfig, reduzindo a quantidade de etapas manuais durante uma instalação nova.

> **Importante:** este repositório não é o projeto oficial do rConfig. Os scripts são mantidos pelo Projeto Root como uma forma alternativa de automatizar a instalação.

---

## Sobre o rConfig

O [rConfig](https://github.com/rconfig/rconfig) é uma solução open source de **Network Configuration Management - NCM**, destinada ao gerenciamento, backup, versionamento e comparação das configurações de dispositivos de rede.

Entre os recursos disponíveis estão:

* Backup de configurações de dispositivos de rede
* Suporte a múltiplos fabricantes
* Histórico de configurações
* Versionamento
* Comparação de configurações
* Automação de tarefas
* Gerenciamento centralizado de dispositivos
* Interface web
* Agendamento de tarefas

O rConfig V8 Core é a edição gratuita e open source da plataforma.

---

## Projeto oficial

Para conhecer o projeto, acompanhar o desenvolvimento, consultar a documentação ou obter a versão oficial, utilize os canais mantidos pela equipe do rConfig.

**GitHub oficial**

https://github.com/rconfig/rconfig

**Documentação oficial**

https://docs.rconfig.com/

**Documentação específica do rConfig V8 Core**

https://v8coredocs.rconfig.com/

**Site oficial**

https://www.rconfig.com/

Recomenda-se consultar a documentação oficial antes de realizar instalações em ambientes de produção, principalmente para verificar requisitos, versões suportadas e procedimentos de atualização.

---

# Scripts deste projeto

Os scripts deste repositório foram desenvolvidos para automatizar a preparação do servidor para o rConfig.

Dependendo da distribuição, o instalador pode realizar tarefas como:

* Identificação do sistema operacional
* Instalação dos pacotes necessários
* Configuração do PHP
* Configuração do Apache
* Instalação e configuração do banco de dados
* Instalação do Composer
* Instalação do Node.js e dependências necessárias
* Configuração do Supervisor
* Preparação do ambiente do rConfig
* Configuração de permissões
* Execução das etapas necessárias para concluir a instalação

O objetivo é transformar uma instalação que normalmente envolve várias etapas manuais em um processo mais simples e reproduzível.

> **Atenção:** os scripts deste projeto são uma camada de automação mantida pelo Projeto Root. Eles não substituem a documentação oficial do rConfig.

---

# Distribuições suportadas

Os scripts seguem as distribuições atualmente documentadas pelo projeto rConfig para o V8 Core:

| Distribuição | Versão            |
| ------------ | ----------------- |
| Ubuntu       | 26.04             |
| Debian       | 13                |


---

# Instalação

## Ubuntu

Exemplo para Ubuntu 26.04:

```bash
wget https://raw.githubusercontent.com/projetoroot/rconfig/main/install-rconfig-ubuntu.sh
chmod +x install-rconfig-ubuntu.sh
sudo ./install-rconfig-ubuntu.sh
```

Caso o nome do script seja diferente na versão atual do repositório, consulte os arquivos disponíveis neste GitHub.

---

## Debian

Para Debian 13:

```bash
wget https://raw.githubusercontent.com/projetoroot/rconfig/main/install-rconfig-debian.sh
chmod +x install-rconfig-debian.sh
sudo ./install-rconfig-debian.sh
```

---


> Os nomes dos arquivos acima devem corresponder aos scripts existentes neste repositório. Caso sejam alterados, consulte a lista de arquivos da branch `main`.

---

# Instalação manual

Também é possível instalar o rConfig sem utilizar os scripts deste projeto.

O procedimento oficial envolve, de forma geral:

1. Preparar o sistema operacional
2. Instalar as dependências
3. Configurar MySQL ou MariaDB
4. Clonar o repositório oficial
5. Configurar o arquivo `.env`
6. Instalar as dependências PHP com Composer
7. Configurar o Apache
8. Configurar o Supervisor
9. Executar o instalador do rConfig
10. Configurar o acesso web

A documentação oficial do rConfig V8 Core apresenta esse procedimento detalhadamente.

---

# Dependências

O rConfig V8 possui diversos requisitos de software. Entre eles:

* PHP 8.4 ou superior
* Composer 2.4+
* Apache 2.4+
* MySQL ou MariaDB
* Node.js
* Git
* Supervisor
* Cron
* Redis

Os requisitos podem mudar entre versões. Consulte sempre a documentação oficial antes de realizar uma nova implantação.

---

# Banco de dados

O rConfig utiliza um banco de dados para armazenar suas informações.

Exemplo de criação de banco e usuário:

```sql
CREATE DATABASE rconfig;

CREATE USER 'rconfig_user'@'localhost'
IDENTIFIED BY 'SENHA_SEGURA';

GRANT ALL PRIVILEGES ON rconfig.*
TO 'rconfig_user'@'localhost';

FLUSH PRIVILEGES;
```

As credenciais utilizadas durante a instalação devem ser armazenadas de forma segura.

---

# Segurança

Recomenda-se utilizar:

* Sistema operacional atualizado
* HTTPS
* Senhas fortes
* Banco de dados com usuário específico para o rConfig
* Firewall
* Acesso administrativo restrito
* Backups periódicos
* Atualizações regulares

O próprio rConfig recomenda HTTPS para ambientes que não sejam apenas de teste.

---

# Projeto Root

Este projeto faz parte do conteúdo e dos laboratórios desenvolvidos pelo **Projeto Root**.

A proposta é disponibilizar scripts, documentação e exemplos práticos relacionados a infraestrutura, redes, segurança da informação, virtualização e administração de sistemas.

## Projeto Root

GitHub:

https://github.com/projetoroot

YouTube:

https://youtube.com/projetoroot

Wiki:

https://wiki.projetoroot.com.br

---

# Aviso

Este projeto é mantido de forma independente pelo Projeto Root.

O rConfig é um projeto separado e seus respectivos direitos, código-fonte e documentação pertencem aos seus mantenedores.

Para problemas específicos relacionados ao funcionamento do rConfig, consulte o projeto oficial:

https://github.com/rconfig/rconfig

Para problemas relacionados aos scripts deste repositório, utilize as **Issues** deste projeto.

---

## Licença

Consulte o arquivo `LICENSE` deste repositório para conhecer os termos aplicáveis aos scripts disponibilizados pelo Projeto Root.
