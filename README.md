AWSUtils
====

MovableType管理画面でAWSを操作するプラグインです。

## 機能
* スナップショットの取得/一覧表示  
* CloudFrontのキャッシュ削除  
  * サイト/ブログ個別に設定可能  
* S3への転送機能  
  * サイト/ブログ個別に設定可能  
    * 親サイトを転送するとブログも一緒に転送されます  
    * Cloudfrontが登録されている場合はInvalidationもします  
* システム管理者権限で動作します  
* ログ  
  * 動作結果はエラーも含めてログに記録されます。  

## 動作環境

* Movable Type 7以降  
* PSGI/CGI  
* run-periodic-tasksで動作します  
* aws-cli v2を事前にインストールして下さい。configureは必要ありません。  

## 設定
プラグインセッティングでAWSのアクセスキーやシークレットを登録する必要があります。
ブログに設定が存在しない場合は親サイトの設定を引き継ぎます。

## テスト

```bash
prove -v t/
```

## 変更履歴

### v1.0 (2026-04-08)

MT7+対応およびaws-cli v2対応のための大幅改修。

#### MT7+対応
* `$blog->parent` による親サイト参照に変更（旧APIへのフォールバック付き）
* `can_do('administer')` による権限チェックに変更
* メニューのviewにcontent_typeを追加
* テンプレートをMT7+のlayout/default.tmplに統一

#### aws-cli v2対応
* AWS::CLIWrapperをv1.27相当にアップデート
* `--output json` と `--no-cli-pager` を自動付与
* CloudFront create-invalidationを `--invalidation-batch` JSON形式に対応
* 新しいAWSサービスメソッドを追加（EKS, Glue, SageMaker等）
* 未知のサービスに対するAUTOLOADフォールバックを追加

#### 改善
* S3 sync後のCloudFront invalidation処理を改善
* describe_snapshots APIのエラーハンドリングを強化
* ec2_volume_id未設定時のジョブ投入制御を改善
* Workerのgrab_for/retry_delayを実運用に適した値に調整
* ブログレベルのAWS認証情報がExecに正しく反映されるよう改善
* AWSシークレットキーの入力フィールドをpassword型に変更
* 各ハンドラに権限チェックを追加
* CallerReferenceにPID+乱数を追加して一意性を向上
* 不要な依存 Module::Functions / Sub::Identify を削除
* ユニットテストを追加（7ファイル / 37テスト）

## 注意
プラグインはβ版です。動作保証は致しません。十分検証の上ご利用ください。

## Licence

[ライセンス](https://github.com/onagatani/MT-AWSUtils/blob/master/LICENSE)

## Author

[onagatani](https://github.com/onagatani)
