/** @type {import('jest').Config} */
module.exports = {
    testEnvironment: "node",
    testMatch: ["**/tests/**/*.test.ts"],
    testTimeout: 30000,
    verbose: true,
    transform: {
        "^.+\\.ts$": "@swc/jest",
    },
};
