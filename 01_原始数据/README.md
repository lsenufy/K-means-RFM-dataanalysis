# 01 · 原始数据

## 数据集：UCI Online Retail II

| 项目 | 说明 |
|------|------|
| 来源 | [UCI Machine Learning Repository — Online Retail II](https://archive.ics.uci.edu/dataset/502/online+retail+ii) |
| 许可 | CC BY 4.0 |
| 规模 | 1,067,371 条交易记录，两个年度工作表（2009-12-01～2010-12-09、2010-12-01～2011-12-09） |
| 本仓库文件 | `online_retail_II.xlsx`（约 44 MB，未做任何修改） |

## 字段说明

| 字段 | 类型 | 含义 |
|------|------|------|
| `Invoice` | 文本 | 发票号，6 位数字；以 `C` 开头表示取消（退货）发票 |
| `StockCode` | 文本 | 商品编码 |
| `Description` | 文本 | 商品名称 |
| `Quantity` | 整数 | 数量，取消发票为负 |
| `InvoiceDate` | 文本 | 交易时间 `YYYY-MM-DD HH:MM:SS` |
| `Price` | 数值 | 单价（GBP） |
| `Customer ID` | 文本 | 客户编号，存在少量缺失 |
| `Country` | 文本 | 国家 |

## 项目时间口径

- **历史窗口**：2009-12-01 ～ 2011-06-30（19 个月，用于分层建模）
- **未来窗口**：2011-07-01 ～ 2011-11-30（5 个月，仅用于回测验证）

## 引用格式

> Chen, S., Sain, S. L., & Guo, K. (2012). Data mining for the online retail industry: A case study of RFM model-based customer segmentation using data mining. *Journal of Database Marketing & Customer Strategy Management*, 19(3), 197–208.

若本文件缺失，可从上方 UCI 官方链接重新下载（文件名一致）。
