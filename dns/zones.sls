{% from "dns/map.jinja" import dns with context %}
{% if dns.mydomains is defined %}
{% set i = 1 %}
{% for name, domain in salt['pillar.get']('dns:mydomains', {}).items() %}
{% for zone_type, zone in { 'forward': { 'name': name } ,  'reverse': { 'name': '0.0.'+domain.local_zone+'.' }}.items() %}
{% set sn = None |strftime("%Y%m%d")+"0"+i|string %}
{% set i = i + 1  %}


include: 
  - dns

#################################################################################
# ZONES FILES GENERATION    
#################################################################################


{{ dns.nsd.config.server.zonesdir }}/{{ name }}.{{ zone_type }}: 
  file.managed: 
    - user: {{ dns.nsd.user }}
    - mode: 640 


Zone file content for {{ name }}.{{ zone_type }}: 
  file.blockreplace:
    - name: {{ dns.nsd.config.server.zonesdir }}/{{ name }}.{{ zone_type }}
    - marker_start: ";#######  START MANAGED Zone - {{ name }}.{{ zone_type }} -DO-NOT-EDIT-"
    - marker_end: ";#######  END MANAGED Zone - {{ name }}.{{ zone_type }} -DO-NOT-EDIT-"
    - append_if_not_found: True
    - content: |
{%- if zone_type == 'forward' %}
          ;## NSD authoritative only DNS
          ;## FORWARD Zone - {{ name }}.{{ zone_type }}
          $ORIGIN {{ name }}.    ; default zone domain
          $TTL 86400           ; default time to live
          @ IN SOA ns1 admin@{{ name }} (
{%- else %}
          ;## NSD authoritative only DNS
          ;## REVERSE Zone - {{ name }}.{{ zone_type }}
          ;$ORIGIN {{ zone.name }}  ; default zone domain
          $TTL 86400         ; default time to live
          {{ zone.name }} IN SOA {{ domain.records.NS1 }}.{{ name }}. admin@{{ name }} (
{%- endif %}
           {{ sn }}  ; serial number
           28800       ; Refresh
           7200        ; Retry
           864000      ; Expire
           86400       ; Min TTL
           )
           NS      {{ domain.records.NS1 }}.{{ name }}.
           NS      {{ domain.records.NS2 }}.{{ name }}.
           MX      10 {{ domain.records.MX }}.{{ name }}.

A Records accumulator for zone {{ name }} {{ zone_type }}:
  file.accumulated:
    - filename: {{ dns.nsd.config.server.zonesdir }}/{{ name }}.{{ zone_type }}
    - require_in:
      - file: {{ dns.nsd.config.server.zonesdir }}/{{ name }}.{{ zone_type }}
    - text: |
{%- for record, ip in domain.records.A|dictsort(by='value') %}
{%- if zone_type == 'forward' %}
{%- set spacer = ' '*(20-record|length) %}
{%- if record == 'wildcard' %}
          *                         IN     A     {{ ip }}
{%- else %}
          {{ record }} {{ spacer }}     IN     A     {{ ip }}
{%- endif %}
{%- else %}
{%- set spacer = ' '*(20-ip|length) %}
          {{ salt['network.reverse_ip'](ip) }}. {{ spacer }}     IN     PTR     {{ record }}.{{ name }}.
{%- endif %}
{%- endfor %}
{%- if zone_type == 'forward' %}
          @                         IN     A     {{ domain.primary_ip }}
{%- endif %}


#################################################################################
# NSD INCLUDE ZONES INTO CONFIG + CLUSTER CONFIG     
#################################################################################


NSD block for zone {{ name }} {{ zone_type }}:
  file.blockreplace:
    - name: {{ dns.nsd.include }}
    - marker_start: "########## START managed zone for domain {{ name }} {{ zone_type }} -DO-NOT-EDIT-"
    - marker_end: "########## END managed zone for domain {{ name }} {{ zone_type }} -DO-NOT-EDIT-"
    - append_if_not_found: True
    - show_changes: True
    - watch_in:
    - content: | 
          zone:                                                                                                                                                  
              name: {{ zone.name }}
              zonefile: "{{ name }}.{{ zone_type }}"                                                                                                                   
{%- if dns.cluster_config is defined %}
{%- if domain.primary_ip in salt['grains.get']('ipv4') %}
              notify: {{ domain.secondary_ip }} {{ dns.nsd.config.key.name }}
              provide-xfr: {{ domain.secondary_ip }} {{ dns.nsd.config.key.name }}
{%- elif domain.secondary_ip in salt['grains.get']('ipv4') %}
              notify-allow: {{ domain.primary_ip }} {{ dns.nsd.config.key.name }}
              request-xfr: {{ domain.primary_ip }} {{ dns.nsd.config.key.name }}
{%- endif %}
{%- endif %}
{%- endfor %}



#################################################################################
# UNBOUND INCLUDE ZONES INTO CONFIG     
#################################################################################

Unbound block for zone {{ name }}:
  file.blockreplace:
    - name: {{ dns.unbound.include }}
    - marker_start: "########## START managed zone for domain {{ name }} -DO-NOT-EDIT-"
    - marker_end: "########## END managed zone for domain {{ name }} -DO-NOT-EDIT-"
    - append_if_not_found: True
    - show_changes: True
    - content: | 
          private-domain: "{{ name }}"
          local-zone: "{{ domain.local_zone }}." nodefault
          stub-zone:
              name: "{{ name }}"
              stub-addr: {{ salt['pillar.get']('dns:nsd:config:server:ip-address') }}@{{ dns.nsd.config.server.port }}
          stub-zone:
              name: "0.0.{{ domain.local_zone }}"
              stub-addr: {{ salt['pillar.get']('dns:nsd:config:server:ip-address') }}@{{ dns.nsd.config.server.port }}


#################################################################################
# /etc/resolv.conf part      
#################################################################################


{% if dns.resolv_conf == True %}
{% if salt['service.status']('unbound') %}

domain {{ name }} accumulator in /etc/resolv.conf:
  file.accumulated:
    - filename: /etc/resolv.conf
    - require_in:
      - file: resolv.conf block for domain {{ name }}
    - text: |
        search {{ name }} 
{%- if dns.fwzones is defined %}
{%- for fwzone, records in dns.fwzones.items() %}
        search {{ fwzone }}
{%- endfor %}
{%- endif %}


resolv.conf block for domain {{ name }}:
  cmd.run: 
    - name: echo > /etc/resolv.conf 
  file.blockreplace:
    - name: /etc/resolv.conf
    - marker_start: "########## START managed block in resolv.conf for {{ name }} -DO-NOT-EDIT-"
    - marker_end: "########## END managed block in resolv.conf for domain {{ name }} -DO-NOT-EDIT-"
    - append_if_not_found: True
    - show_changes: True
    - content: |
        nameserver {{ domain.primary_ip }}
        nameserver {{ domain.secondary_ip }}
        lookup bind
{% endif %}
{% endif %}


nsd-control reload {{ name }} && unbound-control flush {{ name }}:
  cmd.run:
    - service: nsd
    - service: unbound 


{% endfor %}
{% endif %}


#################################################################################
# UNBOUND INCLUDE FORWARDING ZONES INTO CONFIG (IF DEFINED)     
#################################################################################


unbound forward zones:
  file.blockreplace:
    - name: {{ dns.unbound.include }}
    - marker_start: "########## START managed block for forward zones config -DO-NOT-EDIT-"
    - marker_end: "########## END managed block for forward zones config -DO-NOT-EDIT-"
    - append_if_not_found: True
    - show_changes: True
    - content: | 
{%- if dns.fwzones is defined %}
{%- for name, zone in dns.fwzones.items() %}
          forward-zone: 
              name: {{ name }}
{%- for key, value in zone.items() %}
              forward-addr: {{ value }}
{%- endfor %}
{%- endfor %}
{%- endif %}



