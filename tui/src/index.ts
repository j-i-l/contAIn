// SPDX-FileCopyrightText: 2024-2026 Jonas I. Liechti <j-i-l@t4d.ch>
//
// SPDX-License-Identifier: CC-BY-NC-4.0
import('./app.js')
  .then(({ App }) => {
    const app = new App();
    return app.init().then(() => app);
  })
  .then((app) => {
    app.run();
  })
  .catch((err) => {
    console.error('ERROR:', err);
    if (err?.stack) console.error(err.stack);
    process.exit(1);
  });