WITH troponin_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),

initial_trop AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  JOIN troponin_items AS ti
    ON le.itemid = ti.itemid
  WHERE le.valuenum IS NOT NULL
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime ASC) = 1
),

cohort AS (
  SELECT
    it.valuenum
  FROM initial_trop AS it
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON it.subject_id = adm.subject_id
   AND it.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON it.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 54 AND 64
    AND it.valuenum > 0.01
),

metrics AS (
  SELECT
    COUNT(*)          AS n,
    AVG(valuenum)     AS mean,
    STDDEV_POP(valuenum) AS stddev,
    MIN(valuenum)     AS min,
    MAX(valuenum)     AS max
  FROM cohort
),

quant AS (
  SELECT
    APPROX_QUANTILES(valuenum, 4) AS quantiles
  FROM cohort
)

SELECT
  m.n,
  m.mean,
  m.stddev,
  m.min,
  m.max,
  q.quantiles[OFFSET(1)] AS p25,
  q.quantiles[OFFSET(2)] AS median,
  q.quantiles[OFFSET(3)] AS p75
FROM metrics AS m
CROSS JOIN quant AS q;