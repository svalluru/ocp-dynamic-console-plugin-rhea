# OCP dynamic plugin image — matches openshift/console-plugin-template pattern.
# Build runs `npm run build` (production webpack + ConsoleRemotePlugin).
FROM registry.access.redhat.com/ubi9/nodejs-22:latest AS build
USER root
WORKDIR /opt/app-root/src
COPY package.json package-lock.json ./
RUN npm ci
COPY tsconfig.json webpack.config.cjs console-extensions.json ./
COPY locales ./locales
COPY public ./public
COPY src ./src
RUN npm run build

# Cluster deploy: ConfigMap nginx serves from /usr/share/nginx/html over HTTPS (8443); see deploy/nginx.conf.
# Also copy to /opt/app-root/src so a stock-config local run (podman without ConfigMap) still serves files on 8080.
FROM registry.access.redhat.com/ubi9/nginx-120:latest
COPY --from=build /opt/app-root/src/dist/ /usr/share/nginx/html/
COPY --from=build /opt/app-root/src/dist/ /opt/app-root/src/
# Fail the image build if webpack did not emit the console manifest (avoids 404 readiness in the cluster).
RUN test -f /usr/share/nginx/html/plugin-manifest.json \
  || (echo "error: /usr/share/nginx/html/plugin-manifest.json missing — webpack build did not produce dist/" >&2; exit 1)
USER 1001
ENTRYPOINT ["nginx", "-g", "daemon off;"]
