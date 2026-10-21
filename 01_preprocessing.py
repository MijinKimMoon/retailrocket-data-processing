# Converted from Jupyter Notebook; cell order preserved.
# Run from the project root unless a cell specifies otherwise.

# %%
import os

os.getcwd()

# %%
import pandas as pd
import sys

# 한글 출력 깨짐 방지
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

##### 열 행 다 출력하기
# 모든 행 출력
pd.set_option("display.max_rows", None)

# 모든 열 출력
pd.set_option("display.max_columns", None)

# 열 너비 및 한 줄 출력 제한 해제
pd.set_option("display.max_colwidth", None)
pd.set_option("display.width", None)

events = pd.read_csv("../data/events.csv")
print(events.head())

# %% [markdown]
# # item_properties_part1.csv, item_properties_part2.csv 파일 합치기

# %%
item_properties_1 = pd.read_csv("../data/item_properties_part1.csv")
item_properties_2 = pd.read_csv("../data/item_properties_part2.csv")

print(item_properties_1.shape)
print(item_properties_2.shape)

print(item_properties_1.columns)
print(item_properties_2.columns)

item_properties = pd.concat(
    [item_properties_1, item_properties_2],
    ignore_index=True
)

print("합친 후 결과")
print(item_properties_1.shape)
print(item_properties_2.shape)
print(item_properties.shape)

print(item_properties.head())

# %% [markdown]
# # item_properties 데이터 이해

# %%
item_properties.head(10)

# %%
item_properties["property"].value_counts().head(20)

# %%
properties = ["categoryid", "available", "888", "790"]

for prop in properties:
    print(f"\n[{prop}]")
    print(
        item_properties.loc[
            item_properties["property"] == prop,
            ["itemid", "property", "value"]
        ].head(10)
    )

# %% [markdown]
# # events 과 item_properties 테이블의 timestamp 속성_밀리초 -> datetime으로 변경

# %%
item_properties["timestamp"].head()

# %%
events["datetime"] = pd.to_datetime(
    events["timestamp"],
    unit="ms"
)

events[["timestamp", "datetime"]].head()

# %%
events["datetime"].min(), events["datetime"].max()

# %%
item_properties["datetime"] = pd.to_datetime(
    item_properties["timestamp"],
    unit="ms"
)

# %%
item_properties[["timestamp", "datetime"]].head()

# %%
item_properties["datetime"].min(), item_properties["datetime"].max()

# %% [markdown]
# # 데이터 전처리

# %% [markdown]
# ## 중복값 확인

# %%
category_tree = pd.read_csv("../data/category_tree.csv")

print("events:", events.duplicated().sum())
print("item_properties:", item_properties.duplicated().sum())
print("category_tree:", category_tree.duplicated().sum())

# %%
duplicate_events = events[
    events.duplicated(keep=False)
].sort_values(
    ["visitorid", "timestamp", "itemid", "event"]
)

duplicate_events.head(20)

# %% [markdown]
# ## 중복값 처리

# %%
events_clean = events.drop_duplicates().copy()

print("원본:", events.shape)
print("중복 제거 후:", events_clean.shape)
print("제거된 행:", len(events) - len(events_clean))

# %%
## 결측치 확인

# %%
print("[events]")
print(events_clean.isnull().sum())

print("\n[item_properties]")
print(item_properties.isnull().sum())

print("\n[category_tree]")
print(category_tree.isnull().sum())

# %% [markdown]
# ### 결측치가 구조상 자연스럽게 발생할 수 있는 결측치 인가?
# (가설1) events의 transactionid는 event필드 값이 view, addtocart이면 거래가 발생하지 않았으니 NULL인 것이 자연스럽다.
# (가설2) category_tree의 parentid는 최상위(root) 카테고리는 상위 카테고리가 없기 때문에 parentid가 NULL일 수 있다.

# %%
pd.crosstab(
    events_clean["event"],
    events_clean["transactionid"].isnull()
)

# %%
category_tree[category_tree["parentid"].isnull()]

# %%
root_categories = category_tree.loc[
    category_tree["parentid"].isnull(),
    "categoryid"
]

category_tree[
    category_tree["parentid"].isin(root_categories)
].sort_values("parentid")

# %% [markdown]
# ## 값의 유효성 및 데이터 정합성 검증

# %%
events_clean["event"].value_counts()

# %%
item_properties[item_properties["property"]=='available']['value'].value_counts()

# %%
print(
    item_properties.loc[
        item_properties["property"] == "categoryid",
        "value"
    ].dtype
)

print(category_tree["categoryid"].dtype)

# %%
item_properties.loc[
    item_properties["property"] == "categoryid",
    "value"
].head(10)

# %%
item_category = item_properties.loc[
    item_properties["property"] == "categoryid",
    "value"
]

item_category_num = pd.to_numeric(item_category, errors="coerce")

# %%
item_category_num.isna().sum()

# %%
item_category_num.isin(category_tree["categoryid"])

# %%
~item_category_num.isin(category_tree["categoryid"])

# %%
(~item_category_num.isin(category_tree["categoryid"])).sum()

# %%
unmatched_categories = item_category_num[
    ~item_category_num.isin(category_tree["categoryid"])
]

# %%
print(unmatched_categories.value_counts())
print("고유 categoryid 수:", unmatched_categories.nunique())

# %% [markdown]
# ### 혹시 부모 카테고리에 값이 있지 않은지 확인

# %%
unmatched_categories.isin(category_tree["parentid"])

# %%
unmatched_unique = unmatched_categories.unique()

pd.Series(unmatched_unique).isin(category_tree["parentid"])

# %%
category_rows = item_properties[
    item_properties["property"] == "categoryid"
].copy()

category_rows["categoryid_num"] = pd.to_numeric(category_rows["value"])

category_rows[
    category_rows["categoryid_num"].isin(unmatched_unique)
]["itemid"].nunique()

# %%
events_clean[
    ["visitorid", "itemid"]
].min()

# %% [markdown]
# ## 데이터 간 커버리지 확인

# %%
events_clean["itemid"].isin(item_properties["itemid"])

# %%
events_clean["itemid"].isin(
    item_properties["itemid"]
).mean() * 100

# %%
events_clean["itemid"].drop_duplicates().isin(
    item_properties["itemid"]
).mean() * 100

# %% [markdown]
# # 전처리한 데이터 테이블 내보내기

# %%
events_clean.to_csv(
    "../data/events_clean.csv",
    index=False
)

# %% [markdown]
# # item_properties 테이블 전처리_item_properties  테이블에서 의미가 익명화된 속성은 데이터 분석에 사용하지 않는걸로 결정

# %% [markdown]
# ## 같은 itemid가 관측 기간 동안 서로 다른 categoryid를 가진 경우가 있는가?

# %%
category_rows.head()

# %%
category_rows.groupby("itemid")["categoryid_num"].nunique()

# %%
item_category_count = category_rows.groupby("itemid")["categoryid_num"].nunique()
item_category_count[item_category_count >= 2]

# %%
(item_category_count >= 2).sum()

# %%
(item_category_count >= 2).sum() / len(item_category_count) * 100

# %%
item_properties[
    (item_properties["itemid"] == 25) &
    (item_properties["property"] == "categoryid")
]

# %%
category_data = category_rows[
    ["itemid", "categoryid_num", "datetime"]
]

category_data = category_data.rename(
    columns={"categoryid_num": "categoryid"}
)

# %%
category_data.head()

# %%
category_data = category_data.sort_values(
    ["itemid", "datetime"]
)

category_data[category_data["itemid"] == 25]

# %%
current = category_data["categoryid"]

previous = category_data.groupby("itemid")["categoryid"].shift()

category_data[current != previous]

# %%
category_changes = category_data[current != previous].copy()

# %%
print("변경 전:", len(category_data))
print("변경 후:", len(category_changes))

# %%
category_changes[
    category_changes["itemid"] == 25
]

# %%
category_changes.to_csv(
    "../data/category_changes.csv",
    index=False
)

# %%
available_rows = item_properties[
    item_properties["property"] == "available"
].copy()

# %%
available_rows["available"] = pd.to_numeric(
    available_rows["value"],
    errors="coerce"
)

# %%
available_rows["available"].isna().sum()

# %%
available_data = available_rows[
    ["itemid", "available", "datetime"]
]
available_data = available_data.sort_values(
    ["itemid", "datetime"]
)

# %%
current = available_data["available"]

previous = available_data.groupby("itemid")["available"].shift()

available_changes = available_data[
    current != previous
].copy()

# %%
print("변경 전:", len(available_data))
print("변경 후:", len(available_changes))

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

# %%
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

# %% [markdown]
# transactions → 기준이 되는 구매 데이터
# available_changes → 붙일 판매 가능 상태 데이터
# on="datetime" → 시간을 기준으로 찾음
# by="itemid" → 같은 상품끼리만 찾음
# direction="backward" → 구매 시점보다 이전 기록 중 가장 가까운 것을 가져옴

# %%
available_changes.to_csv(
    "../data/available_changes.csv",
    index=False
)

# %%
transaction_available[
    ["datetime", "itemid", "available"]
].head(10)
