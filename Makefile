help:
	@echo targets: help swarm swarm_manager webpages manpages

swarm:
	@echo installing swarm
	install -p -m 0755 -o root -g root swarm /usr/local/bin
	ls -l /usr/local/bin/swarm

swarm_manager:
	@echo installing swarm_manager
	install -p -m 0740 -o helixmon -g staff swarm_manager /usr/local/sbin
	ls -l /usr/local/sbin/swarm_manager

webpages:
	@echo installing webpages
	install -p -m 0644 -o webcpu -g webcpu swarm.html /usr/local/www/hpcweb/htdocs/apps
	ls -l /usr/local/www/hpcweb/htdocs/apps/swarm.html

manpages:
	@echo installing manpages
	install -p -m 0644 -o root -g root swarm.1 /usr/local/share/man/man1
	ls -l /usr/local/share/man/man1/swarm.1

.PHONY: swarm swarm_manager webpages manpages
