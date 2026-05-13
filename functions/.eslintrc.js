module.exports = {
  env: {
    es6: true,
    node: true,
  },
  parserOptions: {
    ecmaVersion: 2018,
  },
  extends: [
    "eslint:recommended",
  ],
  rules: {
    "no-restricted-globals": ["error", "name", "length"],
    "prefer-arrow-callback": "error",
    "quotes": ["error", "double", {"allowTemplateLiterals": true}],
    "max-len": "off",
    "indent": ["error", 2],
    "object-curly-spacing": ["error", "never"],
    "comma-dangle": ["error", "always-multiline"],
    "operator-linebreak": ["error", "after"],
    "eol-last": ["error", "always"],
    "no-console": "off",
    "no-unused-vars": ["error", {"args": "none"}],
  },
  overrides: [
    {
      files: ["**/*.spec.*"],
      env: {
        mocha: true,
      },
      rules: {},
    },
  ],
  globals: {},
};
