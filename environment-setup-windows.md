# Environment Setup (Windows)

The Environment Setup for the Labs Bootcamp Program equips participants with essential tools and configurations for effective learning and project development. It includes operating system setup, installation of development tools and programming languages, virtual environment management, and network connectivity. This setup ensures a consistent and productive environment, enabling participants to focus on skill development and collaboration.

## Step by step

Please follow the order from top to bottom, and if there's any issue, feel free to ask the trainer.

**Contents**

- General Tools: Seatalk, Google Chrome, VPN, Git, Request GitLab Account, Garena GitLab, Visual Studio Code
- Backend Related: Go, GoMock, Unit test dependency, Postman, Visual Studio Code setup for Go
- Database Related: PostgreSQL, DBeaver
- Frontend Related: NVM and NodeJS, React Dev Tools, Visual Studio Code setup for React
- QAE Related: K6
- SRE Related: Docker (WSL2 + Docker Engine)

### Before you start

- This guide assumes **Windows 10 (64-bit, version 2004 or newer) or Windows 11**.
- Commands are written for **PowerShell**. To open it, press `Win` and type "PowerShell". Some steps need **Run as administrator** (right-click PowerShell > *Run as administrator*); these are marked.
- Many tools can be installed with `winget` (Windows Package Manager, built into Windows 10/11). Check it works with:
  ```powershell
  winget --version
  ```
  If `winget` is not found, install "App Installer" from the Microsoft Store, or use the manual download link given in each section.
- After installing something that changes `PATH`, **close and reopen your terminal** (and VS Code) before verifying.
- Check your CPU type under *Settings > System > About > System type*. Most laptops are **x64**. If yours is **ARM64**, use the `arm64` installers instead of `amd64`/`x64` and ask the trainer if anything is unclear.

---

## General Tools

### Seatalk

Please install it on your phone (Google Play Store / App Store), and sign up with your Shopee email. For desktop/laptop, you can open https://seatalkweb.com/ in your browser. Make sure you already join your batch group in Seatalk.

### Google Chrome

Download it on your laptop: https://www.google.com/chrome/. Run the downloaded installer and follow the prompts. After the installation is complete, make sure to log in with your company email.

### VPN

Some applications will be available only in our internal network, so we need a Shopee VPN to access internal resources like code repository (GitLab) and Confluence. Below are steps to request VPN access from our IT Center.

1. Visit https://it-center.sea.com.
2. Click "Sign in with Google" and select your Shopee email address.
3. After logging in, click the "Request IT Service" button on the navbar.
4. Select **"VPN (Company Device)"**.
5. Fill out the form with the information below:
   - **Create for**: your email address
   - **Location**: your office location (e.g. `ID - SKY Tower Office`)
   - **VPN Group**: `Shopee - General`
   - **Operating System**: **Windows**
   - **Purpose**: `Labs Bootcamp Program`
6. After all the fields are filled, click the **"Create"** button.
7. The request will be submitted and will wait for approval from your reporting manager. After approval and processing, you will receive an email with the installation guide. Follow the instructions in it. The approval process will take hours, so make sure you always check your email / IT Center website for updates.

### Git

Git is essential for version control, allowing participants to track changes and collaborate on code. Setup involves installing Git and configuring user identity, ensuring effective collaboration during the bootcamp.

Run the command below in PowerShell to check whether it is already installed:

```powershell
git --version
```

If Git is not installed yet, run:

```powershell
winget install --id Git.Git -e --source winget
```

(Or download the installer from https://git-scm.com/download/win and keep the default options.)

Close and reopen PowerShell, then configure your identity:

```powershell
git config --global user.name "Your Name"
git config --global user.email "your.name@shopee.com"
git config --global core.autocrlf input
```


> The `core.autocrlf input` setting avoids Windows line-ending (CRLF) problems in shell scripts and Docker files.

Installing Git for Windows also gives you **Git Bash**, which is useful if you want to run Linux-style commands.

### Request GitLab Account

Before using GitLab, you need to manually create it by requesting a ticket. You can request the ticket by following these steps:

1. Go to https://space.shopee.io/
2. Login with your Shopee Email
3. Once logged in, go to the GitLab account request link provided by the trainer
4. Fill the details with your email account and choose Role as **R&D**
5. Once done, click **Submit**

### Garena GitLab

Internally we are using a self-managed instance of GitLab. Below are steps to register to our GitLab.

1. Connect the VPN (it's required)
2. Open https://git.garena.com
3. Click the **"Sign In with Google"** button and select your Shopee email address.
4. After login, go to your batch folder (https://git.garena.com/sea-labs-id/bootcamp/batch-xx, change `xx` with your batch number) and check if you have a subgroup with your name on it. When you do, try creating a dummy repository called **test_repo**.

You need to configure an SSH connection so you can communicate with our GitLab easily.

1. Open PowerShell (Windows 10/11 already includes the OpenSSH client) and generate a key:
   ```powershell
   ssh-keygen -t ed25519 -C "your.name@shopee.com"
   ```
   Press `Enter` to accept the default location (`C:\Users\<you>\.ssh\id_ed25519`).
2. Copy your public key to the clipboard:
   ```powershell
   Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub | Set-Clipboard
   ```
3. In GitLab, go to **Profile picture > Preferences > SSH Keys**, paste the key, and click **Add key**.
4. Test the connection (VPN must be on):
   ```powershell
   ssh -T git@git.garena.com
   ```

Reference: https://docs.gitlab.com/ee/user/ssh.html#generate-an-ssh-key-pair

### Visual Studio Code

We will use Visual Studio Code as our main app for coding during the bootcamp.

> **WARNING!!!**
> **DO NOT INSTALL UNNECESSARY PLUGINS**

1. Download the **User Installer (x64)** from https://code.visualstudio.com/download and run it. (Or: `winget install -e --id Microsoft.VisualStudioCode`.)
2. On the "Select Additional Tasks" screen, make sure **"Add to PATH"** is checked, so the `code .` command works in your terminal.
3. Verify by opening a new PowerShell and running:
   ```powershell
   code --version
   ```

---

## Backend Related

### Go

Follow this installation instruction to install Go version **1.26.5**.

**Installing Golang:**

1. Go to https://go.dev/dl/, scroll to "Stable versions" and find **go1.26.5**.
2. Download the **Windows installer**: `go1.26.5.windows-amd64.msi` (ARM64 laptops: `windows-arm64.msi`).
3. Run the `.msi` and follow the wizard with the default options. The installer installs Go to `C:\Program Files\Go` and automatically sets up the `PATH`, so no manual `.bashrc` editing is needed.
4. If you already have another Go version installed, uninstall it first (*Settings > Apps > Installed apps*).

**Check the environment variables (usually automatic):**

1. Close and reopen PowerShell, then run:
   ```powershell
   go env GOROOT GOPATH
   ```
   Expected output is something like:
   ```
   C:\Program Files\Go
   C:\Users\<you>\go
   ```
2. Make sure `%GOPATH%\bin` (i.e. `C:\Users\<you>\go\bin`) is in your `PATH` so tools like `mockgen` can be found. Check with:
   ```powershell
   $env:Path -split ';' | Select-String 'go'
   ```
   If `C:\Users\<you>\go\bin` is missing, add it: press `Win`, search **"Edit environment variables for your account"**, select `Path` > *Edit* > *New*, and add `%USERPROFILE%\go\bin`. Then reopen your terminal.

**Verify the Golang installation:**

```powershell
go version
```

The output should be something like:

```
go version go1.26.5 windows/amd64
```

**Testing Golang project:**

1. In your Home directory, create the folders:
   ```powershell
   mkdir $HOME\go\src\hello
   mkdir $HOME\go\pkg, $HOME\go\bin
   ```
   (Some of these may already exist, that's fine.)
2. Open the `hello` folder in Visual Studio Code:
   ```powershell
   cd $HOME\go\src\hello
   code .
   ```
3. Open the terminal in VSCode (`` Ctrl + ` ``) and run:
   ```powershell
   go mod init hello
   ```
4. Create a file called `main.go` and paste this code:
   ```go
   package main

   import "fmt"

   func main() {
       fmt.Println("Hello, World!")
   }
   ```
5. Save the file, open the terminal in VSCode and run:
   ```powershell
   go run .
   ```
6. The output in the terminal should be `Hello, World!`

### GoMock

GoMock will be used to create mocks and help unit testing. Run the command below:

```powershell
go install go.uber.org/mock/mockgen@v0.6.0
```

Verify:

```powershell
mockgen -version
```

If you get "not recognized", `%USERPROFILE%\go\bin` is not in your `PATH` (see the Go section above).

### Unit test dependency

On Linux this is `build-essential`. On Windows, the equivalent is a C compiler (GCC), which Go needs for `cgo` and for features like `go test -race`. We'll use MSYS2:

1. Install MSYS2:
   ```powershell
   winget install -e --id MSYS2.MSYS2
   ```
   (Or download from https://www.msys2.org/.)
2. Open the **MSYS2 UCRT64** terminal from the Start menu and run:
   ```bash
   pacman -S --needed base-devel mingw-w64-ucrt-x86_64-toolchain
   ```
   Press `Enter` to install all packages when asked.
3. Add `C:\msys64\ucrt64\bin` to your Windows `PATH` (same steps as editing environment variables above).
4. Open a new PowerShell and verify:
   ```powershell
   gcc --version
   ```

### Postman

Postman will be used during Golang and RESTful API sessions. You can login or register to Postman, but make sure to use your personal email.

**Recommended:**

```powershell
winget install -e --id Postman.Postman
```

**Alternative:** download the Windows 64-bit installer from https://www.postman.com/downloads/ and run it.

Reference: https://learning.postman.com/docs/getting-started/installation/install-app

### Visual Studio Code setup for Go

This setup is necessary to help you code in Go conveniently:

1. Open Visual Studio Code by running the command below in your terminal:
   ```powershell
   code .
   ```
2. Visit https://marketplace.visualstudio.com/items?itemName=golang.Go and click **Install**.
3. After the extension has been installed, press `Ctrl + Shift + P` to open the command palette and type `Go: Install/Update Tools`.
4. Check all of the available tools to install and then click **OK**. The installation process will start automatically for all of the selected tools. Wait until you see "All tools successfully installed. You are ready to Go. :)" in the output.

---

## Database Related

### PostgreSQL

> **WARNING!!!**
> **Make sure you remember your password.**

On Windows we install PostgreSQL 16 using the official installer.

1. Download the **PostgreSQL 16** Windows x86-64 installer from https://www.postgresql.org/download/windows/ (click "Download the installer", which leads to the EDB page, and pick version **16.x**).
2. Run the installer. In the wizard:
   - **Components**: keep *PostgreSQL Server* and *Command Line Tools* checked (pgAdmin and Stack Builder are optional; you can uncheck Stack Builder).
   - **Password**: set a password for the `postgres` superuser. **Remember it.**
   - **Port**: keep the default `5432`.
   - **Locale**: keep the default.
3. Finish the installation. (If asked to launch Stack Builder at the end, uncheck it.)
4. Add the PostgreSQL `bin` folder to your `PATH` so `psql` works in any terminal: add `C:\Program Files\PostgreSQL\16\bin` (same steps as editing environment variables above), then open a new PowerShell.
5. Make sure the service is running:
   ```powershell
   Get-Service postgresql*
   ```
   Status should be `Running`.
6. Create a new role. First log in as the `postgres` superuser (enter the password from step 2):
   ```powershell
   psql -U postgres
   ```
   Then run the command below, changing `<your_username>` to your Shopee email without the "@" and without the dot "." (`john.doe@shopee.com` becomes `johndoe`) and `<your_password>` to your desired password. Make sure you remember both of these. No need to create a secure and strong password in this bootcamp because the tendency to forget is high.
   ```sql
   CREATE ROLE <your_username> SUPERUSER LOGIN CREATEDB PASSWORD '<your_password>';
   ```
   Type `\q` to exit.
7. Verify by logging in to PostgreSQL again using `psql`.

   psql command format:
   ```powershell
   psql -h <host> -p <port> -d <database name> -U <username>
   ```
   psql example:
   ```powershell
   psql -h localhost -p 5432 -d postgres -U johndoe
   ```
   You will be asked to type the password that you entered before.

### DBeaver

Install DBeaver Community:

```powershell
winget install -e --id DBeaver.DBeaver.Community
```

(Or download the Windows installer from https://dbeaver.io/download/.)

**Test connection to PostgreSQL:**

1. Open DBeaver.
2. In the top-left there's a connection icon, click it and choose **PostgreSQL**.
3. It will ask to download the driver, just download and wait.
4. After that, you will be asked for a few inputs. Fill in:
   - **Host**: `localhost`
   - **Database**: `postgres` (check "Show all databases")
   - **Username**: `<your_username>`
   - **Password**: `<your_password>`
5. Click **Test Connection**. When it is successful it will say "Connected". If it's not, make sure the PostgreSQL service is running on your machine (`Get-Service postgresql*`) and your input is correct.
6. Click **OK** to close the windows.

---

## Frontend Related

### NVM and NodeJS

On Windows we use **nvm-windows** (the Linux `nvm` script does not work on Windows). NVM allows you to quickly install and use different versions of Node via the command line.

1. If you already have Node.js installed directly, **uninstall it first** (*Settings > Apps > Installed apps*).
2. Download `nvm-setup.exe` from the latest release at https://github.com/coreybutler/nvm-windows/releases and run it with the default options. (Or: `winget install -e --id CoreyButler.NVMforWindows`.)
3. Close all terminals, open a **new PowerShell**, and verify NVM:
   ```powershell
   nvm version
   ```
4. If the NVM installation is successful, install Node.js 24. Run **PowerShell as administrator** for these commands:
   ```powershell
   nvm install 24
   nvm use 24
   ```
5. Verify Node and NPM are installed (in a normal PowerShell):
   ```powershell
   node -v
   npm -v
   ```

**Testing Node.js project:**

1. In your Home directory, create a folder called `hellonode` and open it in Visual Studio Code:
   ```powershell
   mkdir $HOME\hellonode
   cd $HOME\hellonode
   code .
   ```
2. Create a file called `hello.js` and paste this code:
   ```js
   console.log('Hello, World!');
   ```
3. Save the file and run this in the terminal; the output should be `Hello, World!`:
   ```powershell
   node hello.js
   ```

> **Troubleshooting:** if PowerShell says `npm.ps1 cannot be loaded because running scripts is disabled`, run this once:
> ```powershell
> Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
> ```

### React Dev Tools

1. Open this link in Chrome: https://chromewebstore.google.com/detail/react-developer-tools/fmkadmapgofadopljbjfkapdkoienihi
2. Click **Add to Chrome**, and then click **Add extension**.

### Visual Studio Code setup for React

This setup is necessary to help you code in React conveniently:

1. Open Visual Studio Code by running `code .` in your terminal.
2. Visit https://marketplace.visualstudio.com/items?itemName=clinyong.vscode-css-modules and install it.

---

## QAE Related

### K6

Install K6 using winget:

```powershell
winget install k6 --source winget
```

(Other options: Chocolatey `choco install k6`, or the MSI installer from https://grafana.com/docs/k6/latest/set-up/install-k6/.)

Close and reopen PowerShell, then verify the installation:

1. Run:
   ```powershell
   k6 new
   ```
2. Run:
   ```powershell
   k6 run script.js
   ```
3. If you can see a process running with the K6 logo until it's completed in around 30 seconds, then the installation is done.

---

## SRE Related

### Docker

> **WARNING!!!**
> **DO NOT INSTALL DOCKER DESKTOP**

We will use **Docker Engine**. Docker Engine runs on Linux, so on Windows we run it inside **WSL2** (Windows Subsystem for Linux) with an Ubuntu distribution.

**1. Make sure virtualization is enabled.** Open Task Manager > Performance > CPU and check that *Virtualization* says **Enabled**. If it says Disabled, enable Intel VT-x / AMD-V (SVM) in your BIOS, or ask the trainer.

**2. Install WSL2 with Ubuntu.** Open PowerShell **as administrator**:

```powershell
wsl --install -d Ubuntu
```

Restart your laptop if asked, then open **Ubuntu** from the Start menu and create a Linux username and password when prompted. Verify it is WSL version 2:

```powershell
wsl -l -v
```

**3. Enable systemd in Ubuntu** (so the Docker service starts automatically). In the Ubuntu terminal:

```bash
sudo tee /etc/wsl.conf > /dev/null <<'EOF'
[boot]
systemd=true
EOF
```

Then, in PowerShell, restart WSL:

```powershell
wsl --shutdown
```

**4. Install Docker Engine inside Ubuntu.** Open the Ubuntu terminal and follow the official guide: [How to Install Docker Engine on Ubuntu](https://docs.docker.com/engine/install/ubuntu/) (use the "Install using the apt repository" method and the Linux instructions, **not** Docker Desktop).

**5. Run docker without `sudo`.** In the Ubuntu terminal:

1. Run:
   ```bash
   sudo usermod -a -G docker $USER
   ```
2. Run:
   ```bash
   newgrp docker
   ```
3. Restart WSL: close the Ubuntu terminal, run `wsl --shutdown` in PowerShell, then open Ubuntu again. (Restarting the laptop also works.)

**6. Verify that Docker Engine is installed** (in the Ubuntu terminal):

1. Run:
   ```bash
   docker -v
   ```
2. Run:
   ```bash
   docker run hello-world
   ```

> **Note:** all `docker` commands in this bootcamp should be run from the **Ubuntu (WSL) terminal**. Ports published by containers (e.g. `-p 8080:80`) are reachable from Windows via `localhost`.

**7. Pull the images.** Run `docker pull` for each Docker image listed below:

1. `alpine:3.24.1`
2. `golang:1.26.5-alpine`
3. `postgres:16.14-alpine3.24`
4. `migrate/migrate:v4.19.1`
5. `node:24.18.0-alpine`
6. `nginx:1.30.3-alpine`
7. `otel/opentelemetry-collector-contrib:0.156.0`
8. `grafana/tempo:3.0.2`
9. `prom/prometheus:v3.13.0`
10. `ghcr.io/google/cadvisor:v0.60.4`
11. `quay.io/prometheuscommunity/postgres-exporter:v0.20.1`
12. `grafana/loki:3.7.3`
13. `axllent/mailpit:v1.30.4`
14. `grafana/grafana:13.1.0`

Or pull them all at once in the Ubuntu terminal:

```bash
for img in \
  alpine:3.24.1 \
  golang:1.26.5-alpine \
  postgres:16.14-alpine3.24 \
  migrate/migrate:v4.19.1 \
  node:24.18.0-alpine \
  nginx:1.30.3-alpine \
  otel/opentelemetry-collector-contrib:0.156.0 \
  grafana/tempo:3.0.2 \
  prom/prometheus:v3.13.0 \
  ghcr.io/google/cadvisor:v0.60.4 \
  quay.io/prometheuscommunity/postgres-exporter:v0.20.1 \
  grafana/loki:3.7.3 \
  axllent/mailpit:v1.30.4 \
  grafana/grafana:13.1.0; do
  docker pull "$img"
done
```

> If you are connected to the VPN and image pulls fail or time out, try disconnecting the VPN for the pull, or ask the trainer.
