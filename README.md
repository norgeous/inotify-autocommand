# inotify-autocommand
Trigger a shell command when a file is changed. Configure with JSON. Work in progress...

## Why

Often, as a website or javascript developer using a linux VPS you need to restart services such as nginx or ghost after you have made changes to a specific file.
With Ghost for example, you edit some css in your ghost install, then you need to restart the ghost service.
You can use this minimal script to save yourself the effort of sshing in to restart services, by automatically running shell commands when changes to files happen.

It's great for use with ftp, ssh, rsync or some other file transfer syncing application (such as syncthing).

## Install

You will need ```bash 4.2``` (or higher), ```jshon``` and ```inotify-tools```, the latter two can be installed with:

```
sudo apt-get install jshon inotify-tools
```

You then just need to download the script in this repo and save it to a convinient location on the remote machine that you want to auto-execute your commands on. With ssh access this can be achieved with:

```
sudo mkdir /etc/inotify-autocommand
cd /etc/inotify-autocommand
wget https://raw.githubusercontent.com/norgeous/inotify-autocommand/master/inotify-autocommand.sh
```

## Configure

Most javascript/node developers should be familiar with creating json for configuration. For this reason, the script can be configured using a single json file, in the example below called ```config.json```.

```
{
  "jobs": [
    {
      "paths": ["/etc/nginx/nginx.conf"],
      "command": "service nginx restart"
    }
  ]
}
```

With this config, if the file ```/etc/nginx/nginx.conf``` changes, then the shell command ```service nginx restart``` is run.

Each job must contain a populated ```paths``` key and ```command``` key (as above) to be functional.

```paths``` must be an array of strings

```command``` must be a valid json encoded string

Multiple jobs can be configured in ```config.json```, and each job can listen to multiple files.

```
{
  "jobs": [
    {
      "paths": ["/etc/nginx/nginx.conf"],
      "command": "service nginx restart"
    },
    {
      "paths": ["/var/www/ghost/content/themes/casper"],
      "ignores": [".syncthing"],
      "command": "service ghost restart",
      "limit": 60
    }
  ],
  "logfile": "/var/log/inotify-autocommand.log"
}
```
The first job above restarts ```nginx``` when it's config changes.

The second job restarts ```ghost``` when one of the files in the theme directory changes.

## Defaults

```logfile``` is set to ```/dev/null``` when no key present in ```config.json```

```limit``` is set to ```10``` (seconds) when no key present in ```config.json```


## Hints and warnings

works on files or directories, just make sure there is not a trailing slash on a directory path

inotifywait is applied recursively

you can render your system unuseable with this script! for example don't configure a system restart when theres a change in the root


## Get the example config.json

```
cd /etc/inotify-autocommand
wget https://raw.githubusercontent.com/norgeous/inotify-autocommand/master/config.json
```



## Usage

Once configured, the script can be run from the command line with:
```
bash /etc/inotify-autocommand/inotify-autocommand.sh -c /etc/inotify-autocommand/config.json
```
It is best to get it configured and working using this method before adding the Upstart service

## Upstart

Create a new upstart entry with:
```
sudo nano /etc/init/inotify-autocommand.conf
```

Inside, we will use the following lines to control our Upstart service:

```
description "inotify-autocommand"

start on (local-filesystems and net-device-up IFACE!=lo)
stop on runlevel [!2345]

env STNORESTART=yes
env HOME=/root
setuid "root"
setgid "root"

exec bash /etc/inotify-autocommand/inotify-autocommand.sh -c /etc/inotify-autocommand/config.json

respawn
```

## Launch
```
service inotify-autocommand start
```

## View log file
```
tail -n +0 -f /var/log/inotify-autocommand.log

```