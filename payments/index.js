
const { setGlobalOptions } = require("firebase-functions");
const { onRequest } = require("firebase-functions/https");

setGlobalOptions({ maxInstances: 10 });

exports.healthCheck = onRequest((request, response) => {
  response.status(200).json({
    status: "ok",
    message: "Payments backend is running",
  });
});
