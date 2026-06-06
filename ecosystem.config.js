module.exports = {
  apps: [
    {
      name: 'professor-bot',
      script: 'main.rb',
      interpreter: 'ruby',
      cwd: '/root/mastodon_bots/professor_bot',
      instances: 1,
      autorestart: true,
      watch: false,
      max_memory_restart: '500M',
      env: {
        NODE_ENV: 'production'
      },
      error_file: './logs/professor-bot-error.log',
      out_file: './logs/professor-bot-out.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      merge_logs: true,
      restart_delay: 5000
    }
  ]
};
