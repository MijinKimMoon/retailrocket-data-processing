-- PUBLIC REPOSITORY NOTE: Adjust LOAD DATA LOCAL INFILE path to an absolute path on your own machine.
-- This script reflects the original exploratory SQL analysis; execute sections selectively.

-- DB 생성 & 테이블 생성

CREATE DATABASE retailrocket;

USE retailrocket;

CREATE TABLE events_final (
    visitorid BIGINT,
    event VARCHAR(20),
    itemid BIGINT,
    transactionid BIGINT NULL,
    datetime DATETIME(3),
    categoryid BIGINT NULL
);

DESC events_final;

SHOW VARIABLES LIKE 'local_infile';

-- 데이터 불러오기

LOAD DATA LOCAL INFILE
'../data/events_final.csv'
INTO TABLE events_final
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(visitorid, event, itemid, @transactionid, datetime, @categoryid)
SET
    transactionid = NULLIF(@transactionid, ''),
    categoryid = NULLIF(@categoryid, '');
    
    
-- 데이터 확인

SELECT COUNT(*)
FROM events_final;

SELECT event, COUNT(*)
FROM events_final
GROUP BY event;  

-- Q1. 사용자는 view → addtocart → transaction 과정에서 어느 단계에서 가장 많이 이탈하는가?

SELECT event, COUNT(DISTINCT visitorid)
FROM events_final
GROUP BY event;

#view	1404179
#addtocart	37722
#transaction	11719

-- 장바구니 사용자는 실제로 조회를 경험했는가? 구매 사용자는 조회와 장바구니를 경험했는가?

-- 시간 순서 고려 X
SELECT COUNT(*)
FROM (
    SELECT DISTINCT visitorid
    FROM events_final
    WHERE event = 'view'
) AS v
INNER JOIN (
    SELECT DISTINCT visitorid
    FROM events_final
    WHERE event = 'addtocart'
) AS a
    ON v.visitorid = a.visitorid;

# view ∩ addtocart = 34,401명

SELECT COUNT(*)
FROM (
    SELECT DISTINCT visitorid
    FROM events_final
    WHERE event = 'view'
) AS v
INNER JOIN (
    SELECT DISTINCT visitorid
    FROM events_final
    WHERE event = 'transaction'
) AS t
    ON v.visitorid = t.visitorid;

# view ∩ transaction = 11,291명

SELECT COUNT(*)
FROM (
    SELECT DISTINCT visitorid
    FROM events_final
    WHERE event = 'addtocart'
) AS a
INNER JOIN (
    SELECT DISTINCT visitorid
    FROM events_final
    WHERE event = 'transaction'
) AS t
    ON a.visitorid = t.visitorid;
    
# addtocart ∩ transaction = 10,576명

-- 시간 순서 고려 o
WITH funnel AS (SELECT
    visitorid,
    itemid,
	MIN(CASE WHEN event = 'view' THEN datetime END) AS first_view
FROM events_final
GROUP BY visitorid,itemid)
SELECT COUNT(*)
FROM funnel
WHERE first_view IS NOT NULL;

# view 성립 조합 2,132,127개

WITH funnel AS (SELECT
    visitorid,
    itemid,
	MIN(CASE WHEN event = 'view' THEN datetime END) AS first_view,
	MIN(CASE WHEN event = 'addtocart' THEN datetime END) AS first_addtocart
FROM events_final
GROUP BY visitorid,itemid)
SELECT COUNT(*)
FROM funnel
WHERE first_view IS NOT NULL
	AND first_addtocart IS NOT NULL
	AND first_view <= first_addtocart;
    
# 동일한 visitorid + itemid 조합에서 최초 view 시점 ≤ 최초 addtocart 시점인 상품 행동 조합이 45,395개

WITH funnel AS (SELECT
    visitorid,
    itemid,
	MIN(CASE WHEN event = 'view' THEN datetime END) AS first_view,
	MIN(CASE WHEN event = 'addtocart' THEN datetime END) AS first_addtocart,
    MIN(CASE WHEN event = 'transaction' THEN datetime END) AS first_transaction
FROM events_final
GROUP BY visitorid,itemid)
SELECT COUNT(*)
FROM funnel
WHERE first_view IS NOT NULL
    AND first_addtocart IS NOT NULL
    AND first_transaction IS NOT NULL
    AND first_view <= first_addtocart
    AND first_addtocart <= first_transaction;
    
# view → addtocart → transaction까지 성립한 조합: 16,502개

-- 정리
#퍼널 단계	                    조합 수
#view	                        2,132,127
#view → addtocart	            45,395
#view → addtocart → transaction	16,502

#단계	         visitorid + itemid 조합	이전 단계 대비 전환율	이탈률
#View	                      2,132,127	       -	          -
#View → Add to Cart	             45,395	      2.13%	       97.87%
#View → Add to Cart → Transaction	16,502	 36.35%	       63.65%

-- 한계 확인
WITH repeated_cart AS (
SELECT
    visitorid,
    itemid,
    COUNT(*) AS addtocart_count
FROM events_final
WHERE event = 'addtocart'
GROUP BY visitorid, itemid
HAVING addtocart_count >= 2)
SELECT COUNT(*)
FROM repeated_cart;

# 반복 addtocart가 4,978개

WITH view_to_cart AS (
    SELECT DISTINCT
        v.visitorid,
        v.itemid
    FROM events_final AS v
    INNER JOIN events_final AS a
        ON v.visitorid = a.visitorid
        AND v.itemid = a.itemid
        AND a.datetime >= v.datetime
    WHERE v.event = 'view'
        AND a.event = 'addtocart'
)
SELECT COUNT(*)
FROM view_to_cart;

# 실제로 view 이후 addtocart가 하나라도 존재하는지를 Self Join으로 확인하니 45,810개

WITH full_funnel AS (
    SELECT DISTINCT
        v.visitorid,
        v.itemid
    FROM events_final AS v
    INNER JOIN events_final AS a
        ON v.visitorid = a.visitorid
        AND v.itemid = a.itemid
        AND a.datetime >= v.datetime
    INNER JOIN events_final AS t
        ON a.visitorid = t.visitorid
        AND a.itemid = t.itemid
        AND t.datetime >= a.datetime
    WHERE v.event = 'view'
        AND a.event = 'addtocart'
        AND t.event = 'transaction'
)
SELECT COUNT(*)
FROM full_funnel;

#동일한 visitorid + itemid에서 어떤 view가 존재하고 → 그 이후 addtocart가 존재하고 → 그 이후 transaction이 존재하는 케이스 : 16700

WITH user_event AS (
    SELECT
        visitorid,
        MAX(CASE WHEN event = 'view' THEN 1 ELSE 0 END) AS has_view,
        MAX(CASE WHEN event = 'transaction' THEN 1 ELSE 0 END) AS has_transaction
    FROM events_final
    GROUP BY visitorid
)

SELECT
    SUM(has_view) AS view_users,
    SUM(CASE
        WHEN has_view = 1 AND has_transaction = 1 THEN 1
        ELSE 0
    END) AS purchase_users,
    ROUND(
        SUM(CASE
            WHEN has_view = 1 AND has_transaction = 1 THEN 1
            ELSE 0
        END) / SUM(has_view) * 100,
        2
    ) AS purchase_conversion_rate
FROM user_event;

# 	view_users	purchase_users	purchase_conversion_rate
#	1404179	         11291	         0.80

-- Q2. 구매 사용자와 비구매 사용자의 행동에는 어떤 차이가 있는가?

-- 가설 1. 상품 조회 활동이 많은 사용자는 구매할 가능성이 높을 것이다.
WITH user_views AS (
    SELECT
        visitorid,
        COUNT(*) AS view_count
    FROM events_final
    WHERE event = 'view'
    GROUP BY visitorid
)
SELECT
    MIN(view_count),
    AVG(view_count),
    MAX(view_count)
FROM user_views;

#MIN = 1회
#AVG = 1.8973회
#MAX = 6,479회

WITH user_views AS (
    SELECT
        visitorid,
        COUNT(*) AS view_count
    FROM events_final
    WHERE event = 'view'
    GROUP BY visitorid
)
SELECT
    view_count,
    COUNT(*) AS user_count
FROM user_views
GROUP BY view_count
ORDER BY view_count;

--

WITH user_views AS (
    SELECT
        visitorid,
        COUNT(*) AS view_count
    FROM events_final
    WHERE event = 'view'
    GROUP BY visitorid
)

SELECT
    visitorid,
    view_count,
    CASE
        WHEN view_count = 1 THEN '1회'
        WHEN view_count BETWEEN 2 AND 3 THEN '2~3회'
        WHEN view_count BETWEEN 4 AND 5 THEN '4~5회'
        WHEN view_count BETWEEN 6 AND 10 THEN '6~10회'
        ELSE '11회 이상'
    END AS view_group
FROM user_views;
--
WITH user_behavior AS (
    SELECT
        visitorid,
        SUM(CASE WHEN event = 'view' THEN 1 ELSE 0 END) AS view_count,
        MAX(CASE WHEN event = 'transaction' THEN 1 ELSE 0 END) AS has_transaction
    FROM events_final
    GROUP BY visitorid
),

view_group AS (
    SELECT
        visitorid,
        view_count,
        has_transaction,
        CASE
            WHEN view_count = 1 THEN '1회'
            WHEN view_count BETWEEN 2 AND 3 THEN '2~3회'
            WHEN view_count BETWEEN 4 AND 5 THEN '4~5회'
            WHEN view_count BETWEEN 6 AND 10 THEN '6~10회'
            ELSE '11회 이상'
        END AS view_group
    FROM user_behavior
    WHERE view_count >= 1
)

SELECT
    view_group,
    COUNT(*) AS user_count,
    SUM(has_transaction) AS purchase_users,
    ROUND(SUM(has_transaction) / COUNT(*) * 100, 2) AS purchase_rate
FROM view_group
GROUP BY view_group
ORDER BY
    CASE view_group
        WHEN '1회' THEN 1
        WHEN '2~3회' THEN 2
        WHEN '4~5회' THEN 3
        WHEN '6~10회' THEN 4
        WHEN '11회 이상' THEN 5
    END;


-- 가설 2. 장바구니 추가 경험이 있는 사용자는 그렇지 않은 사용자보다 구매할 가능성이 높을 것이다.
WITH user_behavior AS (
    SELECT
        visitorid,
        MAX(CASE WHEN event = 'addtocart' THEN 1 ELSE 0 END) AS has_cart,
        MAX(CASE WHEN event = 'transaction' THEN 1 ELSE 0 END) AS has_transaction
    FROM events_final
    GROUP BY visitorid
)

SELECT
    has_cart,
    COUNT(*) AS user_count,
    SUM(has_transaction) AS purchase_users,
    ROUND(
        SUM(has_transaction) / COUNT(*) * 100,
        2
    ) AS purchase_rate
FROM user_behavior
GROUP BY has_cart
ORDER BY has_cart;
--
WITH user_behavior AS (
    SELECT
        visitorid,
        MAX(CASE WHEN event = 'view' THEN 1 ELSE 0 END) AS has_view,
        MAX(CASE WHEN event = 'addtocart' THEN 1 ELSE 0 END) AS has_cart,
        MAX(CASE WHEN event = 'transaction' THEN 1 ELSE 0 END) AS has_transaction
    FROM events_final
    GROUP BY visitorid
)

SELECT
    has_cart,
    COUNT(*) AS user_count,
    SUM(has_transaction) AS purchase_users,
    ROUND(
        SUM(has_transaction) / COUNT(*) * 100,
        2
    ) AS purchase_rate
FROM user_behavior
WHERE has_view = 1
GROUP BY has_cart
ORDER BY has_cart;

-- Q3. 어떤 상품·카테고리에서 행동 및 전환 차이가 나타나는가?
SELECT COUNT(DISTINCT categoryid)
FROM events_final
WHERE categoryid IS NOT NULL;
--
SELECT
    categoryid,
    COUNT(*) AS event_count
FROM events_final
WHERE categoryid IS NOT NULL
GROUP BY categoryid
ORDER BY event_count DESC;
--
# 카테고리별 view 수의 분포
WITH category_views AS (
    SELECT
        categoryid,
        COUNT(*) AS view_count
    FROM events_final
    WHERE categoryid IS NOT NULL
      AND event = 'view'
    GROUP BY categoryid
)
SELECT
    MIN(view_count) AS min_views,
    AVG(view_count) AS avg_views,
    MAX(view_count) AS max_views
FROM category_views;
--
# 구간별 카테고리 수
WITH category_views AS (
    SELECT
        categoryid,
        COUNT(*) AS view_count
    FROM events_final
    WHERE categoryid IS NOT NULL
      AND event = 'view'
    GROUP BY categoryid
)
SELECT
    CASE
        WHEN view_count < 10 THEN '10회 미만'
        WHEN view_count < 50 THEN '10~49회'
        WHEN view_count < 100 THEN '50~99회'
        WHEN view_count < 500 THEN '100~499회'
        WHEN view_count < 1000 THEN '500~999회'
        ELSE '1000회 이상'
    END AS view_group,
    COUNT(*) AS category_count
FROM category_views
GROUP BY view_group
ORDER BY
    CASE view_group
        WHEN '10회 미만' THEN 1
        WHEN '10~49회' THEN 2
        WHEN '50~99회' THEN 3
        WHEN '100~499회' THEN 4
        WHEN '500~999회' THEN 5
        WHEN '1000회 이상' THEN 6
    END;
    --
    # 카테고리별 view → addtocart 경로가 존재하는 visitorid + itemid 조합 수
    WITH category_views AS (
    SELECT
        categoryid,
        COUNT(DISTINCT visitorid, itemid) AS view_count
    FROM events_final
    WHERE event = 'view'
      AND categoryid IS NOT NULL
    GROUP BY categoryid
),

view_to_cart AS (
    SELECT DISTINCT
        v.categoryid,
        v.visitorid,
        v.itemid
    FROM events_final AS v
    INNER JOIN events_final AS a
        ON v.visitorid = a.visitorid
        AND v.itemid = a.itemid
        AND a.datetime >= v.datetime
    WHERE v.event = 'view'
      AND a.event = 'addtocart'
      AND v.categoryid IS NOT NULL
)

SELECT
    cv.categoryid,
    cv.view_count,
    COUNT(vc.visitorid) AS cart_count,
    ROUND(
        COUNT(vc.visitorid) / cv.view_count * 100,
        2
    ) AS view_to_cart_rate
FROM category_views AS cv
LEFT JOIN view_to_cart AS vc
    ON cv.categoryid = vc.categoryid
WHERE cv.view_count >= 100
GROUP BY
    cv.categoryid,
    cv.view_count
ORDER BY view_to_cart_rate DESC;
--
# 조회 규모 × 조회→장바구니 전환율로 카테고리를 비교
WITH category_views AS (
    SELECT
        categoryid,
        COUNT(DISTINCT visitorid, itemid) AS view_count
    FROM events_final
    WHERE event = 'view'
      AND categoryid IS NOT NULL
    GROUP BY categoryid
),

view_to_cart AS (
    SELECT DISTINCT
        v.categoryid,
        v.visitorid,
        v.itemid
    FROM events_final AS v
    INNER JOIN events_final AS a
        ON v.visitorid = a.visitorid
        AND v.itemid = a.itemid
        AND a.datetime >= v.datetime
    WHERE v.event = 'view'
      AND a.event = 'addtocart'
      AND v.categoryid IS NOT NULL
),

category_funnel AS (
    SELECT
        cv.categoryid,
        cv.view_count,
        COUNT(vc.visitorid) AS cart_count,
        COUNT(vc.visitorid) / cv.view_count * 100 AS view_to_cart_rate
    FROM category_views AS cv
    LEFT JOIN view_to_cart AS vc
        ON cv.categoryid = vc.categoryid
    WHERE cv.view_count >= 100
    GROUP BY
        cv.categoryid,
        cv.view_count
)

SELECT
    ROUND(AVG(view_count), 2) AS avg_view_count,
    ROUND(AVG(view_to_cart_rate), 2) AS avg_view_to_cart_rate
FROM category_funnel;

--

# 평균 조회 조합 수: 2,124.77/평균 조회→장바구니 전환율: 2.36%을 기준으로 카테고리를 4개의 그룹으로 나눔
WITH category_views AS (
    SELECT
        categoryid,
        COUNT(DISTINCT visitorid, itemid) AS view_count
    FROM events_final
    WHERE event = 'view'
      AND categoryid IS NOT NULL
    GROUP BY categoryid
),

view_to_cart AS (
    SELECT DISTINCT
        v.categoryid,
        v.visitorid,
        v.itemid
    FROM events_final AS v
    INNER JOIN events_final AS a
        ON v.visitorid = a.visitorid
        AND v.itemid = a.itemid
        AND a.datetime >= v.datetime
    WHERE v.event = 'view'
      AND a.event = 'addtocart'
      AND v.categoryid IS NOT NULL
),

category_funnel AS (
    SELECT
        cv.categoryid,
        cv.view_count,
        COUNT(vc.visitorid) AS cart_count,
        COUNT(vc.visitorid) / cv.view_count * 100 AS view_to_cart_rate
    FROM category_views AS cv
    LEFT JOIN view_to_cart AS vc
        ON cv.categoryid = vc.categoryid
    WHERE cv.view_count >= 100
    GROUP BY
        cv.categoryid,
        cv.view_count
)

SELECT
    categoryid,
    view_count,
    cart_count,
    ROUND(view_to_cart_rate, 2) AS view_to_cart_rate,
    CASE
        WHEN view_count >= 2124.77
             AND view_to_cart_rate >= 2.36
            THEN '조회 높음 / 전환 높음'

        WHEN view_count >= 2124.77
             AND view_to_cart_rate < 2.36
            THEN '조회 높음 / 전환 낮음'

        WHEN view_count < 2124.77
             AND view_to_cart_rate >= 2.36
            THEN '조회 낮음 / 전환 높음'

        ELSE '조회 낮음 / 전환 낮음'
    END AS category_group

FROM category_funnel
ORDER BY view_count DESC;
--
# 구매단계까지 확인
WITH category_views AS (
    SELECT DISTINCT
        categoryid,
        visitorid,
        itemid
    FROM events_final
    WHERE event = 'view'
      AND categoryid IS NOT NULL
),

view_to_cart AS (
    SELECT DISTINCT
        v.categoryid,
        v.visitorid,
        v.itemid
    FROM events_final AS v
    INNER JOIN events_final AS a
        ON v.visitorid = a.visitorid
        AND v.itemid = a.itemid
        AND a.datetime >= v.datetime
    WHERE v.event = 'view'
      AND a.event = 'addtocart'
      AND v.categoryid IS NOT NULL
),

full_funnel AS (
    SELECT DISTINCT
        v.categoryid,
        v.visitorid,
        v.itemid
    FROM events_final AS v
    INNER JOIN events_final AS a
        ON v.visitorid = a.visitorid
        AND v.itemid = a.itemid
        AND a.datetime >= v.datetime
    INNER JOIN events_final AS t
        ON a.visitorid = t.visitorid
        AND a.itemid = t.itemid
        AND t.datetime >= a.datetime
    WHERE v.event = 'view'
      AND a.event = 'addtocart'
      AND t.event = 'transaction'
      AND v.categoryid IS NOT NULL
),

category_funnel AS (
    SELECT
        cv.categoryid,
        COUNT(*) AS view_count,
        COUNT(vc.visitorid) AS cart_count,
        COUNT(ff.visitorid) AS purchase_count
    FROM category_views AS cv

    LEFT JOIN view_to_cart AS vc
        ON cv.categoryid = vc.categoryid
        AND cv.visitorid = vc.visitorid
        AND cv.itemid = vc.itemid

    LEFT JOIN full_funnel AS ff
        ON cv.categoryid = ff.categoryid
        AND cv.visitorid = ff.visitorid
        AND cv.itemid = ff.itemid

    GROUP BY cv.categoryid
)

SELECT
    categoryid,
    view_count,
    cart_count,
    purchase_count,

    ROUND(
        cart_count / view_count * 100,
        2
    ) AS view_to_cart_rate,

    ROUND(
        purchase_count / NULLIF(cart_count, 0) * 100,
        2
    ) AS cart_to_purchase_rate

FROM category_funnel

WHERE view_count >= 100

ORDER BY view_count DESC;

-- Q4. 어떤 행동 패턴에서 구매 전환이 높게 나타나는가?

# visitorid + itemid별로 같은 상품을 몇 번 조회했는지?
WITH item_view_count AS (
    SELECT
        visitorid,
        itemid,
        COUNT(*) AS view_count
    FROM events_final
    WHERE event = 'view'
    GROUP BY visitorid, itemid
)

SELECT
    view_count,
    COUNT(*) AS user_item_count
FROM item_view_count
GROUP BY view_count
ORDER BY view_count;

--
# 구매 이전에 해당 상품을 몇 번 조회했는가?
# 구매하지 않은 상품은 전체 조회를 세고, 구매한 상품은 최초 구매 시점 이전의 조회만 세는 것
WITH first_purchase AS (
    SELECT
        visitorid,
        itemid,
        MIN(datetime) AS first_purchase_time
    FROM events_final
    WHERE event = 'transaction'
    GROUP BY visitorid, itemid
),

user_item_behavior AS (
    SELECT
        e.visitorid,
        e.itemid,

        COUNT(
            CASE
                WHEN e.event = 'view'
                     AND (
                         fp.first_purchase_time IS NULL
                         OR e.datetime <= fp.first_purchase_time
                     )
                THEN 1
            END
        ) AS view_count,

        CASE
            WHEN fp.first_purchase_time IS NOT NULL THEN 1
            ELSE 0
        END AS purchased

    FROM events_final AS e

    LEFT JOIN first_purchase AS fp
        ON e.visitorid = fp.visitorid
        AND e.itemid = fp.itemid

    GROUP BY
        e.visitorid,
        e.itemid,
        fp.first_purchase_time
),

view_group AS (
    SELECT
        visitorid,
        itemid,
        view_count,
        purchased,

        CASE
            WHEN view_count = 1 THEN '1회'
            WHEN view_count = 2 THEN '2회'
            WHEN view_count BETWEEN 3 AND 5 THEN '3~5회'
            ELSE '6회 이상'
        END AS view_group

    FROM user_item_behavior

    WHERE view_count >= 1
)

SELECT
    view_group,
    COUNT(*) AS user_item_count,
    SUM(purchased) AS purchase_count,

    ROUND(
        SUM(purchased) / COUNT(*) * 100,
        2
    ) AS purchase_rate

FROM view_group

GROUP BY view_group

ORDER BY
    CASE view_group
        WHEN '1회' THEN 1
        WHEN '2회' THEN 2
        WHEN '3~5회' THEN 3
        WHEN '6회 이상' THEN 4
    END;
    
--
# 시각화용
#1. 구매 퍼널 시각화
WITH view_pairs AS (
    SELECT DISTINCT
        visitorid,
        itemid
    FROM events_final
    WHERE event = 'view'
),

view_to_cart AS (
    SELECT DISTINCT
        v.visitorid,
        v.itemid
    FROM events_final AS v
    INNER JOIN events_final AS a
        ON v.visitorid = a.visitorid
        AND v.itemid = a.itemid
        AND a.datetime >= v.datetime
    WHERE v.event = 'view'
      AND a.event = 'addtocart'
),

full_funnel AS (
    SELECT DISTINCT
        v.visitorid,
        v.itemid
    FROM events_final AS v
    INNER JOIN events_final AS a
        ON v.visitorid = a.visitorid
        AND v.itemid = a.itemid
        AND a.datetime >= v.datetime
    INNER JOIN events_final AS t
        ON a.visitorid = t.visitorid
        AND a.itemid = t.itemid
        AND t.datetime >= a.datetime
    WHERE v.event = 'view'
      AND a.event = 'addtocart'
      AND t.event = 'transaction'
),

funnel_count AS (
    SELECT
        (SELECT COUNT(*) FROM view_pairs) AS view_count,
        (SELECT COUNT(*) FROM view_to_cart) AS cart_count,
        (SELECT COUNT(*) FROM full_funnel) AS purchase_count
)

SELECT
    1 AS stage_order,
    'View' AS stage,
    view_count AS combination_count,
    NULL AS conversion_rate,
    NULL AS dropoff_rate
FROM funnel_count

UNION ALL

SELECT
    2 AS stage_order,
    'Add to Cart' AS stage,
    cart_count AS combination_count,
    ROUND(cart_count / view_count * 100, 2) AS conversion_rate,
    ROUND((1 - cart_count / view_count) * 100, 2) AS dropoff_rate
FROM funnel_count

UNION ALL

SELECT
    3 AS stage_order,
    'Purchase' AS stage,
    purchase_count AS combination_count,
    ROUND(purchase_count / cart_count * 100, 2) AS conversion_rate,
    ROUND((1 - purchase_count / cart_count) * 100, 2) AS dropoff_rate
FROM funnel_count

ORDER BY stage_order;

#02. 동일 상품 반복 조회별 구매전환율
WITH first_purchase AS (
    SELECT
        visitorid,
        itemid,
        MIN(datetime) AS first_purchase_time
    FROM events_final
    WHERE event = 'transaction'
    GROUP BY
        visitorid,
        itemid
),

user_item_behavior AS (
    SELECT
        e.visitorid,
        e.itemid,

        COUNT(
            CASE
                WHEN e.event = 'view'
                     AND (
                         fp.first_purchase_time IS NULL
                         OR e.datetime <= fp.first_purchase_time
                     )
                THEN 1
            END
        ) AS view_count,

        CASE
            WHEN fp.first_purchase_time IS NOT NULL THEN 1
            ELSE 0
        END AS purchased

    FROM events_final AS e

    LEFT JOIN first_purchase AS fp
        ON e.visitorid = fp.visitorid
        AND e.itemid = fp.itemid

    GROUP BY
        e.visitorid,
        e.itemid,
        fp.first_purchase_time
),

view_group AS (
    SELECT
        visitorid,
        itemid,
        view_count,
        purchased,

        CASE
            WHEN view_count = 1 THEN '1회'
            WHEN view_count = 2 THEN '2회'
            WHEN view_count BETWEEN 3 AND 5 THEN '3~5회'
            ELSE '6회 이상'
        END AS view_group,

        CASE
            WHEN view_count = 1 THEN 1
            WHEN view_count = 2 THEN 2
            WHEN view_count BETWEEN 3 AND 5 THEN 3
            ELSE 4
        END AS group_order

    FROM user_item_behavior
    WHERE view_count >= 1
)

SELECT
    group_order,
    view_group,
    COUNT(*) AS user_item_count,
    SUM(purchased) AS purchase_count,
    ROUND(
        SUM(purchased) / COUNT(*) * 100,
        2
    ) AS purchase_rate

FROM view_group

GROUP BY
    group_order,
    view_group

ORDER BY group_order;