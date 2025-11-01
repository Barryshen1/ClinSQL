WITH demographic AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 54 AND 64
),
troponin_events AS (
  SELECT 
    le.hadm_id,
    le.charttime,  -- Added to enable ordering by measurement time
    le.valuenum AS troponin_value
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE 
    LOWER(dli.label) LIKE '%troponin t%'
    AND le.valuenum IS NOT NULL
),
first_troponin AS (
  SELECT 
    hadm_id,
    troponin_value,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY le.charttime) AS rn
  FROM troponin_events le
),
cohort AS (
  SELECT 
    ft.troponin_value
  FROM demographic d
  INNER JOIN first_troponin ft
    ON d.hadm_id = ft.hadm_id
  WHERE 
    ft.rn = 1
    AND ft.troponin_value > 0.01
)
SELECT 
  COUNT(*) AS n,
  AVG(troponin_value) AS mean,
  STDDEV_SAMP(troponin_value) AS sd,
  MIN(troponin_value) AS min,
  MAX(troponin_value) AS max,
  APPROX_QUANTILES(troponin_value, 1000)[OFFSET(250)] AS p25,
  APPROX_QUANTILES(troponin_value, 1000)[OFFSET(500)] AS median,
  APPROX_QUANTILES(troponin_value, 1000)[OFFSET(750)] AS p75
FROM cohort;