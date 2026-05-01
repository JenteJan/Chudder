FROM nginx:alpine

EXPOSE 80

ENV BASE_URL=""
ENV JELLYBOT_URL=""
ENV FLADDER_WEBPATH="/"

COPY build/web /usr/share/nginx/html

RUN mkdir -p /usr/share/nginx/html/assets/config && \
    chown -R nginx:nginx /usr/share/nginx/html && \
    chown -R nginx:nginx /etc/nginx/conf.d

CMD ["/bin/sh", "-c", \
  "echo \"{\\\"baseUrl\\\": \\\"${BASE_URL:-https://cine.maktep.fr}\\\", \\\"jellybotBaseUrl\\\": \\\"${JELLYBOT_URL:-https://jellybot.maktep.fr}\\\"}\" > /usr/share/nginx/html/assets/config/config.json && exec nginx -g 'daemon off;'"]
