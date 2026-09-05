FROM node:22-alpine

WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm install

COPY . .

EXPOSE 5173

ENV API_PROXY_TARGET=http://api:3000

CMD ["npm", "run", "dev", "--", "--host", "0.0.0.0", "--port", "5173"]
