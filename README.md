# NeuroFL Client Node Setup Guide

---

## What You Need

You should have received the following from the NeuroFL team:
- **API Token** — your authentication credential
- **VM/Node Name** — a unique name for your machine
- **ACR credentials** — username and password for the container registry

---

## Step 1: Install Docker

| Platform | Install |
|---|---|
| Linux (Ubuntu/Debian) | `sudo apt-get install docker.io` |
| macOS | [Download Docker Desktop](https://www.docker.com/products/docker-desktop/) |
| Windows | [Download Docker Desktop](https://www.docker.com/products/docker-desktop/) (WSL2 backend required — it's the default) |

---

## Step 2: Login to the container registry

Open a terminal:
- **Linux:** Terminal
- **Mac:** Terminal
- **Windows:** Open **WSL** (search "WSL" in Start menu, or "Ubuntu" if installed)

```bash
docker login daccacrneurofed.azurecr.io -u <username> -p <password>
```

> On Linux, prefix with `sudo` if needed: `sudo docker login ...`

---

## Step 3: Run the setup script

The setup script works on all platforms. It will ask you a few questions, set everything up, pull the image, and start the client automatically.

**Linux:**
```bash
curl -sSL https://raw.githubusercontent.com/<your-org>/neurofl/main/setup-client.sh | sudo bash
```

**Mac or Windows (WSL):**
```bash
curl -sSL https://raw.githubusercontent.com/<your-org>/neurofl/main/setup-client.sh | bash
```

The script will ask for:
1. Your **API Token**
2. Your **VM/Node Name**
3. Where to store **datasets** (press Enter for the default)
4. Where to store **logs** (press Enter for the default)

It then:
- Creates the directories
- Installs security profiles (Linux)
- Sets permissions (Linux)
- Pulls the latest image
- Starts the container
- Saves the run command so you can re-run after updates

---

## Step 4: Register your datasets

Once the container is running:

1. Open your browser: **http://localhost:8501**
2. Go to **Node Configuration** → **Dataset Management**
3. Enter a dataset name (e.g., `brain_data`) and click **Add**
4. The dashboard creates a folder for you in your data directory

---

## Step 5: Copy your data

Copy your actual data files into the folder the dashboard created:

```bash
# Example — adjust paths for your setup
cp -r /path/to/your/data/* /data/data-fl/brain_data/
```

On **Mac**, you can drag-and-drop files using Finder into `~/fl-data/brain_data/`.

On **Windows**, open File Explorer and copy files into `C:\fl-data\brain_data\` (or wherever you chose).

The watcher detects your data and registers with the server. Training starts automatically when a job is submitted by the research team. Your data never leaves your machine.

---

## Common Commands

```bash
docker logs -f fl-client           # View live logs
docker restart fl-client            # Restart the client
docker stop fl-client               # Stop the client
```

To update the client after a new version is released:

```bash
docker pull daccacrneurofed.azurecr.io/fl-client:latest
docker stop fl-client && docker rm fl-client
bash /opt/fl-client/run-client.sh        # Linux
bash ~/.neurofl/run-client.sh            # Mac / Windows (WSL)
```

> On Linux, prefix docker commands with `sudo` if needed.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| "Cannot write to data directory" | **Linux:** Re-run setup script. **Mac/Win:** Allow folder sharing in Docker Desktop → Settings → Resources |
| Container keeps restarting | Check logs: `docker logs fl-client` |
| Dashboard not loading | Verify container is running: `docker ps` |
| "API_TOKEN is required" | The API token was not set — re-run setup script |
| Docker permission denied | **Linux:** prefix with `sudo`. **Mac/Win:** make sure Docker Desktop is running |

---

## Getting Help

Contact the NeuroFL team with:
- Your VM/Node name
- Last 50 lines of logs: `docker logs fl-client --tail 50`
- Your operating system

---

**NeuroFL** — OBI Centre for Analytics
## Preprocessing pipelines

Setup asks which preprocessing pipelines this site allows. A study can require
participating sites to prepare their data before training starts; a site runs a
pipeline only if it appears in this list.

Selecting a pipeline **records permission — it does not install anything**. The
tool itself is installed by the site through its own process, and the dataset
folder needs a `preprocess.sh` that runs it. The node dashboard explains both
and can change the list at any time.

The offered names are standard on purpose. A study can only require a pipeline
that *every* target site offers, so two sites describing the same tool
differently ("mriqc" vs "MRIQC-anat") quietly makes a multi-site study
impossible to submit.

Choosing nothing is fine — the site simply does not take part in studies that
require preprocessing, and training is unaffected. The selection is written to
`<data-dir>/.neurofl/pipelines.json`; re-running setup never overwrites a list
the site has since curated.
