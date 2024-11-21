// config.js
const {Firestore} = require('@google-cloud/firestore');
const firestore = new Firestore();

const getConfig = () => {
  const config = firestore.collection('config').doc('site_config').get();
  if (config.exists) {
    return config.data();
  } else {
    return {
      clientID: '000000000000-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx.apps.googleusercontent.com',
      clientSecret: 'GOCSPX-xxxxxxxxxxxxxxxxxxxxxxxxxxxx',
      callbackURL: 'https://ccinsights-xxxxxxxxxx-xx.x.run.app/auth/google/callback',
      allowedDomains: ['google.com','YOUR-DOMAIN'],
      projectId: 'YOUR-PROJECT',
      prompt_summary: '',
      prompt_action_items: '',
    };
  }
};

module.exports = getConfig();