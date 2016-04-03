#!/bin/bash

# Mount network shares
SMB_USER=username
SMB_SHARE1=//orca-5.openmicroscopy.org/idr
sudo mkdir -p /uod/idr
sudo mount -t cifs -o username="$SMB_USER" "$SMB_SHARE1" /uod/idr

if [ ! -d /uod/idr/filesets ]; then
    echo "ERROR: IDR filesets not found, exiting"
    exit 2
fi

# Optionally disable autostart of OMERO.server
# because /uod/idr needs to be manually mounted
sudo systemctl disable omero

# Install extra utilities
# TODO: Use ansible
sudo yum install -y screen

# If there are web css problems you may need to restore the SELinux labelling
sudo restorecon -R -v ~omero/

sudo chmod a+x /home/*

OMERO_SERVER=/home/omero/OMERO.server

# Download the render.py plugin if it's not present in this build
if [ ! -f "$OMERO_SERVER/lib/python/omero/plugins/render.py" ]; then
    sudo -u omero sh -c "curl https://raw.githubusercontent.com/manics/openmicroscopy/metadata52-render/components/tools/OmeroPy/src/omero/plugins/render.py > '$OMERO_SERVER/lib/python/omero/plugins/render.py'"
fi

omero="$OMERO_SERVER/bin/omero"

# Setup server settings
sudo -u omero $omero << EOF
config set omero.db.poolsize 25
config set omero.jvmcfg.heap_size.blitz 16G
config set omero.sessions.timeout 3600000
EOF

# WARNING: don't use admin restart as this will break systemd control
sudo systemctl restart omero
sleep 1m

# Create users and groups
PUBLIC_PASS="$(openssl rand -base64 12)"

$omero login -s localhost -u root -w omero
$omero group add --type read-only demo
$omero user add --group-name demo -P ome demo idr demo
$omero user add --group-name demo -P "$PUBLIC_PASS" public Public User
$omero logout

# Setup public user
sudo -u omero $omero << EOF
config set omero.web.public.url_filter '^/(webadmin/myphoto/|webclient/(?!(action|annotate_(file|tags|comment|rating|map)|script_ui|ome_tiff|figure_script))|webgateway/(?!(archived_files|download_as)))'
config set omero.web.public.enabled True
config set omero.web.public.user public
config set omero.web.public.password "$PUBLIC_PASS"
config set omero.web.public.server_id 1
config set omero.web.login_redirect '{"redirect": ["webindex"], "viewname": "load_template", "args":["userdata"], "query_string": "experimenter=2"}'
EOF
# WARNING: don't use admin restart as this will break systemd control
sudo systemctl restart omero-web