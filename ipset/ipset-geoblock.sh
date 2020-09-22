#!/bin/bash

# NOTE Comma at end of each string . . .
COUNTRIES_A="al,ad,af,ai,ag,al,am,ao,ar,ax,az,"
COUNTRIES_B="ba,bd,bf,bg,bh,bi,bj,bn,br,bt,bw,by,"
COUNTRIES_C="cd,ci,cl,cf,cg,cm,cn,co,cr,cu,cz,"
COUNTRIES_D="dj,dz,"
COUNTRIES_E="ec,ee,eg,es,"
COUNTRIES_G="ga,gm,ge,gh,"
COUNTRIES_H="hk,hu,hr,"
COUNTRIES_I="id,in,ir,il,it,jp,lt,"
COUNTRIES_K="kh,km,kp,kr,"
COUNTRIES_M="ma,md,mg,ml,mn,mx,my,mz,ni,ne,ng,"
COUNTRIES_P="pk,pt,pl,"
COUNTRIES_R="ro,rs,ru,"
COUNTRIES_S="sa,sk,si,sn,sg,sv,"
COUNTRIES_T="td,tn,th,tg,tr,tw,"
COUNTRIES_V="ua,uy,uz,vn,ve,"
# NOTE NO comma on last entry. This format must be preserved.
COUNTRIES_Y="ye,za,zm,zw"

# COUNTRIES_Y="af,ax,al,dz,as,ao,ai,aq,ag,ar,am,aw,au,at,az,bs,bh,bd,bb,by,bz,bj,bm,bt,bo,ba,bw,br,io,bn,bg,bf,bi,kh,cm,ca,cv,ky,cf,td,cl,cn,co,km,cg,cd,ck,cr,ci,hr,cu,cy,cz,dk,dj,dm,do,ec,eg,sv,gq,er,ee,et,fo,fj,fi,ga,gm,ge,de,gh,gi,gr,gl,gd,gu,gt,gn,ht,hn,hk,hu,is,in,id,ir,iq,ie,im,il,it,jm,jp,je,jo,kz,ke,ki,kp,kr,kw,kg,la,lv,lb,ls,lr,ly,li,lt,lu,mo,mk,mg,mw,my,mv,ml,mt,mh,mq,mr,mu,yt,mx,fm,md,mn,me,ms,ma,mz,mm,na,nr,np,nc,nz,ni,ne,ng,nu,nf,mp,no,om,pk,pw,ps,pa,pg,py,pe,ph,pl,pt,pr,qa,ro,ru,rw,kn,vc,ws,sm,st,sa,sn,rs,sc,sl,sg,sk,si,sb,so,za,es,lk,sd,sr,sz,se,sy,tw,tj,tz,th,tg,tk,to,tt,tn,tr,tm,tc,tv,ug,ua,ae,gb,us,um,uy,uz,vu,ve,vn,vg,vi,wf,ye,zm,zw"

COUNTRIES=$(echo $COUNTRIES_{A..Z}| tr -d '[:space:]')

ipset -L geoblock >/dev/null 2>&1
if [ $? -ne 0 ]; then
# Create the ipset list
echo "Set geoblock does not exist, creating ..."
	ipset -N geoblock hash:net
else
echo "Set geoblock already exists. Flushing old set ..."
	ipset flush geoblock
fi

echo "Adding IPs to geoblock set ..."
for IP in $(curl -s http://www.ipdeny.com/ipblocks/data/aggregated/{${COUNTRIES}}-aggregated.zone)
do
# ban everything - block countryX
ipset -A geoblock $IP
done
ipset save geoblock -f /root/blacklist/ipset-geoblock.list
# validate ipset with : iptables -I INPUT -m set --match-set geoblock src -j DROP
