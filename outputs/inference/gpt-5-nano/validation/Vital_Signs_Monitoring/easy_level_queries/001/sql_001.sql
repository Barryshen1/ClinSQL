WITH MAP_FIRST AS (
  -- Gather MAP chart events for ICU stays of interest, with label mapped to MAP
  SELECT i.stay_id,
         c.charttime,
         c.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS c
    ON c.stay_id = i.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON c.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = i.subject_id
  WHERE LOWER(di.label) LIKE '%mean arterial pressure%'
    AND c.charttime BETWEEN i.intime AND i.outtime
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
),
FIRST_MAP AS (
  -- Select the first MAP measurement per ICU stay
  SELECT stay_id,
         valuenum
  FROM (
    SELECT stay_id, charttime, valuenum,
           ROW_NUMBER() OVER (PARTITION BY stay_id ORDER BY charttime) AS rn
    FROM MAP_FIRST
  )
  WHERE rn = 1
)
-- Compute Q1 and Q3, then IQR
SELECT
  q[OFFSET(1)] AS MAP_Q1,
  q[OFFSET(3)] AS MAP_Q3,
  (q[OFFSET(3)] - q[OFFSET(1)]) AS MAP_IQR
FROM (
  SELECT APPROX_QUANTILES(valuenum, 4) AS q
  FROM FIRST_MAP
) t;