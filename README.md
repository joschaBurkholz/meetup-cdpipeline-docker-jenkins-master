# Jenkins Image

## Build

```shell
docker build -t jenkins-master .
```

## Git
Nach der Provisionierung von Jenkins muss die Git-Konfiguration in ``/opt/docker/jenkins/var/lib/jenkins/.ssh/config`` um folgenden Eintrag ergänzt werden:

```shell
host github.com
 HostName github.com
 IdentityFile ~/.ssh/git
 User git
```