.PHONY: install

install:
	install -p -m 0755 -o root -g root swarm /usr/local/bin
	install -p -m 0740 -o helixmon -g staff swarm_manager /usr/local/sbin
	install -p -m 0644 -o webcpu -g webcpu swarm.html /usr/local/www/hpcweb/htdocs/apps
	install -p -m 0644 -o root -g root swarm.1 /usr/local/share/man/man1
