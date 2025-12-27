/** @type {import('jest').Config} */
module.exports = {
  testEnvironment: 'node',
  transform: {
    '^.+\\.(t|j)sx?$': ['ts-jest', { tsconfig: './tsconfig.json' }],
  },
  roots: ['<rootDir>/tests'],
};

