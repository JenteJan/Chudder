FROM nginx:alpine

EXPOSE 80

ENV BASE_URL=""
ENV JELLYBOT_URL=""
ENV FLADDER_WEBPATH="/"

COPY build/web /usr/share/nginx/html

RUN mkdir -p /usr/share/nginx/html/assets/config && \
    chown -R nginx:nginx /usr/share/nginx/html && \
    chmod +x /docker-entrypoint.sh && \
    chown -R nginx:nginx /etc/nginx/conf.d \

RUN echo '{"baseUrl": "${BASE_URL}"}' > /usr/share/nginx/html/assets/config/config.json

CMD /bin/sh -c 'sed -i "s|\${BASE_URL}|${BASE_URL}|g" /usr/share/nginx/html/assets/config/config.json && nginx -g "daemon off;"'
CMD ["/bin/sh", "-c", "echo \"{\\\"baseUrl\\\": \\\"${BASE_URL:-https://cine.maktep.fr}\\\", \\\"jellybotBaseUrl\\\": \\\"${JELLYBOT_URL:-https://jellybot.maktep.fr}\\\"}\" > /usr/share/nginx/html/assets/config/config.json && nginx -g 'daemon off;'"]

CMD ["/docker-entrypoint.sh"]