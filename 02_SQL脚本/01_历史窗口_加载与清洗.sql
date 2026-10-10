use uci_new;

# drop table online_retail_ii;

# 查看数据内容
select * from online_retail_ii;
# 查看字段名与类型
describe online_retail_ii;
# 转换字符类型
ALTER TABLE  online_retail_ii modify `Invoice` varchar(20);
ALTER TABLE online_retail_ii modify `StockCode` varchar(20);
ALter table online_retail_ii modify `Description` text;
Alter table online_retail_ii modify `Price`  decimal(12,4);
alter table online_retail_ii modify `Customer ID` varchar(20) null;
alter table online_retail_ii modify `Country` varchar(50);

ALter table online_retail_ii
    add column `InvoiceDate_date` Date,
    add column `InvoiceDate_time` Time;

# 两种切分 时间型数据的形式

UPDATE online_retail_ii
SET `InvoiceDate_date` = SUBSTRING(`InvoiceDate`, 1, 10),
    `InvoiceDate_time` = SUBSTRING(`InvoiceDate`, 12, 8);

# 查找数据空值
select count(*) from online_retail_ii where `Customer ID` is null;

# 去重后行数
select count(*) from (
select distinct * from online_retail_ii) a;

# 找取消发票（C%）的数据异常
select Invoice,quantity from online_retail_ii where Invoice like 'C%';
SELECT
  SUM(UPPER(TRIM(`Invoice`)) LIKE 'C%' AND `Quantity` >= 0)
    AS C发票但数量非负,
  SUM(UPPER(TRIM(`Invoice`)) NOT LIKE 'C%' AND `Quantity` < 0)
    AS 非C发票但数量为负
FROM online_retail_ii;
# 发现有一个取消的发票数量为正，找出来观察数据
SELECT * from online_retail_ii where Invoice like 'C%' and Quantity >=0;

# 开始数据清洗

# 1.去重
with t1 as (
select distinct * from online_retail_ii
                  ),

# 2.去空值
t2 as (
    select * from t1 where
                         `Customer ID` is not null and TRIM(`Customer ID`) != ''
                    and `InvoiceDate` is not null and TRIM(`InvoiceDate`) != ''
                     and `Invoice` is not null and TRIM(`Invoice`) != ''
                     and `Quantity` is not null and TRIM(`Quantity`) != ''
                     and `Price` is not null and TRIM(`Price`) != ''
),
# 3.检查业务规则：筛选日期范围(2009-12-01到2011-06-30)、Price >= 0 以及非 C 发票但 Quantity >= 0 以及C发票但Quantity <= 0
t3 as (
    select * from t2 where InvoiceDate_date between '2009-12-01' and '2011-06-30'
                     and `Price` >=0
                     and (
                         (`Invoice` NOT LIKE 'C%' and `Quantity` >= 0)
                            or
                         (`Invoice` like 'C%' and `Quantity` <=0))
)
select * from t3;


# 创建数据清洗后的表
CREATE TABLE online_retail_ii_clean_history LIKE online_retail_ii;
INSERT INTO online_retail_ii_clean_history
with t1 as (
select distinct * from online_retail_ii
                  ),
t2 as (
    select * from t1 where
                         `Customer ID` is not null and TRIM(`Customer ID`) != ''
                    and `InvoiceDate` is not null and TRIM(`InvoiceDate`) != ''
                     and `Invoice` is not null and TRIM(`Invoice`) != ''
                     and `Quantity` is not null and TRIM(`Quantity`) != ''
                     and `Price` is not null and TRIM(`Price`) != ''
),
t3 as (
    select * from t2 where InvoiceDate_date between '2009-12-01' and '2011-06-30'
                     and `Price` >=0
                     and (
                         (`Invoice` NOT LIKE 'C%' and `Quantity` >= 0)
                            or
                         (`Invoice` like 'C%' and `Quantity` <=0))
)
SELECT
   *
FROM t3;

CREATE TABLE online_retail_ii_clean_holdout LIKE online_retail_ii;
INSERT INTO online_retail_ii_clean_holdout
with t1 as (
select distinct * from online_retail_ii
                  ),
t2 as (
    select * from t1 where
                         `Customer ID` is not null and TRIM(`Customer ID`) != ''
                    and `InvoiceDate` is not null and TRIM(`InvoiceDate`) != ''
                     and `Invoice` is not null and TRIM(`Invoice`) != ''
                     and `Quantity` is not null and TRIM(`Quantity`) != ''
                     and `Price` is not null and TRIM(`Price`) != ''
),
t3 as (
    select * from t2 where InvoiceDate_date between '2011-07-01' and '2011-11-30'
                     and `Price` >=0
                     and (
                         (`Invoice` NOT LIKE 'C%' and `Quantity` >= 0)
                            or
                         (`Invoice` like 'C%' and `Quantity` <=0))
)
SELECT
   *
FROM t3;

#   计算独立用户数
select count(distinct `Customer ID`) from online_retail_ii_clean_holdout;
select count(distinct `Customer ID`) from online_retail_ii_clean_history;

describe online_retail_ii_clean_holdout;
describe online_retail_ii_clean_history;

# 对 历史数据 做数据工程
# 找到用户 最近一次下单的日期和时间（R）， 计数真实发票数（F），计算消费金额（M）
# 遇上的问题是 F 其实是和发票数有关而不是和用户ID行数有关  还有就是 时间序列必须完整包含年月日 当天时间，如果只用 拆分后的 max 来判断会导致 时间对应的日期不一致
select `Customer ID`,
       max( case when `Invoice` not like 'C%' then InvoiceDate_date end),
       max(case when `Invoice` not like 'C%' then InvoiceDate_time end) ,
       COUNT( DISTINCT  CASE WHEN `Invoice` not like 'C%' then `Invoice` end) Frequency,
       sum(Quantity*Price) Monetary
from online_retail_ii_clean_history group by `Customer ID`;

# 获得每个用户 最近一次下单时间，下单了几次（基于非取消发票数），消费金额（Quantity x Montary）
# 异常排查 通过datagrip自带的 排序功能 找到 Montary <0 或  Recency 为 null 的全部数据
# 找到异常数据后 通过 Monetary >= 0 去除三个异常值(样本量少影响不大)
with t1 as (
select `Customer ID`,
       max(case when `Invoice` not like 'C%' then timestamp(InvoiceDate_date,InvoiceDate_time) end ) Recency,
       COUNT( DISTINCT  CASE WHEN `Invoice` not like 'C%' then `Invoice` end) Frequency,
       sum(Quantity*Price) Monetary
from online_retail_ii_clean_history group by `Customer ID`  ),
t2 as (
    select * from t1 where Monetary>=0
    )
select * from t2;

# 最终决定 R 以日期为单位，这样会避免当日用户主要行为时间干扰真实用户质量
with t1 as (
select `Customer ID`,
       max(case when `Invoice` not like 'C%' then InvoiceDate_date end ) Recency,
       COUNT( DISTINCT  CASE WHEN `Invoice` not like 'C%' then `Invoice` end) Frequency,
       sum(Quantity*Price) Monetary
from online_retail_ii_clean_history group by `Customer ID`  ),
t2 as (
    select * from t1 where Monetary>=0
    )
select * from t2;

# 建立 RFM 原始表
drop table online_retail_ii_clean_history_RFM_origin;
create table online_retail_ii_clean_history_RFM_origin as
with t1 as (
select `Customer ID`,
       max(case when `Invoice` not like 'C%' then InvoiceDate_date end ) Recency,
       COUNT( DISTINCT  CASE WHEN `Invoice` not like 'C%' then `Invoice` end) Frequency,
       sum(Quantity*Price) Monetary
from online_retail_ii_clean_history group by `Customer ID`  ),
t2 as (
    select * from t1 where Monetary>=0
    )
select * from t2;

# 对RFM数据进行 评分
select  `Customer ID`,percent_rank() over (
    order by Recency asc
    ) recency_percent_rank,
    percent_rank() over (
        order by Frequency asc
        ) frequency_percent_rank,
    percent_rank() over (
        order by Monetary asc
        ) monetary_percent_rank,
    Recency,Frequency,Monetary
FROM online_retail_ii_clean_history_RFM_origin;

# 观察到 购买频次1-2次的用户占比极大，所以RFM模型 F目前暂时用频次分组
# 对各购买频次 用户数统计
select Frequency,
       count(*),
       count(*)/(select count(*) from online_retail_ii_clean_history_rfm_origin)
from online_retail_ii_clean_history_RFM_origin
group by Frequency
order by Frequency asc;

select *,
       CASE WHEN FREQUENCY =1 THEN 1
        WHEN Frequency = 2 THEN 2
        WHEN FREQUENCY BETWEEN 3 AND 4 THEN 3
        WHEN FREQUENCY BETWEEN 5 AND 8 THEN 4
        WHEN FREQUENCY >=9 THEN 5 END F_score
FROM online_retail_ii_clean_history_RFM_origin;

# R recency
select *,
       case when recency_percent_rank<0.2 then 1
       when recency_percent_rank<0.4 then 2
        when recency_percent_rank<0.6 then 3
        when recency_percent_rank<0.8 then 4
        else 5 end R_score
from (
select *,percent_rank() over (
        order by Recency asc
        ) recency_percent_rank
from online_retail_ii_clean_history_RFM_origin) t;

# M monetary
select *,
       case when monetary_percent_rank<0.2 then 1
       when monetary_percent_rank<0.4 then 2
        when monetary_percent_rank<0.6 then 3
        when monetary_percent_rank<0.8 then 4
        else 5 end M_score
from (
select *,percent_rank() over(
    order by Monetary asc
    ) monetary_percent_rank
from online_retail_ii_clean_history_RFM_origin ) t1;

# 汇总一下最后 RFM 得分 (最终获得的表)
select * ,
       case when recency_percent_rank<0.2 then 1
       when recency_percent_rank<0.4 then 2
        when recency_percent_rank<0.6 then 3
        when recency_percent_rank<0.8 then 4
        else 5 end R_score,
        CASE WHEN FREQUENCY =1 THEN 1
        WHEN Frequency = 2 THEN 2
        WHEN FREQUENCY BETWEEN 3 AND 4 THEN 3
        WHEN FREQUENCY BETWEEN 5 AND 8 THEN 4
        WHEN FREQUENCY >=9 THEN 5 END F_score,
        case when monetary_percent_rank<0.2 then 1
       when monetary_percent_rank<0.4 then 2
        when monetary_percent_rank<0.6 then 3
        when monetary_percent_rank<0.8 then 4
        else 5 end M_score
from (
select * ,
    percent_rank() over (
    order by Recency asc
    ) recency_percent_rank,
    percent_rank() over (
        order by Monetary asc
        ) monetary_percent_rank
from online_retail_ii_clean_history_rfm_origin ) t;

# 运用Shopify规定的RFM分层方式 （F+M）/2
with t1 as(
select * ,
    percent_rank() over (
    order by Recency asc
    ) recency_percent_rank,
    percent_rank() over (
        order by Monetary asc
        ) monetary_percent_rank
from online_retail_ii_clean_history_RFM_origin
),t2 as (
    select * ,
       case when recency_percent_rank<0.2 then 1
       when recency_percent_rank<0.4 then 2
        when recency_percent_rank<0.6 then 3
        when recency_percent_rank<0.8 then 4
        else 5 end R_score,
        CASE WHEN FREQUENCY =1 THEN 1
        WHEN Frequency = 2 THEN 2
        WHEN FREQUENCY BETWEEN 3 AND 4 THEN 3
        WHEN FREQUENCY BETWEEN 5 AND 8 THEN 4
        WHEN FREQUENCY >=9 THEN 5 END F_score,
        case when monetary_percent_rank<0.2 then 1
       when monetary_percent_rank<0.4 then 2
        when monetary_percent_rank<0.6 then 3
        when monetary_percent_rank<0.8 then 4
        else 5 end M_score
from t1
),t3 as (
    select `Customer ID`,
           Recency,
           Frequency,
           Monetary,
           recency_percent_rank,
           monetary_percent_rank,
           R_score,
           F_score,
           M_score,
           FLOOR((F_score+M_score)/2) FM_score
    from t2
)
select * from t3 ;

# 完成标签映射
with t1 as(
select * ,
    percent_rank() over (
    order by Recency asc
    ) recency_percent_rank,
    percent_rank() over (
        order by Monetary asc
        ) monetary_percent_rank
from online_retail_ii_clean_history_RFM_origin
),t2 as (
    select * ,
       case when recency_percent_rank<0.2 then 1
       when recency_percent_rank<0.4 then 2
        when recency_percent_rank<0.6 then 3
        when recency_percent_rank<0.8 then 4
        else 5 end R_score,
        CASE WHEN FREQUENCY =1 THEN 1
        WHEN Frequency = 2 THEN 2
        WHEN FREQUENCY BETWEEN 3 AND 4 THEN 3
        WHEN FREQUENCY BETWEEN 5 AND 8 THEN 4
        WHEN FREQUENCY >=9 THEN 5 END F_score,
        case when monetary_percent_rank<0.2 then 1
       when monetary_percent_rank<0.4 then 2
        when monetary_percent_rank<0.6 then 3
        when monetary_percent_rank<0.8 then 4
        else 5 end M_score
from t1
),t3 as (
    select `Customer ID`,
           Recency,
           Frequency,
           Monetary,
           recency_percent_rank,
           monetary_percent_rank,
           R_score,
           F_score,
           M_score,
           FLOOR((F_score+M_score)/2) FM_score
    from t2
),t4 as (
    select *,
           case when (R_score between 1 and 2) AND (FM_score BETWEEN 1 AND 2) then 'Dormant休眠客户'
            when (R_score between 1 and 2) and (FM_score BETWEEN 3 AND 4) then 'At risk流失风险客户'
            when (R_score between 1 and 2) and FM_score = 5 then 'Previously loyal曾经忠诚客户'
            when (R_score =3) and (FM_score between 1 and 2) then 'Almost lost临近流失客户'
            when (R_score =3) and (FM_score = 3) then 'Needs attention待关注客户'
            when (R_score between 3 and 4) and (FM_score between 4 and 5) then 'Loyal忠诚客户'
            when (R_score =4) and (FM_score= 1) then 'Promising潜力客户'
            when (R_score BETWEEN 4 and 5) and (FM_score between 2 and 3) then 'Active活跃客户'
            when (R_score = 5) and(FM_score =1) then 'New新客户'
            when (R_score = 5) and (FM_score between 4 and 5) then 'Champions核心高价值客户' end Customer_group
    from t3
)
select * from t4;

# 建立Shopify RFM用户分层表
DROP TABLE online_retail_ii_clean_history_rfm;
create table online_retail_ii_clean_history_rfm as
with t1 as(
select * ,
    percent_rank() over (
    order by Recency asc
    ) recency_percent_rank,
    percent_rank() over (
        order by Monetary asc
        ) monetary_percent_rank
from online_retail_ii_clean_history_rfm_origin
),t2 as (
    select * ,
       case when recency_percent_rank<0.2 then 1
       when recency_percent_rank<0.4 then 2
        when recency_percent_rank<0.6 then 3
        when recency_percent_rank<0.8 then 4
        else 5 end R_score,
        CASE WHEN FREQUENCY =1 THEN 1
        WHEN Frequency = 2 THEN 2
        WHEN FREQUENCY BETWEEN 3 AND 4 THEN 3
        WHEN FREQUENCY BETWEEN 5 AND 8 THEN 4
        WHEN FREQUENCY >=9 THEN 5 END F_score,
        case when monetary_percent_rank<0.2 then 1
       when monetary_percent_rank<0.4 then 2
        when monetary_percent_rank<0.6 then 3
        when monetary_percent_rank<0.8 then 4
        else 5 end M_score
from t1
),t3 as (
    select `Customer ID`,
           Recency,
           Frequency,
           Monetary,
           recency_percent_rank,
           monetary_percent_rank,
           R_score,
           F_score,
           M_score,
           FLOOR((F_score+M_score)/2) FM_score
    from t2
),t4 as (
    select *,
           case when (R_score between 1 and 2) AND (FM_score BETWEEN 1 AND 2) then 'Dormant休眠客户'
            when (R_score between 1 and 2) and (FM_score BETWEEN 3 AND 4) then 'At risk流失风险客户'
            when (R_score between 1 and 2) and FM_score = 5 then 'Previously loyal曾经忠诚客户'
            when (R_score =3) and (FM_score between 1 and 2) then 'Almost lost临近流失客户'
            when (R_score =3) and (FM_score = 3) then 'Needs attention待关注客户'
            when (R_score between 3 and 4) and (FM_score between 4 and 5) then 'Loyal忠诚客户'
            when (R_score =4) and (FM_score= 1) then 'Promising潜力客户'
            when (R_score BETWEEN 4 and 5) and (FM_score between 2 and 3) then 'Active活跃客户'
            when (R_score = 5) and(FM_score =1) then 'New新客户'
            when (R_score = 5) and (FM_score between 4 and 5) then 'Champions核心高价值客户' end Customer_group
    from t3
)
select `Customer ID`,Recency,Frequency,Monetary,R_score,FM_score,F_score,M_score,Customer_group from t4;

# 检验独立用户数
select count(*) from online_retail_ii_clean_history_rfm_origin;
select count(*) from online_retail_ii_clean_history_rfm;
# 检验 recency 非空 Frequency > 0
select * from online_retail_ii_clean_history_rfm where recency is null or frequency <= 0;
# 检验购买日期范围
select max(recency),min(Recency) from online_retail_ii_clean_history_rfm;

# 计算各人群数据 ： 客户数、客户占比、人均M、M、M占比，购买订单总数、人均订单数、平均最近购买天数
select Customer_group,count(*) `客户数`,
       count(*)/(select count(*) from online_retail_ii_clean_history_rfm) `客户占比`,
       avg(Monetary) `人均M`,
        sum(Monetary) `M总额`,
        sum(Monetary)/(select sum(Monetary)from online_retail_ii_clean_history_rfm) `M占比`,
        sum(Frequency)  `购买订单总数`,
        avg(Frequency)  `人均购买次数`,
        avg(datediff('2011-07-01',Recency))  `平均最近购买天数`
from online_retail_ii_clean_history_rfm group by Customer_group;

# 创建统计学RFM新表
create table online_retail_ii_clean_history_rfm_statistics
as select Customer_group,count(*) `客户数`,
       count(*)/(select count(*) from online_retail_ii_clean_history_rfm) `客户占比`,
       avg(Monetary) `人均M`,
        sum(Monetary) `M总额`,
        sum(Monetary)/(select sum(Monetary)from online_retail_ii_clean_history_rfm) `M占比`,
        sum(Frequency)  `购买订单总数`,
        avg(Frequency)  `人均购买次数`,
        avg(datediff('2011-07-01',Recency))  `平均最近购买天数`
from online_retail_ii_clean_history_rfm group by Customer_group;
