/** @type {import('jest').Config} */
module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'jsdom',
  transform: {
    '^.+\\.(t|j)sx?$': [
      'ts-jest',
      { tsconfig: './jest.tsconfig.json' }
    ],
  },
  roots: ['<rootDir>/tests'],
  testPathIgnorePatterns: ['<rootDir>/tests/e2e'],
  globals: { 'ts-jest': { tsconfig: { types: ['jest','node'] } } }
};

