// Casri POS — bundled cloud config.
// Only the public web API key and project id are needed for the REST calls.
// These are safe to ship: they identify the project, they do not grant access.
// Access is controlled by Firebase Auth (each shop signs in) plus Firestore
// rules that scope every document to the signed-in user's own uid.
//
// Reuses the existing Firebase project so no new console setup is needed.
window.BUNDLED_CLOUD_CFG = {
  apiKey: "AIzaSyCEZxp9W7_h2Nu1qs_wiQdrbXARVb5yvg8",
  projectId: "isguul-togdheer"
};
