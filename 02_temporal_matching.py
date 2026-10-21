# Converted from Jupyter Notebook; cell order preserved.
# Run from the project root unless a cell specifies otherwise.

# %% [markdown]
# # EDA 전에 전처리 이어서하기

# %%
import pandas as pd

events_clean = pd.read_csv(
    "data/events_clean.csv",
    parse_dates=["datetime"]
)

category_changes = pd.read_csv(
    "data/category_changes.csv",
    parse_dates=["datetime"]
)

available_changes = pd.read_csv(
    "data/available_changes.csv",
    parse_dates=["datetime"]
)

# %%
print(events_clean.shape)
print(category_changes.shape)
print(available_changes.shape)

# %%
transactions = events_clean[
    events_clean["event"] == "transaction"
].copy()

# %%
transactions.shape

# %%
transactions = transactions.sort_values(
    ["datetime", "itemid"]
)

available_changes = available_changes.sort_values(
    ["datetime", "itemid"]
)

# %%
transaction_available = pd.merge_asof(
    transactions,
    available_changes,
    on="datetime",
    by="itemid",
    direction="backward"
)

# %%
transaction_available[
    ["datetime", "itemid", "available"]
].head(10)

# %%
transaction_available["available"].isna().sum()

# %%
transaction_available["available"].value_counts(dropna=False)

# %%
transaction_available[
    transaction_available["available"] == 0
][["datetime", "visitorid", "itemid", "available"]].head()

# %%
available_changes[
    available_changes["itemid"] == 408139
]

# %%
transaction_available_missing = transaction_available[
    transaction_available["available"].isna()
].copy()

# %% [markdown]
# ## available을 연결하지 못한 구매가 item_properties 시작일(2015-05-10) 이전에 발생해서 그런 걸까? NO

# %%
transaction_available_missing["datetime"].min(), \
transaction_available_missing["datetime"].max()

# %% [markdown]
# ## NaN 구매 상품 중 available_changes에 아예 한 번도 등장하지 않는 상품이 있는가?
# - 1,974건 (True): 해당 상품의 available 정보는 존재하지만, 구매 시점 이전의 상태 기록이 없어서 merge_asof()가 연결하지 못함
# - 475건 (False): 해당 상품은 available_changes에 판매 가능 상태 정보 자체가 없음

# %%
transaction_available_missing["itemid"].isin(
    available_changes["itemid"]
).value_counts()

# %%
missing_with_available = transaction_available_missing[
    transaction_available_missing["itemid"].isin(
        available_changes["itemid"]
    )
]

# %%
missing_with_available[
    ["datetime", "itemid"]
].head()

# %%
available_changes[
    available_changes["itemid"] == 40685
]

# %% [markdown]
# # category_changes를 이벤트에 시간 기준으로 붙이기

# %%
events_clean = events_clean.sort_values(
    ["datetime", "itemid"]
)

category_changes = category_changes.sort_values(
    ["datetime", "itemid"]
)

# %%
events_analysis = pd.merge_asof(
    events_clean,
    category_changes,
    on="datetime",
    by="itemid",
    direction="backward"
)

# %%
events_analysis.shape

# %%
events_analysis["categoryid"].isna().sum()

# %%
category_missing = events_analysis[
    events_analysis["categoryid"].isna()
].copy()

# %%
category_missing["itemid"].isin(
    category_changes["itemid"]
).value_counts()

# %%
events_analysis[
    events_analysis["event"] == "transaction"
]["categoryid"].isna().sum()

# %%
events_analysis.groupby("event")["categoryid"].agg(
    total="size",
    missing=lambda x: x.isna().sum(),
    matched=lambda x: x.notna().sum()
)

# %%
events_analysis.to_csv(
    "data/events_analysis.csv",
    index=False
)

# %% [markdown]
# # 전처리 확인

# %%
events_analysis.info()

# %%
events_analysis.head()

# %%
events_final = events_analysis.copy()

# %%
events_final = events_final.drop(columns=["timestamp"])

# %%
events_final

# %%
events_final[
    events_final["event"] == "transaction"
].groupby("transactionid").size()

# %%
items_per_transaction = (
    events_final[
        events_final["event"] == "transaction"
    ]
    .groupby("transactionid")
    .size()
)

# %%
items_per_transaction.max()

# %%
events_final["categoryid"] = (
    events_final["categoryid"].astype("Int64")
)

# %%
events_final["transactionid"] = (
    events_final["transactionid"].astype("Int64")
)

# %%
events_final.info()

# %%
events_final.isna().sum()

# %%
events_final.to_csv(
    "data/events_final.csv",
    index=False
)

# %% [markdown]
# # 전처리 종료
