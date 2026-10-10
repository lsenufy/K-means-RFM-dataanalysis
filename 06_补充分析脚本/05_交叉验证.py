from pathlib import Path
import pandas as pd
import numpy as np
from sklearn.cluster import KMeans
from sklearn.preprocessing import StandardScaler

ROOT=Path(__file__).resolve().parent.parent
D=ROOT/'03_清洗与派生数据'
rfm=pd.read_csv(D/'online_retail_ii_clean_history_rfm.csv',encoding='utf-8-sig',dtype={'Customer ID':str})
future=pd.read_csv(D/'online_retail_ii_customer_future_metrics.csv',encoding='utf-8-sig',dtype={'Customer ID':str})
df=rfm.merge(future,on='Customer ID',validate='one_to_one')
df['R_days']=(pd.Timestamp('2011-07-01')-pd.to_datetime(df.Recency)).dt.days
ft=df[['R_days','Frequency','Monetary']].copy()
ft[['Frequency','Monetary']]=np.log1p(ft[['Frequency','Monetary']])
X=StandardScaler().fit_transform(ft)
df['Cluster']=KMeans(n_clusters=6,random_state=42,n_init=20).fit_predict(X)
print(pd.crosstab(df['Cluster'],df['Customer_group']).to_string())
print(pd.crosstab(df['Cluster'],df['Customer_group'],normalize='index').round(4).to_string())
champ=df[df['Customer_group'].eq('Champions核心高价值客户')]
summary=champ.groupby('Cluster').agg(Customers=('Customer ID','size'),RepurchaseRate=('Repurchased','mean'),AvgFutureM=('FutureMonetary','mean'),FutureM=('FutureMonetary','sum'))
print(summary.round(4).to_string())
cell=champ[champ['Cluster'].eq(0)]
total=df['FutureMonetary'].sum()
print('Champions×原簇0人数：',len(cell))
print('未来净M占比：',cell['FutureMonetary'].sum()/total)
print('人均净M相对整体：',cell['FutureMonetary'].mean()/df['FutureMonetary'].mean())
print('复购率：',cell['Repurchased'].mean())
print('相同人数事后最优金额覆盖比例：',cell['FutureMonetary'].sum()/df.nlargest(len(cell),'FutureMonetary')['FutureMonetary'].sum())
