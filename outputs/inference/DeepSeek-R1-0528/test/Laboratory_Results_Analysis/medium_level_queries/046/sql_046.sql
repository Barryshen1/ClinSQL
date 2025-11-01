WITH cohort AS (
  SELECT 
      p.subject_id, 
      p.anchor_age,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
      AND p.anchor_age BETWEEN 83 AND 93
),
ami_admissions AS (
  SELECT DISTINCT
      c.subject_id,
      c.anchor_age,
      c.hadm_id,
      c.admittime,
      c.dischtime,
      c.los_days
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON c.hadm_id = diag.hadm_id
  WHERE 
      (diag.icd_version = 9 AND diag.icd_code LIKE '410%') 
      OR 
      (diag.icd_version = 10 AND (diag.icd_code LIKE 'I21%' OR diag.icd_code LIKE 'I22%'))
),
troponin_events AS (
  SELECT 
      a.hadm_id,
      l.charttime,
      l.valuenum AS troponin_value,
      SAFE_CAST(l.ref_range_upper AS FLOAT64) AS ref_upper,
      ROW_NUMBER() OVER (
          PARTITION BY a.hadm_id 
          ORDER BY l.charttime, l.labevent_id
      ) AS rn
  FROM ami_admissions a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
      ON a.hadm_id = l.hadm_id
  WHERE l.itemid IN (51002, 51003)  -- Troponin T item IDs
      AND l.valuenum IS NOT NULL
      AND SAFE_CAST(l.ref_range_upper AS FLOAT64) IS NOT NULL
      AND l.valuenum > SAFE_CAST(l.ref_range_upper AS FLOAT64)
),
first_troponin AS (
  SELECT 
      hadm_id,
      troponin_value
  FROM troponin_events
  WHERE rn = 1  -- First qualifying troponin per admission
)
SELECT 
    COUNT(*) AS N,
    ROUND(AVG(a.anchor_age), 1) AS mean_age,
    ROUND(AVG(a.los_days), 1) AS mean_los,
    MIN(ft.troponin_value) AS min_troponin,
    MAX(ft.troponin_value) AS max_troponin,
    ROUND(AVG(ft.troponin_value), 1) AS mean_troponin
FROM ami_admissions a
INNER JOIN first_troponin ft
    ON a.hadm_id = ft.hadm_id;