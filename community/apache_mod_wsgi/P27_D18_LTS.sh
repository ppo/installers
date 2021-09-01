#! /bin/bash

# this will build a very basic Django install which will require packages from
# the projects being imported to be placed in the site-packages directory manually.
CRED2='\033[1;91m'        # Red
CGREEN2='\033[1;92m'      # Green
CYELLOW2='\033[1;93m'     # Yellow
CBLUE2='\033[1;94m'       # Blue
CVIOLET2='\033[1;95m'     # Purple
CCYAN2='\033[1;96m'       # Cyan
CWHITE2='\033[1;97m'      # White
CEND='\033[0m'       # Text Reset

# i is for UUID, t is for user token, n is for app name
while getopts i:n: option
do
case "${option}"
in
i) UUID=${OPTARG};;
n) APPNAME=$OPTARG;;
esac
done

printf 'Started at %(%F %T)T\n' >> /home/$USER/logs/apps/$APPNAME/install.log

if [ -z $UUID ] || [ -z $OPAL_TOKEN ] || [ -z $APPNAME ]
then
     printf $CRED2
     echo 'This command requires the following parameters to function,
     -i App UUID, used to make API calls to control panel.
     -t Control panel TOKEN, used to authenticate to the API.
     -n Application NAME, must match the name in the control panel
     '
     exit 1
else
    # Get the port and verify the app exists, and thus the file schema exists.
    if serverjson=`curl -s --fail --header "Content-Type:application/json" --header "Authorization: Token $OPAL_TOKEN"  $API_URL/api/v1/app/read/$UUID` ;then
         printf $CGREEN2
         echo 'UUID validation and server lookup OK.'
         printf $CEND
         PORT=`echo $serverjson | jq -r .port`
    else
         printf $CRED2
         echo 'UUID validation and server lookup failed.'
         exit 1
    fi;
fi;
echo $PORT
export APPROOT=$HOME/apps/$APPNAME
mkdir -p $APPROOT/src $APPROOT/tmp $APPROOT/lib/ $APPROOT/lib/python2.7 $APPROOT/lib/python2.7/site-packages

echo "
/bin/wget https://github.com/opalstack/installers/raw/master/community/apache_mod_wsgi/httpd-2.4.41.tar.gz -O $APPROOT/src/httpd-2.4.41.tar.gz
/bin/tar zxf $APPROOT/src/httpd-2.4.41.tar.gz --directory=$APPROOT/src
cd $APPROOT/src/httpd-2.4.41 && ./configure --srcdir=$APPROOT/src/httpd-2.4.41 --prefix=$APPROOT/apache2 --enable-mods-shared=all --enable-mpms-shared=all --with-mpm=prefork
cd $APPROOT/src/httpd-2.4.41 && make --directory=$APPROOT/src/httpd-2.4.41
cd $APPROOT/src/httpd-2.4.41 && make --directory=$APPROOT/src/httpd-2.4.41 install
/bin/wget https://github.com/opalstack/installers/raw/master/community/apache_mod_wsgi/mod_wsgi-4.7.0.tar.gz -O $APPROOT/src/mod_wsgi-4.7.0.tar.gz
/bin/tar zxf $APPROOT/src/mod_wsgi-4.7.0.tar.gz --directory=$APPROOT/src
/bin/cd $APPROOT/src/mod_wsgi-4.7.0 && ./configure --srcdir=$APPROOT/src/mod_wsgi-4.7.0 --with-python=/usr/bin/python2.7 --with-apxs=$APPROOT/apache2/bin/apxs
/bin/cd $APPROOT/src/mod_wsgi-4.7.0 && make --directory=$APPROOT/src/mod_wsgi-4.7.0
/bin/cd $APPROOT/src/mod_wsgi-4.7.0 && make --directory=$APPROOT/src/mod_wsgi-4.7.0 install
export PYTHONPATH=$APPROOT/lib/python2.7/site-packages
/bin/easy_install-2.7 --prefix=$APPROOT https://github.com/opalstack/installers/raw/master/community/apache_mod_wsgi/Django-1.8.19.tar.gz
/bin/cp $APPROOT/src/httpd.conf.example $APPROOT/apache2/conf/httpd.conf
" > $APPROOT/build.sh
/bin/chmod +x $APPROOT/build.sh

echo "
export PATH=\$HOME/.local/bin:\$PATH
pip2.7 install --user -U pip==20.3.4
pip2.7 install --user  virtualenv
" > $APPROOT/pip27.sh
/bin/chmod +x $APPROOT/pip27.sh


echo "
Define OPAL_USER ${USER}
Define APP_NAME ${APPNAME}
Define APP_PORT ${PORT}
Define PROJ_NAME myproject
Define APP_ROOT /home/\${OPAL_USER}/apps/\${APP_NAME}
Define VIRT_ENV \${APP_ROOT}/env
Define PROJ_ROOT \${APP_ROOT}/\${PROJ_NAME}
Define LOG_ROOT /home/\${OPAL_USER}/logs/apps/\${APP_NAME}

ServerRoot \${APP_ROOT}/apache2

LoadModule mpm_worker_module modules/mod_mpm_worker.so
LoadModule authz_core_module modules/mod_authz_core.so
LoadModule dir_module        modules/mod_dir.so
LoadModule env_module        modules/mod_env.so
LoadModule log_config_module modules/mod_log_config.so
LoadModule mime_module       modules/mod_mime.so
LoadModule rewrite_module    modules/mod_rewrite.so
LoadModule setenvif_module   modules/mod_setenvif.so
LoadModule wsgi_module       modules/mod_wsgi.so
LoadModule unixd_module      modules/mod_unixd.so

LogFormat \"%{X-Forwarded-For}i %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\"\" combined
CustomLog \${LOG_ROOT}/access_\${APP_NAME}.log combined
ErrorLog \${LOG_ROOT}/error_\${APP_NAME}.log

DirectoryIndex index.py
DocumentRoot \${APP_ROOT}/apache2/htdocs

Listen \${APP_PORT}
KeepAlive Off
SetEnvIf X-Forwarded-SSL on HTTPS=1
ServerLimit 1
StartServers 1
MaxRequestWorkers 5
MinSpareThreads 1
MaxSpareThreads 3
ThreadsPerChild 5

# python-home = path to your virtualenv
# python-path = path to your project directory
# this is usually all of the python path config that you need.
WSGIDaemonProcess \${APP_NAME} processes=2 threads=12 python-home=\${VIRT_ENV} python-path=\${PROJ_ROOT}
WSGIProcessGroup \${APP_NAME}
WSGIRestrictEmbedded On
WSGILazyInitialization On
WSGIScriptAlias / \${PROJ_ROOT}/\${PROJ_NAME}/wsgi.py
" > $APPROOT/src/httpd.conf.example



# add installed OK
/usr/bin/curl -s -X POST --header "Content-Type:application/json" --header "Authorization: Token $OPAL_TOKEN" -d'[{"id": "'$UUID'"}]' $API_URL/api/v1/app/installed/
