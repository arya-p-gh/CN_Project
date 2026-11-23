#!/bin/zsh
# Lists every .crt in Downloads and ~/cn/tls with its subject and fingerprint,
# so you can see which one is the new CA before trusting it.
#   new CA          -> ends 67:93:55:35   (subject CN=Team07 Local CA)
#   new server cert -> ends 71:5E:E1      (subject CN=app.team07.test)
#   OLD phase 1 CA  -> ends 8C:9D:E4:9B   (don't use)
setopt nullglob
for f in ~/Downloads/*.crt ~/cn/tls/*.crt; do
  subj=$(openssl x509 -in "$f" -noout -subject 2>/dev/null)
  fp=$(openssl x509 -in "$f" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2)
  tag=""
  case "$fp" in
    *67:93:55:35) tag="  <-- NEW CA (use this one)";;
    *71:5E:E1)    tag="  <-- new server cert";;
    *8C:9D:E4:9B) tag="  <-- OLD CA";;
  esac
  echo "$f"
  echo "    $subj   ...${fp[-11,-1]}$tag"
done
