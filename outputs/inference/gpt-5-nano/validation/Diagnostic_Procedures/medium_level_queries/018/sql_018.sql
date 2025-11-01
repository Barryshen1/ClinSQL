WITH eligible AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON diag.subject_id = a.subject_id AND diag.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
    AND (
      (diag.icd_version = 9 AND diag.icd_code IN ('430','431','432','432.0','432.1','432.9'))
      OR
      (diag.icd_version = 10 AND (diag.icd_code LIKE 'I60%' OR diag.icd_code LIKE 'I61%' OR diag.icd_code LIKE 'I62%'))
    )
),

-- Step 2: Find admissions that had ultrasounds during the admission
ultrasound_hadm AS (
  SELECT DISTINCT e.hadm_id
  FROM eligible e
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.hadm_id = e.hadm_id
   AND ce.charttime BETWEEN e.admittime AND e.dischtime
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON di.itemid = ce.itemid
  WHERE LOWER(di.label) LIKE '%ultrasound%'
),

-- Step 3: Count ultrasounds per admission (0 if none)
ultrasound_counts AS (
  SELECT h.hadm_id,
         COUNT(*) AS ultrasound_count
  FROM ultrasound_hadm h
  GROUP BY h.hadm_id
),

-- Step 4: Build a base table of eligible admissions with LOS and ultrasound counts (0 where none)
base AS (
  SELECT
    e.hadm_id,
    COALESCE(uc.ultrasound_count, 0) AS ultrasound_count,
    DATE_DIFF(DATE(e.dischtime), DATE(e.admittime), DAY) AS stay_days
  FROM eligible e
  LEFT JOIN ultrasound_counts uc
    ON uc.hadm_id = e.hadm_id
)

-- Step 5: Compute mean, min, max ultrasound counts by LOS buckets (1-4 days vs 5-7 days)
SELECT
  CASE
    WHEN stay_days BETWEEN 1 AND 4 THEN '1-4'
    WHEN stay_days BETWEEN 5 AND 7 THEN '5-7'
    ELSE NULL
  END AS stay_bucket,
  AVG(ultrasound_count) AS mean_ultrasounds,
  MIN(ultrasound_count) AS min_ultrasounds,
  MAX(ultrasound_count) AS max_ultrasounds
FROM base
WHERE stay_days BETWEEN 1 AND 7
  AND stay_days IS NOT NULL
  AND (stay_days BETWEEN 1 AND 4 OR stay_days BETWEEN 5 AND 7)
GROUP BY stay_bucket
ORDER BY stay_bucket;