AWSUtils
====

MovableType管理画面でAWSを操作するプラグインです。

## スリーンショット
![スクリーンショット](https://user-images.githubusercontent.com/375844/38234872-24368c7a-375a-11e8-9b74-4c5a3770642c.png)

## 機能
* スナップショットの取得/一覧表示  
* CloudFrontのキャッシュ削除  
  * WebSite/ブログ個別に設定可能  
* S3への転送機能  
  * WebSite/ブログ個別に設定可能  
    * WebSiteを転送するとブログも一緒に転送されます  
    * Cloudfrontが登録されている場合はInvalidationもします  
* システム管理者権限で動作します  
* ログ  
  * 動作結果はエラーも含めてログに記録されます。  

## 動作環境

* Movable Type ６/7  
* PSGI/CGI  
* run-periodic-tasksで動作します  
* pythonモジュールawscliを事前にインストールして下さい（Amazon Linuxの場合は必要ありません）。configureは必要ありません。  

## 設定
プラグインセッティングでAWSのアクセスキーやシークレットを登録する必要があります。
ブログに設定が存在しない場合はWebSiteの設定を引き継ぎます。

## 注意
プラグインはβ版です。動作保証は致しません。十分検証の上ご利用ください。

## Licence

[ライセンス](https://github.com/onagatani/MT-AWSUtils/blob/master/LICENSE)

## Author

[onagatani](https://github.com/onagatani)
