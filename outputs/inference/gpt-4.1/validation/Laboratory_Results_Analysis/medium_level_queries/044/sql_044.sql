WITH troponin_t_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),

male_admissions_54_64 AS (
  SELECT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 54 AND 64
),

initial_troponin_t AS (
  SELECT
    ma.subject_id,
    ma.hadm_id,
    l.charttime,
    l.valuenum
  FROM male_admissions_54_64 ma
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON ma.subject_id = l.subject_id AND ma.hadm_id = l.hadm_id
  WHERE l.itemid IN (SELECT itemid FROM troponin_t_items)
    AND l.valueuom = 'ng/mL'
    AND l.valuenum IS NOT NULL
),

first_troponin_t_per_admission AS (
  SELECT
    subject_id,
    hadm_id,
    charttime,
    valuenum AS initial_troponin_t
  FROM (
    SELECT
      subject_id,
      hadm_id,
      charttime,
      valuenum,
      ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY charttime ASC) AS rn
    FROM initial_troponin_t
  )
  WHERE rn = 1
    AND valuenum > 0.01
)

SELECT
  COUNT(*) AS n,
  ROUND(AVG(initial_troponin_t), 4) AS mean,
  ROUND(STDDEV(initial_troponin_t), 4) AS sd,
  ROUND(MIN(initial_troponin_t), 4) AS min,
  ROUND(MAX(initial_troponin_t), 4) AS max,
  ROUND(APPROX_QUANTILES(initial_troponin_t, 2)[OFFSET(1)], 4) AS median,
  ROUND(APPROX_QUANTILES(initial_troponin_t, 4)[OFFSET(1)], 4) AS percentile_25,
  ROUND(APPROX_QUANTILES(initial_troponin_t, 4)[OFFSET(3)], 4) AS percentile_75
FROM first_troponin_t_per_admission
;