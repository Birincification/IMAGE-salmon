FROM combinelab/salmon:1.4.0

RUN apt-get update --fix-missing -qq && \
	apt-get install -y -q \
	sysstat \
	&& apt-get clean \
	&& apt-get purge

ADD scripts /home/scripts
