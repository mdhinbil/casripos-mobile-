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

// The MareegTech super-admin account. This account signs in through the normal
// "I have a workspace" login and gets the Workspaces approval page instead of a
// till. Set this to the email you'll use as super admin, and use the SAME email
// in the Firestore rules. New client workspaces stay locked until this account
// approves them.
window.CASRI_MASTER_EMAIL = "admin@mareegtech.com";
