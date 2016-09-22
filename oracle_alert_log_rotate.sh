#!/bin/sh

#####
# サーバ名取得
Host=`hostname -s`

# 本番環境Oracleサーバか開発環境Oracleサーバのどちらで実行しているか判定する
# 本番環境Oracleサーバ
if [ "${Host}" = "example-oracle-11g-active" ] || [ "${Host}" = "example-oracle-11g-standby" ] ; then

    Disk_Name="/oracle_example_production"
    SidName="testsid1"      # ORACLE_SIDを指定する

    MailAddress="hogehoge-production@example.com" # ログローテーション結果メールの通知先メールアドレスを指定する

    MailSubjectText="[$Host] [production] Oracleアラートログとリスナーログローテーション結果"

# 開発環境Oracleサーバ
else

    Disk_Name="/oracle_example_staging"
    SidName="testsid2"      # ORACLE_SIDを指定する

    MailAddress="hogehoge-staging@example.com"    # ログローテーション結果メールの通知先メールアドレスを指定する

    MailSubjectText="[$Host] [staging] Oracleアラートログとリスナーログローテーション結果"

fi

#####
# スクリプトの2重起動チェック
procname="oracle_alert_log_rotate"
lock_fname="/tmp/${procname}.lock"

if [ -f "${lock_fname}" ] ; then

    echo "バッチ [$0 $@] が実行中です。"
    echo "バッチの多重起動を禁止している為、処理を実行せずに終了します。"

    echo "バッチを強制的に実行したい場合、既存のバッチ [$0] を停止して、以下のロックファイルを削除して下さい。"
    echo "${lock_fname}"
    ls -lrta ${lock_fname}
    exit 1

fi

echo "$$ $0 $@" > ${lock_fname}

##### 待機系Oracleサーバではスクリプトを実行させないチェック処理
# ${Disk_Name}で指定したディレクトリがマウントされていなければ、待機系サーバと判断してシェルを実行しないこととする。
Mount_Chk=`df -Pk | grep -v grep | grep "${Disk_Name}" | wc -l`

if [ "${Mount_Chk}" -lt "1" ] ; then

    # ロックファイル削除
    rm -f ${lock_fname}

    exit 0

fi

#####
# Oracle11gリスナーログ(XML形式とテキスト形式両方)、アラートログのログローテーションを実行する

#####
# ログローテーション対象のOracleリスナーログを記述する
LogNameList="\
    ${Disk_Name}/opt/oracle/app/oracle/diag/tnslsnr/${Host}/listener/alert/log.xml \
    ${Disk_Name}/opt/oracle/app/oracle/diag/tnslsnr/${Host}/listener/trace/listener.log \
    ${Disk_Name}/opt/oracle/app/oracle/diag/rdbms/${SidName}/${SidName}/alert/log.xml \
    ${Disk_Name}/opt/oracle/app/oracle/diag/rdbms/${SidName}/${SidName}/trace/alert_${SidName}.log \
"

#####
# メール件名を日本語表記とする為、nkfで文字コード変換を実行
Subject=`echo ${MailSubjectText} | nkf -j`
echo "${MailSubjectText}" > /tmp/${procname}
echo "" >> /tmp/${procname}

#####
date_str=`date "+%Y%m%d"`
LogCount=0

# ログローテーション実行
for LogName in ${LogNameList}
do

    LogCount=`expr ${LogCount} + 1`
    echo "対象ログファイル名:${LogName}" >> /tmp/${procname}

    if [ -f "${LogName}" ] ; then

        # ログファイル名をリネーム
        mv ${LogName} ${LogName}.${date_str}

        # リネームしたログファイルを圧縮
        gzip ${LogName}.${date_str}

        if [ -f "${LogName}.${date_str}.gz" ] ; then

            echo "ログファイル圧縮 成功" >> /tmp/${procname}
            echo "  ログファイル名: ${LogName}.${date_str}.gz"  >> /tmp/${procname}

        else

            echo "ログファイル圧縮 失敗!!"     >> /tmp/${procname}
            echo "  ログファイル名: ${LogName}.${date_str}"     >> /tmp/${procname}

        fi

    else

        echo "以下のログファイルはありません" >> /tmp/${procname}
        echo "  ログファイル名:${LogName}"    >> /tmp/${procname}

    fi

    echo "" >> /tmp/${procname}

done

##### ログローテーションして一定時間が経過した古いログファイルを削除する
if [ -d "${Disk_Name}/opt/oracle/app/oracle/diag/rdbms/${SidName}/${SidName}/trace" ] ; then
    find ${Disk_Name}/opt/oracle/app/oracle/diag/rdbms/${SidName}/${SidName}/trace -name "${SidName}_*.trm" -mtime +0 -print | xargs rm -f
    find ${Disk_Name}/opt/oracle/app/oracle/diag/rdbms/${SidName}/${SidName}/trace -name "${SidName}_*.trc" -mtime +0 -print | xargs rm -f
    find ${Disk_Name}/opt/oracle/app/oracle/diag/rdbms/${SidName}/${SidName}/trace -name "cdmp_*" -mtime +7 -print | xargs rm -f -r
    echo "${Disk_Name}/opt/oracle/app/oracle/diag/rdbms/${SidName}/${SidName}/trace 配下の古いログファイルを削除しました。" >> /tmp/${procname}
else
    echo "${Disk_Name}/opt/oracle/app/oracle/diag/rdbms/${SidName}/${SidName}/trace ディレクトリは存在しません。" >> /tmp/${procname}
fi

if [ -d "${Disk_Name}/opt/oracle/app/oracle/diag/tnslsnr/${Host}/listener/alert" ] ; then
    find ${Disk_Name}/opt/oracle/app/oracle/diag/tnslsnr/${Host}/listener/alert -name "log*.xml*.gz" -mtime +14 -print | xargs rm -f
    echo "${Disk_Name}/opt/oracle/app/oracle/diag/tnslsnr/${Host}/listener/alert 配下の古いログファイルを削除しました。" >> /tmp/${procname}
else
    echo "${Disk_Name}/opt/oracle/app/oracle/diag/tnslsnr/${Host}/listener/alert ディレクトリは存在しません。" >> /tmp/${procname}
fi

if [ -d "${Disk_Name}/opt/oracle/app/oracle/diag/tnslsnr/${Host}/listener/trace" ] ; then
    find ${Disk_Name}/opt/oracle/app/oracle/diag/tnslsnr/${Host}/listener/trace -name "listener*.gz" -mtime +14 -print | xargs rm -f
    echo "${Disk_Name}/opt/oracle/app/oracle/diag/tnslsnr/${Host}/listener/trace 配下の古いログファイルを削除しました。" >> /tmp/${procname}
else
    echo "${Disk_Name}/opt/oracle/app/oracle/diag/tnslsnr/${Host}/listener/trace ディレクトリは存在しません。" >> /tmp/${procname}
fi

if [ -d "${Disk_Name}/opt/oracle/app/oracle/diag/rdbms/${SidName}/${SidName}/alert" ] ; then
    find ${Disk_Name}/opt/oracle/app/oracle/diag/rdbms/${SidName}/${SidName}/alert -name "log*.xml*.gz" -mtime +14 -print | xargs rm -f
    echo "${Disk_Name}/opt/oracle/app/oracle/diag/rdbms/${SidName}/${SidName}/alert 配下の古いログファイルを削除しました。" >> /tmp/${procname}
else
    echo "${Disk_Name}/opt/oracle/app/oracle/diag/rdbms/${SidName}/${SidName}/alert ディレクトリは存在しません。" >> /tmp/${procname}
fi

if [ -d "${Disk_Name}/opt/oracle/app/oracle/diag/rdbms/${SidName}/${SidName}/trace" ] ; then
    find ${Disk_Name}/opt/oracle/app/oracle/diag/rdbms/${SidName}/${SidName}/trace -name "alert_${SidName}*.gz" -mtime +14 -print | xargs rm -f
    find ${Disk_Name}/opt/oracle/app/oracle/diag/rdbms/${SidName}/${SidName}/trace -name "${SidName}_*.trc*" -mtime +1 -print | xargs rm -f
    find ${Disk_Name}/opt/oracle/app/oracle/diag/rdbms/${SidName}/${SidName}/trace -name "${SidName}_*.trm*" -mtime +1 -print | xargs rm -f
    echo "${Disk_Name}/opt/oracle/app/oracle/diag/rdbms/${SidName}/${SidName}/trace 配下の古いログファイルを削除しました。" >> /tmp/${procname}
else
    echo "${Disk_Name}/opt/oracle/app/oracle/diag/rdbms/${SidName}/${SidName}/trace ディレクトリは存在しません。" >> /tmp/${procname}
fi

# 古いインシデントトレースログファイルを削除
if [ -d "${Disk_Name}/opt/oracle/app/oracle/diag/rdbms/${SidName}/${SidName}/incident" ] ; then
    find ${Disk_Name}/opt/oracle/app/oracle/diag/rdbms/${SidName}/${SidName}/incident -name "incdir_*" -mtime +7 -print | xargs rm -f -r
    echo "${Disk_Name}/opt/oracle/app/oracle/diag/rdbms/${SidName}/${SidName}/incident 配下の古いログファイルを削除しました。" >> /tmp/${procname}
else
    echo "${Disk_Name}/opt/oracle/app/oracle/diag/rdbms/${SidName}/${SidName}/incident ディレクトリは存在しません。" >> /tmp/${procname}
fi

#####
# ログローテーション結果の通知メール送信
cat /tmp/${procname} | nkf -j > /tmp/${procname}.sjis
mail -s "${Subject}" ${MailAddress} < /tmp/${procname}.sjis
rm -f /tmp/${procname} /tmp/${procname}.sjis

#####
# ロックファイル削除
rm -f ${lock_fname}
