FROM nginx:alpine
COPY ./nginx.conf /etc/nginx/nginx.conf
COPY ./templates/*.template /etc/nginx/templates/

RUN rm -f /etc/nginx/conf.d/default.conf

EXPOSE 80 443