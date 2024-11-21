const express = require('express');
const passport = require('passport');
const GoogleStrategy = require('passport-google-oauth20').Strategy;
const session = require('express-session');
const {Storage} = require('@google-cloud/storage');
const {Datastore} = require('@google-cloud/datastore');
const {Firestore} = require('@google-cloud/firestore');
const multer = require('multer');
const util = require('util');
const {BigQuery} = require('@google-cloud/bigquery');
const config = require('./config');



var app = express();

app.set('view engine', 'ejs');

// Add the express-session middleware
app.use(session({
    secret: 'gen-ai-insights-demo-secret-key',
    resave: false,
    saveUninitialized: false
  }));

passport.use(new GoogleStrategy({
  clientID: config.clientID,
  clientSecret: config.clientSecret,
  callbackURL: config.callbackURL,
  passReqToCallback: true
},
(request, accessToken, refreshToken, profile, done) => {
  const domain = profile.emails[0].value.split('@')[1];
  if (config.allowedDomains.includes(domain)) {
    return done(null, profile);
  } else {
    return done(null, false, { message: 'Only @central.tech accounts are allowed to log in.' });
  }
}));

passport.serializeUser((user, done) => {
  done(null, user.id);
});

passport.deserializeUser((id, done) => {
  done(null, { id });
});

app.use(passport.initialize());
app.use(passport.session());

app.use(express.static('public'));


app.get('/', (req, res) => {
  res.sendFile(__dirname + '/html_files/login.html');
});

app.get('/auth/google', passport.authenticate('google', { scope: ['profile', 'email'] }));

app.get('/auth/google/callback', passport.authenticate('google', {
  successRedirect: '/success',
  failureRedirect: '/failure'
}));

app.get('/success', (req, res) => {
  if (req.isAuthenticated()) {
    var results = [];
    res.render('upload', { statusMessage: '', searchResults: results });
  } else {
    res.redirect('/');
  }
});

app.get('/site-settings', async (req, res) => {
  if (req.isAuthenticated()) {
    const configStore = await firestore.collection('config').doc('site_config').get();
    if (config.exists) {
      res.render('settings', { statusMessage: '', config: configStore.data() });
    } else {
      res.render('settings', { statusMessage: 'No config found. Please create one.', config: config });
    }
  } else {
    res.redirect('/');
  }
});

app.post('/config', async (req, res) => {
  if (!req.isAuthenticated()) {
    res.status(401).send('Unauthorized');
    return;
  }
  const {clientID, clientSecret, callbackURL, allowedDomains, projectId, prompt_summary, prompt_action_items} = req.body;
  await firestore.collection('config').doc('site_config').set({
    clientID: { name: 'clientID', value: clientID },
    clientSecret: { name: 'clientSecret', value: clientSecret },
    callbackURL: { name: 'callbackURL', value: callbackURL },
    allowedDomains: { name: 'allowedDomains', value: allowedDomains },
    projectId: { name: 'projectId', value: projectId },
    prompt_summary: { name: 'prompt_summary', value: prompt_summary },
    prompt_action_items: { name: 'prompt_action_items', value: prompt_action_items },
  });
  res.render('settings', { statusMessage: 'Config updated successfully.', config: config });
});


app.get('/search', (req, res) => {
  if (req.isAuthenticated()) {
    const caseId = req.query['case-id'];

    const query = firestore.collection('audio-files-metadata').where('caseid', '==', caseId).orderBy('caseid', 'desc');

    query.get().then((querySnapshot) => {
      const results = [];
      querySnapshot.forEach((doc) => {
        const data = doc.data();
        console.log(util.inspect(data, {showHidden: false, depth: null, colors: true}))
        results.push({
          gcsUri: data.gcsUri,
          caseId: data.caseid,
          timestamp: new Date(data.timestamp).toLocaleString('en-SG', {timeZone: 'Asia/Singapore'}),
          aiInsights: doc.id,
          processingStatus: data.status
        });
      });
      res.render('upload', { statusMessage: '', searchResults: results, refresh: true });
    });
  } else {
    res.redirect('/');
  }
});

app.get('/failure', (req, res) => {
  res.send('Login failed.');
});

const storage = new Storage();
const datastore = new Datastore();
const firestore = new Firestore();

const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 500 * 1024 * 1024, // no larger than 5mb
  },
});

app.post('/upload', upload.single('audio'), async (req, res) => {
  if (!req.isAuthenticated()) {
    res.status(401).send('Unauthorized');
    return;
  }

  const file = req.file;

  const bucketName = config.projectId+'-operation-insights-audio-files';
  const case_timestamp = Date.now();
  const entity = {
    key: datastore.key(['audio-files-metadata']),
    data: [
      {
        name: 'caseid',
        value: req.body['case-id'],
      },
      {
        name: 'timestamp',
        value: case_timestamp
      },
      {
        name: 'status',
        value: 'processing'
      }
    ],
  };

  await datastore.save(entity);
  
  const fileName = `__id${entity.key.id}__${file.originalname.split('.')[0]}-${case_timestamp}.${file.originalname.split('.')[1]}`;
  const fileUpload = storage.bucket(bucketName).file(fileName);

  // Add one more field after the entity is saved
  entity.data.push({
    name: 'gcsUri',
    value: `gs://${bucketName}/${fileName}`,
  });
  await datastore.save(entity);

  const apiResponse = await fileUpload.save(file.buffer);
  var results = [];
  res.render('upload', { statusMessage: 'File uploaded successfully.', searchResults: results });
});

// Create an API endpoint to get the audio file URL
app.get('/api/getAudioFileUrl/:docId', async (req, res) => {
  const db = new Firestore();
  const bigquery = new BigQuery();
  const storage = new Storage({scopes: [
    'https://www.googleapis.com/auth/devstorage.full_control',
    'https://www.googleapis.com/auth/iam',
    'https://www.googleapis.com/auth/cloud-platform'
  ]} );

  const docId = req.params.docId;

  const docRef = db.collection('audio-files-metadata').doc(docId);
  const doc = await docRef.get();

  if (!doc.exists) {
    res.status(404).send('Document not found');
    return;
  }

  const data = doc.data();
  var gcsUri = data.gcsUri;
  var raw_transcript = data.raw_transcript;
  const { bucketName, fileName } = extractBucketAndFilename(gcsUri);
  console.log(gcsUri);
  console.log(bucketName);
  console.log(fileName);
  // These options will allow temporary read access to the file
  const options = {
    version: 'v4',
    action: 'read',
    expires: Date.now() + 1000 * 60 * 10, // 10 min
  };
  const [url] = await storage.bucket(bucketName).file(fileName).getSignedUrl(options);
  // The SQL query to execute

  
  var action_items = [];
  var ai_summary = "AI Summary Not Found.";
  var raw_transcrip_text = "Transcript Not Found.";
  var sentiment_score = "Unknown";
  var sentiment_desc= "Unknown";
  
  if (raw_transcript) {
    raw_transcript_json = JSON.parse(raw_transcript);
    ai_summary = raw_transcript_json.detailed_summary;
    raw_transcript_text = raw_transcript_json.raw_transcript;
    sentiment_score = raw_transcript_json.sentiment_score;
    sentiment_desc = raw_transcript_json.sentiment_description;
    action_items = raw_transcript_json.action_items;
  }


  // Send the signed URL back to the client

  res.json({
    gcsUri: url,
    aiSummary: ai_summary,
    sentiment_score: sentiment_score,
    sentiment_desc: sentiment_desc,
    action_items: action_items,
    raw_transcript: raw_transcript_text
  });
});

function extractBucketAndFilename(gcsUri) {
  // Split the URI by '/' separators
  const uriParts = gcsUri.split('/');

  // The bucket name is the 3rd element (index 2)
  const bucketName = uriParts[2];

  // The filename is everything after the bucket name
  const fileName = uriParts.slice(3).join('/');
  console.log(uriParts);
  console.log(fileName);
  return { bucketName, fileName };
}

const port = parseInt(process.env.PORT) || 8080;

app.listen(port, () => {
  console.log('App listening on port 8080');
});

