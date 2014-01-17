function get_k_id 
{
   RETVAL=$( keystone ${1}-list | grep "${2}" | awk '{print $2}' )
   echo $RETVAL
}

function get_q_id 
{
   RETVAL=$( neutron ${1}-list | grep "${2}" | awk '{print $2}' )
   echo $RETVAL
}

function get_image
{
  NAME=$1 
  ID=$( glance index | grep ${NAME} | awk '{print $1}' ) 

  echo ${ID}
}