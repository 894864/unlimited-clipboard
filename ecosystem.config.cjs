const path = require('node:path');

module.exports = {
  apps: [{
    name: 'unlimited-clipboard',
    cwd: path.join(__dirname, 'website'),
    script: 'server.js',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '200M',
    env: { NODE_ENV: 'production', PORT: 3001 }
  }]
};
