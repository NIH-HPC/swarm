help:
	@echo targets: help swarm swarm_cleanup webpages manpages

swarm:
	@echo installing swarm
	install -p -m 0755 -o root -g root swarm /usr/local/bin
	sed -i "s/NNNNN_DATESTAMP_NNNNN/$(shell git log -1 --format=%cd swarm)/" /usr/local/bin/swarm
	ls -l /usr/local/bin/swarm

swarm_cleanup:
	@echo installing swarm_cleanup.pl
	install -p -m 0740 -o root -g staff swarm_cleanup.pl /usr/local/sbin
	ls -l /usr/local/sbin/swarm_cleanup.pl

webpages:
	@echo installing webpages
	install -p -m 0644 -o webcpu -g webcpu swarm.html /usr/local/www/hpcweb/htdocs/apps
	ls -l /usr/local/www/hpcweb/htdocs/apps/swarm.html

manpages:
	@echo installing manpages
	install -p -m 0644 -o root -g root swarm.1 /usr/local/share/man/man1
	ls -l /usr/local/share/man/man1/swarm.1

.PHONY: swarm swarm_cleanup webpages manpages
