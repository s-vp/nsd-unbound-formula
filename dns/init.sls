{% from "dns/map.jinja" import dns with context %}
{% set anchor_file = salt['pillar.get']('dns:unbound:config:server:auto-trust-anchor-file') %}
{% set root_hints_file = salt['pillar.get']('dns:unbound:config:server:root-hints') %}
{% set myip = salt['network.ipaddrs']()|join  %}
{% set nsd = dns.nsd %}
{% set unbound = dns.unbound %}


#################################################################################
# Install packages   
#################################################################################


{% if dns.install_packages is defined %}
{% for name in dns.install_packages %}

{{ name }} install packages: 
  pkg.installed:
    - name: {{ name }}
    - unless: 
      - which {{ name }}

{% endfor %}
{% endif %}


#################################################################################
# COMMON Config part creating/checking users, dirs, files, permissions    
#################################################################################

{% for this in  nsd , unbound %}

{{ this.user }}:
  user.present:
    - shell: /sbin/nologin
  group.present: 
    - name: {{ this.user }}

{{ this.name }} create default dirs:
  file.directory: 
    - user: {{ this.user }}
    - makedirs: True
    - name: {{ this.prefix }}/var/log

{% if dns.clean_config == True %}
{% if this.name == 'nsd' %}

{{ dns.nsd.config.server.zonesdir }}:
  file.directory:
    - user: {{ this.user }}
    - clean: True

{% endif %}

echo > {{ this.include }}:
  cmd.run

{% endif %}

#################################################################################
# COMMON PART for serialized config files   
#################################################################################


{{ this.conf_file }}:
  file.serialize:
    - user: root
    - group: {{ this.user }}
    - mode: 640
    - makedirs: True
    - backup: minion
    - dataset_pillar: dns:{{ this.name }}:config


#################################################################################
# workaround to replace 'yes' and 'no with yes and no in serialized config files   
#################################################################################

{% for word in 'yes', 'no' %}

{{ this.conf_file }} replace {{ word }}:   
  file.replace:
    - name: {{ this.conf_file }}
    - show_changes: False
    - pattern: |
        '{{ word }}'
    - repl: |
        {{ word }}
{% endfor %}

#################################################################################
# UNBOUND Config part 
#################################################################################

{% if this.name == "unbound" %}

{{ this.conf_file }} replace :   
  file.replace:
    - name: {{ this.conf_file }}
    - show_changes: True
    - append_if_not_found: True 
    - pattern: |
        \ interface:.*$
    - repl: |
             interface: {{ myip }}

{{ this.prefix }}{{ root_hints_file }}:
  file.managed:
    - user: {{ this.user }}
    - mode: 644
    - makedirs: True
    - source: http://www.internic.net/domain/named.cache
    - source_hash: http://www.internic.net/domain/named.cache.md5


{{ this.ad_servers }}:
  file.managed: 
    - user: {{ this.user }}
    - mode: 644
    - source: 
      - http://pgl.yoyo.org/adservers/serverlist.php?hostformat=unbound;showintro=0 
      - salt://dns/files/unbound_ad_servers

ad_servers_replace:   
  file.replace:
    - name: {{ this.ad_servers }}
    - repl: ''
    - pattern: |
        <[^>]*> 
        ^Ad.* 


{{ this.prefix }}{{ anchor_file }}:
  file.touch: 
    - makedirs: True 

unbound-anchor -a {{ this.prefix }}{{ anchor_file }}:
  cmd.run

{% endif %}

{{ this.include }}:
  file.touch:
    - makedirs: True 

include zones into {{ this.name }} config: 
  file.append:
    - name: {{ this.conf_file }}
    - text: |
        include: {{ this.include }}


#################################################################################
# Start services    
#################################################################################

start_service {{ this.name }}: 
  service.running:
    - name: {{ this.name }}
    - enable: True
    - watch: 
      - file: {{ this.conf_file }}
      - file: {{ this.include }}
{% endfor %}