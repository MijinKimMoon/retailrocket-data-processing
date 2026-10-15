# RetailRocket E-commerce Data Processing

Python·Pandas와 MySQL을 사용해 RetailRocket 이커머스 이벤트와 상품 속성 변경 이력을 정리하고, 이벤트 발생 시점에 맞는 카테고리 정보를 연결한 **개인 프로젝트**입니다. 분석용 데이터셋을 생성한 후 SQL로 사용자 행동을 탐색했습니다.

> **프로젝트 범위:** 로컬 환경에서 진행한 탐색·전처리·CSV 저장·MySQL 적재 및 SQL 분석입니다. Airflow/dbt 기반 스케줄링, 클라우드 배포, 운영형 파이프라인 구축 프로젝트는 아닙니다.

## Data & tools

| 원천 데이터 | 행 수 | 내용 |
| --- | ---: | --- |
| `events.csv` | 2,756,101 | 상품 조회(`view`), 장바구니(`addtocart`), 구매(`transaction`) |
| `item_properties_part1.csv` + `item_properties_part2.csv` | 20,275,902 | 시점별 상품 속성(`categoryid`, `available` 등) |
| `category_tree.csv` | 1,669 | 카테고리 계층 정보 |

- **Tools:** Python, Pandas, MySQL, SQL, Jupyter Notebook
- 원천 데이터: [RetailRocket recommender system dataset (Kaggle)](https://www.kaggle.com/datasets/retailrocket/ecommerce-dataset). 원천 데이터 파일은 이 저장소에 포함하지 않습니다.

## Processing flow

1. 이벤트의 시간값을 `datetime`으로 변환하고 완전 중복 **460건** 제거 → **2,755,641건** 유지.
2. 상품 속성 파일을 결합하고, `categoryid` 및 `available`의 상품별 시점 기록을 검토.
3. 상품별로 값이 바뀐 기록을 추출해 변경 이력 구성.
4. `pd.merge_asof(..., on="datetime", by="itemid", direction="backward")`로 각 이벤트 시점 **이전**의 가장 최근 카테고리 속성 연결.
5. 매칭되지 않는 데이터는 임의로 채우지 않고 결측 유지. 시점 기준 카테고리 미매칭 이벤트 **656,867건** 확인.
6. 최종 6개 컬럼(`visitorid`, `event`, `itemid`, `transactionid`, `datetime`, `categoryid`)의 CSV를 작성하고 MySQL `events_final` 테이블로 적재.
7. SQL로 이벤트 유형별 건수, 사용자 행동 경로, 전환 및 카테고리별 차이 탐색.

**Data-quality note:** 이벤트 상품 ID가 상품 속성 데이터에 존재하는 커버리지 **90.73%**와 시점 조건을 적용한 카테고리 매칭률은 서로 다른 지표입니다. `available`을 이용한 구매 시점 검증은 별도로 진행했으며, 최종 MySQL `events_final` 테이블에는 `available` 컬럼을 적재하지 않았습니다.

## Repository contents

```text
retailrocket-data-processing/
├── README.md
├── .gitignore
├── notebooks/
│   ├── 01_preprocessing.ipynb       # 데이터 탐색, 중복·품질 검증, 속성 변경 이력 생성
│   └── 02_temporal_matching.ipynb   # 시점 매칭, 미매칭 검증, 최종 CSV 생성
└── sql/
    └── retailrocket_analysis.sql   # events_final 생성·적재 및 탐색 SQL
```

## Running locally

**Requirements:** Python, Jupyter, Pandas, MySQL 8.x (SQL 쿼리 문법에 따라 버전 호환성 점검 필요), 원천 CSV를 처리할 수 있는 충분한 메모리와 디스크 공간.

1. Kaggle 원천 데이터를 내려받고 저장소 루트의 `data/` 폴더에 다음 파일을 준비합니다.

```text
retailrocket-data-processing/
├── notebooks/
├── sql/
└── data/                     # .gitignore로 업로드 제외
    ├── events.csv
    ├── item_properties_part1.csv
    ├── item_properties_part2.csv
    └── category_tree.csv
```

2. `notebooks/01_preprocessing.ipynb`를 실행해 `data/events_clean.csv`, `data/category_changes.csv`, `data/available_changes.csv`를 생성합니다.
3. 이어서 `notebooks/02_temporal_matching.ipynb`를 실행해 `data/events_final.csv`를 생성합니다.
4. `sql/retailrocket_analysis.sql`의 `LOAD DATA LOCAL INFILE` 파일 경로를 **사용 중인 PC의 실제 CSV 절대경로**로 바꾸고, MySQL의 `local_infile` 설정과 파일 접근 권한을 확인한 뒤 적재 부분을 실행합니다.
5. 이어지는 SQL 쿼리는 관심 분석별로 **선택 실행**합니다. 전체 파일을 배포 스크립트처럼 무조건 한 번에 실행하는 용도로 작성된 코드는 아닙니다.

> **재현성 안내:** 이 파일들은 기존 탐색 노트북의 **코드 셀과 순서를 보존**하고 저장된 출력만 삭제한 공개용 사본입니다. 새 환경에서 처음부터 끝까지 재실행하는 테스트는 수행하지 않았습니다. 일부 셀은 탐색용이며, 대용량 데이터 처리로 실행에 시간이 걸리거나 환경에 따라 추가 조정이 필요할 수 있습니다. `data/` 경로는 **노트북 폴더를 작업 디렉터리로 실행하는 경우**를 기준으로 합니다.

## Limitations

- 상품 속성 기록의 범위로 인해 일부 이벤트는 발생 시점 이전의 속성을 찾을 수 없습니다.
- 구매 이벤트 중 `available` 시점 매칭이 불가능한 사례를 조사했으나 누락된 원천 정보를 임의로 복원하지 않았습니다.
- 퍼널 분석의 결과는 ‘최초 이벤트 시점’ 기준인지 ‘조건을 만족하는 이벤트 순서 존재’ 기준인지에 따라 달라지므로 SQL 파일에 두 접근을 남겼습니다.
- 카테고리 변경: 카테고리 정보가 연결된 조회 기준 사용자·상품 조합 1,611,479개 중 442개(0.0274%)에서 복수 카테고리가 확인되었습니다. 따라서 카테고리별 분석에서 동일 조합이 여러 카테고리에 포함될 가능성이 있습니다.
- 반복 조회 분석: 구매 조합은 최초 구매 이전까지, 비구매 조합은 전체 분석 기간의 조회 횟수를 집계했습니다. 관찰 기간의 차이가 구매 전환율 비교에 영향을 줄 수 있으며, 분석 결과는 인과관계를 의미하지 않습니다.
- **자동화된 재실행, 테스트, 성능 튜닝, 모니터링 구축은 이 저장소가 입증하는 범위에 포함하지 않습니다.**

