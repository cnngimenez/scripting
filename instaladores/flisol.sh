#!/bin/bash 

DEBUG=debug

source './uizenity.sh'

[[ ! -z "$DEBUG" ]] && echo 'Modo debug activo!'

#Verificaciones 
[[ $(id -u) -ne 0 ]] && uialert 'Debe ser root para ejecutar este script' && [[ -z "$DEBUG" ]] && exit 1

if ! ( which lsblk >/dev/null &&  which fdisk >/dev/null && which e2label >/dev/null )
then 	
  uialert 'Se requiere: fdisk, lsblk y e2label. Instalarlos para continuar.'
  exit 2
fi

#Establecer cuál es el dispositivo root para evitar
#problemas y excluirlo de cualquier selección. 
ROOTDEV="/dev/$(lsblk --filter 'MOUNTPOINT == "/"' -o PKNAME --noheading)"
uimsg "Dispositivo root detectado: $ROOTDEV"

function terminar {
# Código 1: salida a pedido del usuario
# Código 2: salida por situación anormal, sin cambios en sistema 
# Código 3: salida anormal, con cambios en sistema
   case $1 in 
     0) uimsg 'Saliendo, todo OK :D' ;;
     1) uimsg 'Saliendo a pedido del usuario...';;
     2) uialert 'Saliendo con errores pero sin cambios en sistema. :(';;
     3) uialert "Saliendo con errores y cambios parciales, REVISAR SISTEMA :'(" ;;
     *) uialert 'Salida de error desconocida... reporte el BUG'
   esac 
   exit $1
}

function origen {
    declare -g ORIGENLIVE ORIGENPERS ORIGENDEV

    disp=''
    while [[ -z "$disp" ]]; do
        msg='Seleccione el dispositivo ORIGEN a partir del cual realizará la copia a un nuevo dispositivo. El mismo deberá contener una partición FAT con la imagen Debian-Live y una segunda partición EXT4 donde se guardan los archivos persistentes.'
        uialert "$msg"
        
        #Eliminamos ROOTFS para evitar errores.

        lstdisps=$(lsblk -r --noheadings  -p -d -o NAME | grep -v $ROOTDEV)
        disp=$(echo "$lstdisps" salir | uiselect 'Seleccione el dispositivo de ORIGEN')

        [[ "$disp" == "salir" ]] && terminar 1

        if [[ ! -z "$disp" ]] ; then
            lsblk --noheading -r -p -o MOUNTPOINTS "$disp"
            yn=$(uiyn "El dispositivo seleccionado es: \"$disp\" ¿Es correcto?")
            if [[ "$resp" == "n" ]]; then 
                disp=''
            fi
        fi
    done

    # El script asume que la primer partición del disco tiene la imagen
    # live y la segunda partición la información de persistencia
    ORIGENLIVE=$(lsblk  -r -o MOUNTPOINT,TYPE "${disp}" |grep part |sed -e 's/part//' |head -1)
    ORIGENPERS=$(lsblk  -r -o MOUNTPOINT,TYPE "${disp}" |grep part |sed -e 's/part//' |tail -1)
    ORIGENDEV=${disp}

    if [[ -z "$ORIGENLIVE" ]] || [[ -z "$ORIGENPERS" ]] || [[ -z "$ORIGENDEV" ]];
    then 
        umsg 'No se pudo especificar el origen, saliendo...'
        terminar 2
    fi
}

function destino {
    declare -g DESTINODEV

    disp=''
    while [[ -z "$disp" ]]; do
        msg='Seleccione un dispositivo DESTINO para crear una imagen de Debian-Live con persistencia.\nADVERTENCIA: el mismo perderá TODO su contenido actual en el proceso.'
        uismsg "$msg"
        
        # Se eliminan el dispositivo de ORIGEN y el ROOTFS del listado de posibles
        # destinos para evitar catástrofes
        lstdisps=$(lsblk -r --noheadings -p -d -o NAME |egrep -v "$ROOTDEV|$ORIGENDEV")
        disp=$(echo "$lstdisps" salir | uiselect 'Seleccione un dispositivo DESTINO')
        
        [[ "$disp" == "salir" ]] && terminar 1

        if [[ ! -z "$disp" ]]; then
            tbl=$(lsblk "$disp")
            resp=$(uiyn "El dispositivo seleccionado es: \"$disp\"\n$tbl\n¿Es correcta la elección?")

            if [[ $resp == 'n' ]];then 
                disp=''
            fi
        fi
    done 

    resp=''
    while [[ -z "$resp" ]]; do
        resp=$(uiyn "Se procederá a destruir la información en \"$disp\"\n¿Está de acuerdo?")
        if [[ $resp == 'n' ]];then 
            uialert "Saliendo, sin cambios sobre \"$disp\""
            terminar 1
        fi 
    done   

    DESTINODEV="$disp"
    [[ -z "$DESTINODEV " ]] && uialert 'Destino inválido' && terminar 2
}

uialert 'Este script fue creado para FLISOL 2024 UNCOMA Neuquén.
El mismo sirve para copiar un pendrive armado LIVE con persistencia a un nuevo pendrive con iguales características.
Se requiere de: * un pendrive ORIGEN con los datos de la distribución a copiar.
                * un pendrive DESTINO de al menos 8GB de capacidad QUE SERÁ BORRADO EN SU TOTALIDAD para crear una replica del origen.'

# Determinar dispositivos de origen y de destino. 
origen 
destino  

uiprogress_start 'Creando pendrive...'

# Intentamos desmontar particiones del destino 
for mpt in $(lsblk --noheading -r -p -o MOUNTPOINTS "$DESTINODEV");do
  uimsg "Desmontando $mpt"
  if ! umount $mpt;then 
    uialert "No fue posible desmontar $mpt"
    terminar 2
  fi
done 

uiprogress_msg "Escribiendo nueva tabla de particiones en \"$DESTINODEV\""
# Eliminar cualquier tabla de partición existente
echo -e "o\nw" | fdisk "$DESTINODEV" > /dev/null 2>&1

# Crear la partición FAT de 5GB
echo -e "n\np\n1\n\n+5G\nt\nb\nw" | fdisk "$DESTINODEV" > /dev/null 2>&1

# Crear la partición EXT4 con el resto del espacio
echo -e "n\np\n2\n\n\nw" | fdisk "$DESTINODEV" > /dev/null 2>&1

partprobe "$DESTINODEV" > /dev/null 2>&1

tbl=$(lsblk "$DESTINODEV")
uiprogress_msg "Tabla de particiones creada...\n$tbl"

DESTDEVLIVE=$(lsblk  -r -o PATH,TYPE "${DESTINODEV}" |grep part |sed -e 's/part//' \
	-e 's/ //'|head -1)
DESTDEVPERS=$(lsblk  -r -o PATH,TYPE "${DESTINODEV}" |grep part |sed -e 's/part//' \
        -e 's/ //'|tail -1)


mptlive=/tmp/FATLIVE/
uiprogress_msg "Creando sistemas de archivo en \"$DESTDEVLIVE\" para LIVE"
mkfs.fat -F32 "$DESTDEVLIVE"
uiprogress_msg "Montando \"$DESTDEVLIVE\""
[[ ! -d $mptlive ]] && mkdir $mptlive
if ! mount "$DESTDEVLIVE" $mptlive ; then 
	uialert "No fue posible montar $DESTDEVLIVE en $mptlive, saliendo"
	terminar 3
fi 
cd ${ORIGENLIVE}
uiprogress_msg "Copiando de origen a $mptlive, puede tomar un tiempo"
cp -a . $mptlive/ 2>/dev/null
cd $OLDPWD


uiprogress_msg "Creando sistemas de archivo en "$DESTDEVPERS" para PERSISTENCIA,\npuede tomar varios minutos..." 
mptpers=/tmp/EXT4PERS 
mkfs.ext4  "$DESTDEVPERS"
e2label  "$DESTDEVPERS" persistence
uiprogress_msg "Montando \"$DESTDEVPERS\""
[[ ! -d $mptpers ]] && mkdir $mptpers
if ! mount "$DESTDEVPERS" $mptpers ;then 
   uialert "No fue posible montar $DESTDEVPERS en $mptpers, saliendo"
   terminar 3
fi 
uiprogress_msg "Copiando de origen a $mptpers, puede tomar un tiempo"
rsync -a ${ORIGENPERS}/ $mptpers/

uiprogress_msg "Desmontando, espere, en unos minutos terminaremos"
umount "$DESTDEVLIVE"
umount "$DESTDEVPERS" 

#Limpiando 
rmdir $mptlive
rmdir $mptpers

uiprogress_end
uialert 'Adiós, feliz FLISOL!' && terminar 0

# TODO:  
# recibir como opciones dispositivo de origen y destino para evitar
# menu de preguntas. 
# Asociar mejor las verificaciones 
# Agregar comillas dobles donde corresponda 
# Mejorar en general la estética de los mensajes, colores etc. 
# Interfaz con dialog 
# Faltaría verificar que la capacidad del pendrive 
# destino sea igual o superior a 8GB 
# Verificar que las variables DESTDEVLIVE y DESTDEVPERS estén definidas
# antes de ser usadas. 
# Se necesita un pendrive de al menos 8GB.
#
# RECETA PARA ARMAR EL PRIMER PENDRIVE 
# con PERSISTENCIA (hay herramientas como ventoy)
# En un pendrive de 8G o mas (ej /dev/sdb)
# Se crean ahí dos particiones
# 1. una de 5GB fat (seleccionar fat32), puede ser menos
# dependiendo de la distro 
# 2. una ext4

# luego de crear el filesystem ext4, se le coloca la etiqueta
# "persistente" a la particion ext4.
# Ejemplo:
# e2label /dev/sdb2 persistence

# Montamos la particion fat y colocamos ahí el live cd. Ejemplo:
# mount /dev/sdb1 /mnt
# cd /mnt
# 7z x /home/user/iso/debian-live.iso (distro favorita)

# Editamos el archivo boot/grub/grub.cfg de la particion fat, y en los
# argumentos del kernel agregamos el argumento "persistence". Ejemplo

# editar /mnt/boot/grub/grub.cfg
# agregar persistence a la linea linux:
#linux /live/vmlinuz-6.1.0-7-amd64 boot=live components persistence
#quiet splash etc

#Desmontamos.
# umount /mnt

#En la particion 2 ext4:
# mount /dev/sdb2 /mnt
# cd /mnt
# echo / union > persistence.conf
# cd /
# umount /mnt

# Listo. Reiniciar y arrancar del pendrive para probar.

# Para poner ese GNU/Linux en español una vez iniciado hay que hacer un pasito mas:

#abrir una terminal en el live
#sudo su -
#export LANG=es_ES.UTF-8

#dpkg-reconfigure locales

#(y seleccionar en el menu que construya el locale es_ES.UTF-8 y luego
#seleccionar ese como default).

#Listo, reiniciar. Una contra de esta opción es que es mas lento 
#que instalar en el disco interno. Depende del pendrive, y de que 
#tan bueno sea el puerto usb para velocidades altas.
