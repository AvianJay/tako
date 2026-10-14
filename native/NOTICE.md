The JavaScript runtime embeds QuickJS-NG v0.17.0, downloaded during the build
from https://github.com/quickjs-ng/quickjs/releases/tag/v0.17.0 and verified
against SHA-256 a0955463c74809173a253ff87365095e6972e8b171cfb6aa8a1e781adf35cfeb.

The upstream amalgamation retains its MIT copyright and license notices.
Tako builds the language engine without quickjs-libc and installs no filesystem,
network, native-module or standard-module loader. The bridge exposes only
audited browser/phone operations. Native source lives in the build cache.
