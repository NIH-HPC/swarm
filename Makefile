.PHONY: install

install:
	install -p -m 0755 -o root -g root swarm /usr/local/bin
	ls -l /usr/local/bin/swarm
	install -p -m 0740 -o helixmon -g staff swarm_manager /usr/local/sbin
	ls -l /usr/local/sbin/swarm_manager
	install -p -m 0644 -o webcpu -g webcpu swarm.html /usr/local/www/hpcweb/htdocs/apps
	ls -l /usr/local/www/hpcweb/htdocs/apps/swarm.html
	install -p -m 0644 -o root -g root swarm.1 /usr/local/share/man/man1
	ls -l /usr/local/share/man/man1/swarm.1
