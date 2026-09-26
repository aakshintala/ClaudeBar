# non-blank, non-comment-only lines (// , ///, /* */ blocks)
FNR==1{inb=0}
{ l=$0; sub(/^[ \t]+/,"",l); sub(/[ \t]+$/,"",l)
  if(inb){ if(index(l,"*/")){inb=0; r=substr(l,index(l,"*/")+2); if(r!="" ) c[FILENAME]++} ; raw[FILENAME]++; next }
  raw[FILENAME]++
  if(l=="") next
  if(l ~ /^\/\//) next
  if(l ~ /^\/\*/){ if(!index(substr(l,3),"*/")) inb=1; next }
  c[FILENAME]++ }
END{for(f in raw) printf "%d\t%d\t%s\n", c[f]+0, raw[f], f}
