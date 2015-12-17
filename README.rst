=========================================================================================
NSD and Unbound (authoritative and caching resolving) DNS server configuration    
=========================================================================================


Formulas to set up and configure both resolving and authoritive DNS server

.. note::

    See the full `Salt Formulas installation and usage instructions
    <http://docs.saltstack.com/topics/development/conventions/formulas.html>`_.

Available states
================

.. contents::
    :local:

``dns``
----------------------------------------------------------------------------------------

Installs packages, and a basic config.


``dns.zones``
----------------------------------------------------------------------------------------

Generates zones files for domains defined in a pillar file, 
and reloads NSD server with a new configuration  
  


``dns.check``
----------------------------------------------------------------------------------------


Basic healthcheck 