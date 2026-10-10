# 03 · 清洗与派生数据

本目录存放各环节代码的**直接输入/输出**，全部为客户级或组级汇总数据（小文件，随仓库分发）。
交易级明细（> 50 MB）未随仓库分发，可用 SQL 从原始 xlsx 一键再生。

## 文件清单与血缘

| 文件 | 行数 | 产出方 | 被谁使用 | 说明 |
|------|-----:|--------|----------|------|
| `online_retail_ii_clean_history_rfm.csv` | 5,023 | SQL 01 | Notebook、04/05 脚本 | 客户级 RFM：R/F/M 原值 + R/F/M 得分 + FM + 10 组标签 |
| `online_retail_ii_clean_history_rfm_statistics.csv` | 10 | SQL 01 | — | 规则RFM 各组历史画像。⚠️ **无表头**，读取用 `header=None` |
| `online_retail_ii_customer_future_metrics.csv` | 5,023 | SQL 02 | Notebook、04/05 脚本 | 客户级未来指标：FutureFrequency / FutureMonetary / Repurchased |
| `online_retail_ii_customer_monthly_metrics.csv` | 25,115（=5,023×5 个月） | SQL 02 | Notebook | 客户 × 月度订单数与净消费 |
| `online_retail_ii_rfm_holdout_statistics.csv` | 10 | SQL 02 | — | 规则RFM 各组未来表现（复购率、未来净M占比等） |

### 未随仓库分发的交易级明细（SQL 再生）

| 文件 | 行数 | 大小 | 再生方式 |
|------|-----:|------|----------|
| `online_retail_ii_clean.csv` | 797,885 | 86 MB | 执行 `02_SQL脚本/01_历史窗口_加载与清洗.sql` 后导出 `online_retail_ii_clean_history ∪ online_retail_ii_clean_holdout` |
| `online_retail_ii_clean_holdout.csv` | 209,319 | 23 MB | 同上（未来窗口表） |

两者是原始 xlsx 的确定性派生物：Python 分析链路（Notebook 与 04/05 脚本）**不依赖**这两个文件，因此克隆仓库后无需再生即可运行全部 Python 复现。

## ⚠️ 读取注意事项

1. **`Customer ID` 在 CSV 中为浮点样式**（如 `17592.0`）。所有脚本统一以 `dtype={'Customer ID': str}` 读取，两表同为字符串后才能正确对齐合并。请勿用 Excel 打开后另存，否则格式可能被改写导致合并失败。
2. **`online_retail_ii_clean_history_rfm_statistics.csv` 无表头**，单独读取时请使用 `pd.read_csv(..., header=None)`；其余客户级 CSV 均有表头。
3. 全部文件编码为 `utf-8-sig`（带 BOM），读取时指定 `encoding='utf-8-sig'` 可避免首列名带 BOM 前缀。

## 字段口径速查

| 字段 | 口径 |
|------|------|
| `Recency` | 最近一次**非取消**发票的日期（yyyy-mm-dd） |
| `Frequency` | 历史/未来窗口内非取消发票去重数 |
| `Monetary` | `sum(Quantity × Price)`，**含取消发票负金额**（净额口径），单位 GBP |
| `R_score` | R 的 `percent_rank` 五等分（1 最久未买 ～ 5 最近购买） |
| `F_score` | 固定频次分档：1→1，2→2，3–4→3，5–8→4，≥9→5 |
| `M_score` | M 的 `percent_rank` 五等分 |
| `FM_score` | `FLOOR((F_score + M_score) / 2)` |
| `Customer_group` | 按 Shopify 官方 R × FM 映射的 10 组实际非空群组 |
| `Repurchased` | 未来窗口内发生非取消购买 = 1，否则 0 |
