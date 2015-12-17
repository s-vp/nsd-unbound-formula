{% from "dns/map.jinja" import dns with context %}


#################################################################################
# Healthcheck      
#################################################################################


nsd test connection: 
  module.run: 
    - name: network.connect 
    - host: {{ salt['pillar.get']('dns:nsd:config:server:ip-address') }}
    - port: {{ dns.nsd.config.server.port}}
    - proto: udp

unbound test connection:
  module.run: 
    - name: network.connect
    - host: {{ salt['network.ipaddrs']()|join }}
    - port: {{ dns.unbound.config.server.port}}
    - proto: udp

