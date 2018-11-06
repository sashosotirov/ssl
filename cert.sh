#!/bin/bash

WORK_DIR=/var/lib/jenkins/temp
DOMAIN=edu.jboxers.com
ALIAS=wildfly
STOREPASS=password
KEYPASS=password
SERVER="albacore@edu.jboxers.com"
WILDFLY_PATH="/opt/wildfly/standalone/configuration"
WEB_ROOT=/opt/wildfly/welcome-content
SRV="/srv"

# it is necessary to configure and prepare in WORK_DIR, files : intermediate.cer and standalone.xml  

#--LOCAL
cd $WORK_DIR
UNTIL=`keytool -list -v -keystore keystore.jks -v -storepass "$STOREPASS" -alias $ALIAS | grep Valid | perl -ne 'if(/until: (.*?)\n/) { print "$1\n"; }'`
UNTIL_SECONDS=`date -d "$UNTIL" +%s`
REMAINING_DAYS=$((($UNTIL_SECONDS -  $(date +%s)) / 60 / 60 / 24 ))
if [ $REMAINING_DAYS -gt 5 ]; then  exit 1; fi  

echo "-- Clean keystore --"
sudo rm $WORK_DIR/keystore.jks

echo " -- Create keystore -- "
keytool -genkey -noprompt \
 -alias $ALIAS \
 -keyalg RSA\
 -dname "CN=$DOMAIN" \
 -keystore keystore.jks \
 -storepass $STOREPASS \
 -keypass $KEYPASS\
 -keysize 2048

keytool -import -trustcacerts -alias intermediate -file $WORK_DIR/intermediate.cer -keystore keystore.jks -storepass $STOREPASS

echo "-- test keystore entry --"
keytool -list -keystore keystore.jks -v -storepass "$STOREPASS"
echo " -- Build CSR -- "
keytool -certreq -alias $ALIAS -file $WORK_DIR/request.csr -keystore keystore.jks -storepass "$STOREPASS"
scp request.csr $SERVER:$SRV


#--SERVER
echo "-- Install certbot --"
ssh $SERVER sudo chown -R albacore:albacore /srv \
&& sudo yum -y install yum-utils \
&& sudo yum-config-manager --enable rhui-REGION-rhel-server-extras rhui-REGION-rhel-server-optional\
&& sudo yum install -y certbot \
&& sudo mkdir -p $WEB_ROOT/.well-known/acme-challenge \
&& cd $SRV && rm -f *.pem
ssh $SERVER sudo certbot certonly --csr $SRV/request.csr --webroot -w $WEB_ROOT --agree-tos
scp $SERVER:$SRV/0001_chain.pem $WORK_DIR 

#--LOCAL
echo " -- Import to keystore -- "
sudo keytool -importcert -alias $ALIAS -file 0001_chain.pem -keystore keystore.jks -storepass "$STOREPASS"

#--SERVER
scp -p standalone.xml keystore.jks $SERVER:.
ssh $SERVER sudo cp keystore.jks standalone.xml $WILDFLY_PATH && sleep 5 && sudo systemctl restart wildfly

sleep 10
response=$(curl --write-out %{http_code} --silent --output /dev/null https://edu.jboxers.com)
if [ $response -eq 200 ]; then
  echo "Server ok"
else 
  echo "Server not start"
fi



