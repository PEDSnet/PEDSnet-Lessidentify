# Minimal Dockerfile for PEDSnet::Lessidentify build, using standard
# Perl image as base
#
# Once built, you can run with access to files in /your/data/dir
# by saying
#   docker run -v /your/data/dir:/working --rm -it PEDSnet-Lessidentify

FROM perl:latest
LABEL description "Simple image for PEDSnet::Lessidentify"
LABEL maintainer "Charles Bailey <baileyc@email.chop.edu>"


# To set up using released version of PEDSnet::Lessidentify, just say
#   docker build -t PEDSnet-Lessidentify -f /path/to/this/file
RUN cpanm PEDSnet::Lessidentify

# Alternatively, to install local copy, first say
#   dzil build
# then comment out the RUN above, and uncomment the COPY and RUN
# below, then say
#   docker build -t PEDSnet-Lessidentify -f etc/Dockerfile
#COPY PEDSnet-Lessidentify-*.tar.gz /src/ 
#RUN cpanm /src/*.tar.gz


RUN useradd -m -s /bin/bash normalized
USER normalized
WORKDIR /working
CMD /bin/bash  
