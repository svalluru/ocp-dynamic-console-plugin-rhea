'use strict';

const path = require('path');
const { ConsoleRemotePlugin } = require('@openshift-console/dynamic-plugin-sdk-webpack');
const CopyWebpackPlugin = require('copy-webpack-plugin');
const HtmlWebpackPlugin = require('html-webpack-plugin');

const isProd = process.env.NODE_ENV === 'production';
/** Local browser preview at :9001 — skips ConsoleRemotePlugin so publicPath stays `/`. */
const localPreview = process.env.RHEA_PREVIEW === '1';

module.exports = {
  mode: isProd ? 'production' : 'development',
  entry:
    isProd || !localPreview
      ? {}
      : {
          preview: './preview.tsx',
        },
  context: path.resolve(__dirname, 'src'),
  output: {
    path: path.resolve(__dirname, 'dist'),
    filename: isProd ? '[name]-bundle-[hash].min.js' : '[name]-bundle.js',
    chunkFilename: isProd ? '[name]-chunk-[chunkhash].min.js' : '[name]-chunk.js',
    ...(localPreview && !isProd ? { publicPath: '/' } : {}),
  },
  resolve: {
    extensions: ['.ts', '.tsx', '.js', '.jsx'],
  },
  module: {
    rules: [
      {
        test: /\.(jsx?|tsx?)$/,
        exclude: /\/node_modules\//,
        use: [
          {
            loader: 'ts-loader',
            options: {
              configFile: path.resolve(__dirname, 'tsconfig.json'),
            },
          },
        ],
      },
      {
        test: /\.(css)$/,
        use: ['style-loader', 'css-loader'],
      },
      {
        test: /\.(png|jpg|jpeg|gif|svg|woff2?|ttf|eot|otf)(\?.*$|$)/,
        type: 'asset/resource',
        generator: {
          filename: isProd ? 'assets/[contenthash][ext]' : 'assets/[name][ext]',
        },
      },
      {
        test: /\.(m?js)$/,
        resolve: {
          fullySpecified: false,
        },
      },
    ],
  },
  devServer: {
    static: localPreview ? path.resolve(__dirname, 'public') : path.resolve(__dirname, 'dist'),
    port: 9001,
    allowedHosts: 'all',
    historyApiFallback: localPreview,
    headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, PATCH, OPTIONS',
      'Access-Control-Allow-Headers': 'X-Requested-With, Content-Type, Authorization',
    },
    devMiddleware: {
      writeToDisk: true,
    },
  },
  plugins: [
    ...(localPreview ? [] : [new ConsoleRemotePlugin()]),
    new CopyWebpackPlugin({
      patterns: [{ from: path.resolve(__dirname, 'locales'), to: 'locales' }],
    }),
    ...(localPreview && !isProd
      ? [
          new HtmlWebpackPlugin({
            template: path.resolve(__dirname, 'public/index.html'),
            chunks: ['preview'],
            inject: 'body',
          }),
        ]
      : []),
  ],
  devtool: isProd ? false : 'source-map',
  optimization: {
    chunkIds: isProd ? 'deterministic' : 'named',
    minimize: isProd,
  },
};
