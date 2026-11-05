// Tako Den web app. Every page is a module under js/; this file maps paths
// to them and starts the router.
import { api, render, route, session } from './js/core.js';
import { adminPage } from './js/admin.js';
import { linkPage, loginPage, oauthPage, registerPage, setupPage } from './js/auth.js';
import { chatPage } from './js/chat.js';
import { settingsPage } from './js/settings.js';

route('/', chatPage);
route('/login', loginPage);
route('/register', registerPage);
route('/setup', setupPage);
route('/oauth', oauthPage);
route('/link', linkPage);
route('/settings', settingsPage);
route('/admin', adminPage);

session.info = await api('/v1/info').catch(() => null);
if (session.info) document.title = session.info.name;
render();
