WITH platelet_items AS (
  -- Identify lab itemids that correspond to platelet measurements
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%platelet%'
),

sepsis_admissions AS (
  -- Admissions that have a diagnosis with "sepsis" in the diagnosis description
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id AND a.subject_id = d.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE LOWER(COALESCE(dd.long_title, '')) LIKE '%sepsis%'
),

cohort_admissions AS (
  -- Filter to female patients aged 76
  SELECT s.subject_id, s.hadm_id, s.admittime
  FROM sepsis_admissions s
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age = 76
),

hadm_platelet_avg AS (
  -- For each admission in the cohort, compute the mean platelet value in first 24 hours
  SELECT
    c.subject_id,
    c.hadm_id,
    AVG(le.valuenum) AS avg_platelet_first24h
  FROM cohort_admissions c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.hadm_id = le.hadm_id
  JOIN platelet_items pi
    ON le.itemid = pi.itemid
  WHERE le.valuenum IS NOT NULL
    AND le.valuenum > 0
    AND le.charttime >= c.admittime
    AND le.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
  GROUP BY c.subject_id, c.hadm_id
)

-- Compute exact median from the ordered array of per-admission averages
SELECT
  CASE
    WHEN n = 0 THEN NULL
    WHEN MOD(n, 2) = 1 THEN arr[OFFSET((n - 1) / 2)]
    ELSE (arr[OFFSET(n / 2 - 1)] + arr[OFFSET(n / 2)]) / 2.0
  END AS median_platelet_avg_first24h,
  n AS admissions_in_cohort
FROM (
  SELECT ARRAY_AGG(avg_platelet_first24h ORDER BY avg_platelet_first24h) AS arr,
         COUNT(*) AS n
  FROM hadm_platelet_avg
);