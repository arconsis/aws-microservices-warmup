require('dotenv').config();

const config = {
  databaseUri: `postgres://${process.env.DB_USER}:${process.env.DB_PASS}@${process.env.DB_HOST}:${process.env.DB_PORT}/${process.env.DB_NAME}`,
  aws: {
    s3: {
      region: process.env.AWS_S3_REGION,
      bucket: process.env.AWS_S3_BUCKET,
    },
  },
};

module.exports = Object.freeze(config);
