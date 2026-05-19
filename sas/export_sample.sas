/* ========================================================== */
/* サンプル: 月次売上データを JSON で出力                      */
/*                                                            */
/* PROC JSON で出力するときは、meta ブロックを必ず含める。     */
/* この meta が SAS 側と Web 側の「契約」になる。              */
/* ========================================================== */

/* 1. データ準備（実運用ではここを既存ロジックに差し替え） */
data work.sales_monthly;
    length category $20;
    do category = "食品", "日用品", "家電", "衣料";
        do month = 1 to 12;
            yyyymm = put(year(today())*100 + month, 6.);
            amount = round(ranuni(0)*1000000 + 500000, 1000);
            output;
        end;
    end;
run;

/* 2. メタ情報を含めて JSON 出力 */
filename outjson "C:\dashboard\data\sales_monthly.json" encoding="utf-8";

proc json out=outjson pretty nosastags;
    write open object;

    /* メタブロック（契約として必須） */
    write values "meta";
    write open object;
    write values "report_name" "月次売上";
    write values "generated_at" "%sysfunc(datetime(), E8601DT.)";
    write values "row_count";
    write values 48;
    write close;

    /* データ本体 */
    write values "data";
    export work.sales_monthly;

    write close;
run;

filename outjson clear;
