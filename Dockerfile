FROM nginx:alpine

EXPOSE 80

ENV BASE_URL=""
ENV JELLYBOT_URL=""

COPY build/web /usr/share/nginx/html

CMD ["/bin/sh", "-c", "echo \"{\\\"baseUrl\\\": \\\"${BASE_URL:-https://cine.maktep.fr}\\\", \\\"jellybotBaseUrl\\\": \\\"${JELLYBOT_URL:-https://jellybot.maktep.fr}\\\"}\" > /usr/share/nginx/html/assets/config/config.json && nginx -g 'daemon off;'"]
