ARG CONTRAIL_REGISTRY
ARG CONTRAIL_CONTAINER_TAG
FROM ${CONTRAIL_REGISTRY}/contrail-base:${CONTRAIL_CONTAINER_TAG}
ARG VENDOR_DOMAIN
ARG CONTRAIL_BUILD_FROM_SOURCE
ARG CONTAINER_NAME
LABEL name=$CONTAINER_NAME \
      summary="Contrail statistics client" \
      description="Contrail statistics client collects statistics about number of virtual networks, virtual routers , etc. No private information is collected."

RUN if [[ -z "$CONTRAIL_BUILD_FROM_SOURCE" ]] ; then \
      yum install -y git && \
      git clone --single-branch https://github.com/Juniper/contrail-controller.git && \
      cd contrail-controller/src/stats && \
      python setup.py install --no-compile && \
      yum autoremove -y git && \
      yum clean all -y && \
      rm -rf /var/cache/yum && \
      rm -rf /contrail-controller; \
    fi

COPY *.sh /
ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/bin/contrail-stats-client", "--config-file", "/etc/contrail/contrail-stats-client.conf"]

ENV NODE_TYPE=config
LABEL $VENDOR_DOMAIN".pod"=$NODE_TYPE

ENV SERVICE_NAME=stats
LABEL $VENDOR_DOMAIN".service"=$SERVICE_NAME
LABEL $VENDOR_DOMAIN".container.name"=$CONTAINER_NAME
