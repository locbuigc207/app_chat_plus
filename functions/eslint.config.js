/**
 * Flat config cho ESLint >= 9
 * Thay thế hoàn toàn cho .eslintrc.js cũ
 */
"use strict";

const js = require("@eslint/js");
const globals = require("globals");

module.exports = [
  // 1. Bỏ qua các thư mục không cần kiểm tra (Thay thế cho .eslintignore)
  {
    ignores: ["node_modules/**", "lib/**"],
  },

  // 2. Tích hợp các quy tắc khuyên dùng mặc định của ESLint
  js.configs.recommended,

  // 3. Cấu hình chính áp dụng cho toàn bộ mã nguồn Node.js của bạn
  {
    languageOptions: {
      ecmaVersion: "latest",
      sourceType: "commonjs", // Giữ nguyên theo chuẩn module.exports/require
      globals: {
        ...globals.node,
        ...globals.es2021,
      },
    },
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
  },

  // 4. Cấu hình ghi đè (Overrides) dành riêng cho các file Test
  {
    files: ["**/*.spec.*", "**/*.test.*"],
    languageOptions: {
      globals: {
        ...globals.mocha,
      },
    },
  },
];
