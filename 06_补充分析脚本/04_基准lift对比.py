# -*- coding: utf-8 -*-
"""
04 · 基准 lift 对比（最小化复算核心结论）

输入：03_清洗与派生数据/online_retail_ii_clean_history_rfm.csv
      03_清洗与派生数据/online_retail_ii_customer_future_metrics.csv

目的：检验「规则型 RFM 分层」「K-means 分簇」相对「直接按历史 Monetary 排序」
      是否真的能更好地识别未来高价值客户。

路径说明：全部基于本文件位置推导，可在任意工作目录下运行。
"""
from pathlib import Path

import numpy as np
import pandas as pd
from scipy import stats
from sklearn.cluster import KMeans
from sklearn.metrics import adjusted_rand_score, silhouette_score
from sklearn.preprocessing import StandardScaler

ROOT = Path(__file__).resolve().parent.parent
D = ROOT / "03_清洗与派生数据"

pd.set_option("display.width", 220)
pd.set_option("display.unicode.east_asian_width", True)


def main() -> None:
    rfm = pd.read_csv(D / "online_retail_ii_clean_history_rfm.csv",
                      encoding="utf-8-sig", dtype={"Customer ID": str})
    fut = pd.read_csv(D / "online_retail_ii_customer_future_metrics.csv",
                      encoding="utf-8-sig", dtype={"Customer ID": str})
    df = rfm.merge(fut, on="Customer ID", how="left", validate="one_to_one")

    # 1. 复现 K-means（与 Notebook 口径一致）
    df["R_days"] = (pd.Timestamp("2011-07-01") - pd.to_datetime(df["Recency"])).dt.days
    feat = df[["R_days", "Frequency", "Monetary"]].copy()
    ft = feat.copy()
    ft["Frequency"] = np.log1p(ft["Frequency"])
    ft["Monetary"] = np.log1p(ft["Monetary"])
    X = StandardScaler().fit_transform(ft)
    km = KMeans(n_clusters=6, random_state=42, n_init=20).fit(X)
    df["Cluster"] = km.labels_
    print("[复现] 轮廓系数 = %.4f" % silhouette_score(X, km.labels_))
    ari = [adjusted_rand_score(km.labels_,
           KMeans(n_clusters=6, random_state=s, n_init=20).fit(X).labels_) for s in [0, 10, 100, 2026]]
    print("[复现] 跨 seed ARI =", ["%.4f" % a for a in ari])

    tot = df["FutureMonetary"].sum()
    print("\n未来净消费总额 = %.0f | 客户数 = %d" % (tot, len(df)))

    # 2. 公平 lift 对比：同一选择人数
    order_g = ["Champions核心高价值客户", "Loyal忠诚客户", "Active活跃客户", "New新客户",
               "Needs attention待关注客户", "Promising潜力客户", "At risk流失风险客户",
               "Almost lost临近流失客户", "Dormant休眠客户", "Previously loyal曾经忠诚客户"]
    df["rfm_rank"] = df["Customer_group"].apply(lambda x: order_g.index(x))
    cluster_order = list(df.groupby("Cluster")["FutureMonetary"].mean().sort_values(ascending=False).index)
    df["clus_rank"] = df["Cluster"].apply(lambda x: cluster_order.index(x))
    df["rfm_key"] = df["rfm_rank"] * 1e9 - df["Monetary"]
    df["clus_key"] = df["clus_rank"] * 1e9 - df["Monetary"]

    print("\n================ 公平 lift 对比（同一选择人数） ================")
    print("选择人数 |  比例  | 基准(历史M) | 规则RFM | K-means | 满分(未来M)")
    for pct in [0.05, 0.10, 0.123, 0.20, 0.279, 0.30, 0.50]:
        n = int(round(len(df) * pct))
        base = df.nlargest(n, "Monetary")["FutureMonetary"].sum() / tot
        r = df.nsmallest(n, "rfm_key")["FutureMonetary"].sum() / tot
        c = df.nsmallest(n, "clus_key")["FutureMonetary"].sum() / tot
        orc = min(df.nlargest(n, "FutureMonetary")["FutureMonetary"].sum() / tot, 1.0)
        print("  %5d  | %5.1f%% |   %.3f     |  %.3f  |  %.3f  |  %.3f" % (n, pct * 100, base, r, c, orc))

    # 3. 组标签对未来价值的解释力 η²
    def eta_sq(values, labels):
        values = np.asarray(values, float); labels = np.asarray(labels); grand = values.mean()
        ssb = sum(len(values[labels == g]) * (values[labels == g].mean() - grand) ** 2
                  for g in np.unique(labels))
        return ssb / ((values - grand) ** 2).sum()

    v = np.log1p(df["FutureMonetary"].clip(lower=0))
    print("\n================ 组标签对未来 log(1+M) 的解释力 η² ================")
    print("规则RFM(10组):   %.3f" % eta_sq(v, df["Customer_group"]))
    print("K-means(6簇):    %.3f" % eta_sq(v, df["Cluster"]))
    print("单一历史M(连续):  %.3f" % (stats.spearmanr(df["Monetary"], v).statistic ** 2))
    print("单一历史F(连续):  %.3f" % (stats.spearmanr(df["Frequency"], v).statistic ** 2))

    # 4. 显著性检验
    print("\n================ 统计检验 ================")
    g1 = [d["FutureMonetary"].values for _, d in df.groupby("Customer_group")]
    g2 = [d["FutureMonetary"].values for _, d in df.groupby("Cluster")]
    print("Kruskal-Wallis 规则RFM: H=%.1f, p=%.3g" % stats.kruskal(*g1))
    print("Kruskal-Wallis K-means: H=%.1f, p=%.3g" % stats.kruskal(*g2))
    c0 = df[(df["Customer_group"] == "Champions核心高价值客户") & (df["Cluster"] == cluster_order[0])]["FutureMonetary"]
    c3 = df[(df["Customer_group"] == "Champions核心高价值客户") & (df["Cluster"] == cluster_order[1])]["FutureMonetary"]
    print("Champions内部 高价值簇(n=%d) vs 次高簇(n=%d): Mann-Whitney p=%.4g | 人均未来M %.0f vs %.0f"
          % (len(c0), len(c3), stats.mannwhitneyu(c0, c3).pvalue, c0.mean(), c3.mean()))


if __name__ == "__main__":
    main()
