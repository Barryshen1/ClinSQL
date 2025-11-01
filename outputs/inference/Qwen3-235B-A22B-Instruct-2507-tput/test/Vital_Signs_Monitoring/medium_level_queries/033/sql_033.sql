WITH patient_stays AS (
  SELECT 
    p.subject_id,
    s.stay_id,
    s.hadm_id,
    s.intime,
    s.outtime
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays s
    ON p.subject_id = s.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age >= 62
    AND p.anchor_age <= 72
),
heart_rate_data AS (
  SELECT 
    ce.stay_id,
    AVG(ce.valuenum) AS mean_hr
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.d_items di
    ON ce.itemid = di.itemid
  WHERE UPPER(di.label) = 'HEART RATE'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0  -- exclude erroneous values
  GROUP BY ce.stay_id
),
mi_diagnoses AS (
  SELECT DISTINCT
    di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE di.icd_version = 10
    AND d.icd_code LIKE 'I21%'
    OR d.icd_code LIKE 'I22%'
),
stay_with_hr_mi AS (
  SELECT 
    ps.stay_id,
    ps.hadm_id,
    hrd.mean_hr,
    CASE
      WHEN hrd.mean_hr < 60 THEN '<60'
      WHEN hrd.mean_hr BETWEEN 60 AND 99 THEN '60-99'
      WHEN hrd.mean_hr BETWEEN 100 AND 119 THEN '100-119'
      WHEN hrd.mean_hr >= 120 THEN '>=120'
      ELSE NULL
    END AS hr_category,
    CASE WHEN mi.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_mi
  FROM patient_stays ps
  INNER JOIN heart_rate_data hrd
    ON ps.stay_id = hrd.stay_id
  LEFT JOIN mi_diagnoses mi
    ON ps.hadm_id = mi.hadm_id
  WHERE hrd.mean_hr IS NOT NULL
)
SELECT
  hr_category,
  COUNT(*) AS stay_count,
  ROUND(100.0 * SUM(has_mi) / COUNT(*), 2) AS percent_with_acute_mi
FROM stay_with_hr_mi
WHERE hr_category IS NOT NULL
GROUP BY hr_category
ORDER BY MIN(CASE hr_category
  WHEN '<60' THEN 1
  WHEN '60-99' THEN 2
  WHEN '100-119' THEN 3
  WHEN '>=120' THEN 4
END);