#!/bin/bash
set -e

APP_DIR="/opt/gps-logger"

echo "Patch server to support driver_id..."

# добавить поле driver_id в meta
sed -i 's/meta = {/meta = {\n        "driver_id": data.get("driver_id","unknown"),/' $APP_DIR/app/session_manager.py || true

echo "Patch API endpoint..."

sed -i 's/data = request.json/data = request.json\n    driver_id = data.get("driver_id","unknown")/' $APP_DIR/app/server.py || true

echo "Patch web UI..."

cat << 'HTMLPATCH' >> $APP_DIR/web/index.html

<script>
function getDriverId(){
    let id = localStorage.getItem("driver_id");
    if(!id){
        id = prompt("Введите имя курьера");
        if(id){
            localStorage.setItem("driver_id",id);
        }
    }
    return id;
}
</script>

HTMLPATCH

echo "Patch start session JS..."

sed -i 's/fetch("\/start_session"/fetch("\/start_session",{method:"POST",headers:{"Content-Type":"application\/json"},body:JSON.stringify({driver_id:getDriverId()})})/' $APP_DIR/web/index.html || true

echo "Restart gps logger..."

systemctl restart gps-logger

echo "DONE"
