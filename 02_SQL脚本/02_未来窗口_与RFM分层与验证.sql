SELECT
    `Customer ID`,
    COUNT(
        DISTINCT CASE
            WHEN UPPER(TRIM(`Invoice`)) NOT LIKE 'C%'
            THEN `Invoice`
        END
    ) AS FutureFrequency,
    SUM(`Quantity` * `Price`) AS FutureMonetary
FROM online_retail_ii_clean_holdout
GROUP BY `Customer ID`;

# 未来数据
# 以历史客户表为主表,关联未来指标，保留未来没有交易的用户
with future_metrics as (SELECT `Customer ID`,
                               COUNT(
                                       DISTINCT CASE
                                                    WHEN UPPER(TRIM(`Invoice`)) NOT LIKE 'C%'
                                                        THEN `Invoice`
                                   END
                               )                         AS FutureFrequency,
                               SUM(`Quantity` * `Price`) AS FutureMonetary
                        FROM online_retail_ii_clean_holdout
                        GROUP BY `Customer ID`),
validation as (
    select h.*,coalesce(f.FutureFrequency,0) as FutureFrequency,
           coalesce(f.FutureMonetary,0) as FutureMonetary,
           case when coalesce(f.FutureFrequency,0) > 0 then 1
            else 0 end as Repurchased
        from online_retail_ii_clean_history_rfm as h
           left join future_metrics as f
           on h.`Customer ID` = f.`Customer ID`
    )
# select * from validation;
# 汇总用户数、订单数、未来消费金额数
/*
select count(*) Customers,
       sum(FutureFrequency) as Orders,
       sum(FutureMonetary) as NetMonetary
from future_metrics;
  */
# 汇总用户数、行数、复购人数、复购率
/*
select count(*) as RowsCount,
       count(distinct `Customer ID`) as Customers,
       sum(Repurchased) as RepurchasedCustomers,
       avg(Repurchased) as RepurchaseRate
from validation;
*/
# 统计 各人群 复购人数 复购率  平均购买频次，平均消费金额，总消费金额
select
    Customer_group,
    Count(*) as Customers,
    Sum(Repurchased) as RepurchasedCustomers,
    avg(Repurchased) as RepurchaseRate,
    avg(FutureFrequency) as AvgFutureOrders,
    avg(FutureMonetary) as AvgFutureNetMonetary,
    sum(FutureMonetary) as TotalFutureNetMonetary
    from validation
    group by Customer_group
    order by AvgFutureNetMonetary DESC;

# 补充分析一下各人群月度表现
with months as (
    select '2011-07' as month
    union all select '2011-08'
    union all select '2011-09'
    union all select '2011-10'
    union all select '2011-11'
),
monthly_metrics as (
    select
        `Customer ID`,
        Date_format(InvoiceDate_date,'%Y-%m') as month,
        count(distinct case
                    when upper(trim(Invoice))not like 'C%'
                    then   Invoice end ) as MonthlyOrders,
        sum(quantity * price) as MonthlyNetMonetary
    from online_retail_ii_clean_holdout
        group by `Customer ID`,
            date_format(InvoiceDate_date,'%Y-%m')
),
    monthly_validation as (
        select
            h.`Customer ID`,
            h.Customer_group,
            m.Month,
            COALESCE(f.MonthlyOrders, 0) AS MonthlyOrders,
        COALESCE(f.MonthlyNetMonetary, 0) AS MonthlyNetMonetary,

        CASE
            WHEN COALESCE(f.MonthlyOrders, 0) > 0 THEN 1
            ELSE 0
        END AS PurchasedThisMonth
        from online_retail_ii_clean_history_rfm as h
        cross join months as m
        left join monthly_metrics as f
         on h.`Customer ID` = f.`Customer ID`
        and m.Month = f.Month
    )
SELECT
    Month,
    Customer_group,
    count(*) as Customers,
    SUM(PurchasedThisMonth) AS PurchasingCustomers,
    AVG(PurchasedThisMonth) AS MonthlyPurchaseRate,
    AVG(MonthlyOrders) AS AvgMonthlyOrders,
    AVG(MonthlyNetMonetary) AS AvgMonthlyNetMonetary,
    SUM(MonthlyNetMonetary) AS TotalMonthlyNetMonetary
    from monthly_validation
group by Month,Customer_group
order by Month,AvgMonthlyNetMonetary DESC;

# 定位 Previously loyal用户 负金额

SELECT
    h.`Customer ID`,

    SUM(
        CASE
            WHEN UPPER(TRIM(f.Invoice)) NOT LIKE 'C%'
            THEN f.Quantity * f.Price
            ELSE 0
        END
    ) AS NormalInvoiceAmount,

    SUM(
        CASE
            WHEN UPPER(TRIM(f.Invoice)) LIKE 'C%'
            THEN f.Quantity * f.Price
            ELSE 0
        END
    ) AS CancellationInvoiceNetAmount,

    COALESCE(SUM(f.Quantity * f.Price), 0)
        AS FutureNetMonetary

FROM online_retail_ii_clean_history_rfm AS h

LEFT JOIN online_retail_ii_clean_holdout AS f
    ON h.`Customer ID` = f.`Customer ID`

WHERE h.Customer_group = 'Previously loyal曾经忠诚客户'

GROUP BY h.`Customer ID`
ORDER BY FutureNetMonetary;

# 建表 基于历史数据的规则型RFM用户分层人群未来表现

CREATE TABLE online_retail_ii_rfm_holdout_statistics AS
WITH future_metrics AS (
    SELECT
        `Customer ID`,

        COUNT(
            DISTINCT CASE
                WHEN UPPER(TRIM(`Invoice`)) NOT LIKE 'C%'
                THEN `Invoice`
            END
        ) AS FutureFrequency,

        SUM(`Quantity` * `Price`) AS FutureMonetary

    FROM online_retail_ii_clean_holdout
    GROUP BY `Customer ID`
),
validation AS (
    SELECT
        h.`Customer ID`,
        h.Customer_group,

        COALESCE(f.FutureFrequency, 0) AS FutureFrequency,
        COALESCE(f.FutureMonetary, 0) AS FutureMonetary,

        CASE
            WHEN COALESCE(f.FutureFrequency, 0) > 0 THEN 1
            ELSE 0
        END AS Repurchased

    FROM online_retail_ii_clean_history_rfm AS h

    LEFT JOIN future_metrics AS f
        ON h.`Customer ID` = f.`Customer ID`
),
totals AS (
    SELECT
        COUNT(*) AS TotalCustomers,
        SUM(FutureFrequency) AS TotalOrders,
        SUM(FutureMonetary) AS TotalNetMonetary
    FROM validation
),
group_statistics AS (
    SELECT
        Customer_group,
        COUNT(*) AS Customers,
        SUM(Repurchased) AS RepurchasedCustomers,
        AVG(Repurchased) AS RepurchaseRate,
        SUM(FutureFrequency) AS TotalFutureOrders,
        AVG(FutureFrequency) AS AvgFutureOrders,
        SUM(FutureMonetary) AS TotalFutureNetMonetary,
        AVG(FutureMonetary) AS AvgFutureNetMonetary
    FROM validation
    GROUP BY Customer_group
)
SELECT
    g.Customer_group,

    g.Customers,
    g.Customers / NULLIF(t.TotalCustomers, 0)
        AS CustomerShare,

    g.RepurchasedCustomers,
    g.RepurchaseRate,

    g.TotalFutureOrders,
    g.AvgFutureOrders,
    g.TotalFutureOrders / NULLIF(t.TotalOrders, 0)
        AS FutureOrderShare,

    g.TotalFutureNetMonetary,
    g.AvgFutureNetMonetary,
    g.TotalFutureNetMonetary / NULLIF(t.TotalNetMonetary, 0)
        AS FutureNetMonetaryShare

FROM group_statistics AS g
CROSS JOIN totals AS t;

select * from online_retail_ii_rfm_holdout_statistics;

/*
| 字段 | 含义 |
|---|---|
| `Customers` | 该历史人群客户数 |
| `CustomerShare` | 该人群占5,023位历史客户的比例 |
| `RepurchasedCustomers` | 未来发生正常购买的客户数 |
| `RepurchaseRate` | 复购人数÷该人群客户数 |
| `TotalFutureOrders` | 未来正常购买订单总数 |
| `AvgFutureOrders` | 人均未来订单数，包含未购买客户 |
| `FutureOrderShare` | 该人群未来订单数占历史客户未来订单总数的比例 |
| `TotalFutureNetMonetary` | 未来净消费总额 |
| `AvgFutureNetMonetary` | 人均未来净消费，包含未购买客户 |
| `FutureNetMonetaryShare` | 该人群未来净消费占全部历史客户未来净消费的比例 |
*/

# 用户未来数据用于K-means聚类分析
CREATE TABLE online_retail_ii_customer_future_metrics AS
WITH future_metrics AS (
    SELECT
        `Customer ID`,

        COUNT(
            DISTINCT CASE
                WHEN UPPER(TRIM(`Invoice`)) NOT LIKE 'C%'
                THEN `Invoice`
            END
        ) AS FutureFrequency,

        SUM(`Quantity` * `Price`) AS FutureMonetary

    FROM online_retail_ii_clean_holdout
    GROUP BY `Customer ID`
)
SELECT
    h.`Customer ID`,

    COALESCE(f.FutureFrequency, 0) AS FutureFrequency,

    COALESCE(f.FutureMonetary, 0) AS FutureMonetary,

    CASE
        WHEN COALESCE(f.FutureFrequency, 0) > 0 THEN 1
        ELSE 0
    END AS Repurchased

FROM online_retail_ii_clean_history_rfm AS h

LEFT JOIN future_metrics AS f
    ON h.`Customer ID` = f.`Customer ID`;

# 检验数据是否有误
SELECT
    COUNT(*) AS Customers,
    COUNT(DISTINCT `Customer ID`) AS UniqueCustomers,
    SUM(FutureFrequency) AS Orders,
    SUM(FutureMonetary) AS NetMonetary,
    SUM(Repurchased) AS RepurchasedCustomers
FROM online_retail_ii_customer_future_metrics;


WITH months AS (
    SELECT '2011-07' AS Month
    UNION ALL SELECT '2011-08'
    UNION ALL SELECT '2011-09'
    UNION ALL SELECT '2011-10'
    UNION ALL SELECT '2011-11'
),
monthly_metrics AS (
    SELECT
        `Customer ID`,
        DATE_FORMAT(InvoiceDate_date, '%Y-%m') AS Month,

        COUNT(
            DISTINCT CASE
                WHEN UPPER(TRIM(`Invoice`)) NOT LIKE 'C%'
                THEN `Invoice`
            END
        ) AS MonthlyOrders,

        SUM(Quantity * Price) AS MonthlyNetMonetary

    FROM online_retail_ii_clean_holdout
    GROUP BY
        `Customer ID`,
        DATE_FORMAT(InvoiceDate_date, '%Y-%m')
)
SELECT
    h.`Customer ID`,
    m.Month,
    COALESCE(f.MonthlyOrders, 0) AS MonthlyOrders,
    COALESCE(f.MonthlyNetMonetary, 0) AS MonthlyNetMonetary

FROM online_retail_ii_clean_history_rfm AS h

CROSS JOIN months AS m

LEFT JOIN monthly_metrics AS f
    ON h.`Customer ID` = f.`Customer ID`
    AND m.Month = f.Month

ORDER BY h.`Customer ID`, m.Month;