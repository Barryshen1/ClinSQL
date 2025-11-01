WITH base_stays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    pat.gender,
    pat.anchor_age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 48 AND 58
),
hr_first48 AS (
  SELECT
    b.stay_id,
    AVG(e.valuenum) AS avg_hr
  FROM base_stays b
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` e
    ON b.stay_id = e.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON e.itemid = di.itemid
  WHERE di.label = 'Heart Rate'
    AND e.valuenum IS NOT NULL
    AND e.charttime >= b.intime
    AND e.charttime < DATETIME_ADD(b.intime, INTERVAL 48 HOUR)
  GROUP BY b.stay_id
),
aki_first48 AS (
  SELECT
    b.stay_id,
    MAX(CASE WHEN le.valuenum >= 1.5 THEN 1 ELSE 0 END) AS aki_flag
  FROM base_stays b
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON b.subject_id = le.subject_id
    AND b.hadm_id = le.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dlab
    ON le.itemid = dlab.itemid
  WHERE LOWER(dlab.label) LIKE 'creatinine%'
    AND le.valuenum IS NOT NULL
    AND le.charttime >= b.intime
    AND le.charttime < DATETIME_ADD(b.intime, INTERVAL 48 HOUR)
  GROUP BY b.stay_id
),
combined AS (
  SELECT
    b.stay_id,
    hf.avg_hr,
    CASE
      WHEN hf.avg_hr < 60 THEN '<60'
      WHEN hf.avg_hr BETWEEN 60 AND 99 THEN '60-99'
      WHEN hf.avg_hr BETWEEN 100 AND 119 THEN '100-119'
      WHEN hf.avg_hr >= 120 THEN '>=120'
      ELSE 'Unknown'
    END AS hr_category,
    af.aki_flag
  FROM base_stays b
  JOIN hr_first48 hf ON b.stay_id = hf.stay_id
  LEFT JOIN aki_first48 af ON b.stay_id = af.stay_id
)
SELECT
  hr_category,
  COUNT(*) AS stay_count,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER(), 2) AS pct_distribution,
  ROUND(100 * SUM(aki_flag) / COUNT(*), 2) AS aki_rate_pct
FROM combined
GROUP BY hr_category
ORDER BY hr_category;