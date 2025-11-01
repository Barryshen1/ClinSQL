WITH acs_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 67 AND 77
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND (d.icd_code LIKE '410%' OR d.icd_code IN ('4110', '4111')))
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I20%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I22%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I23%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I24%')
        )
    )
),
first_troponin AS (
  SELECT 
    l.hadm_id,
    l.valuenum AS troponin_value,
    ROW_NUMBER() OVER (
      PARTITION BY l.hadm_id 
      ORDER BY l.charttime
    ) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN acs_admissions a
    ON l.hadm_id = a.hadm_id
  WHERE l.itemid = 50318  -- Troponin T, high sensitivity
    AND l.valuenum IS NOT NULL
),
eligible_admissions AS (
  SELECT 
    ft.hadm_id,
    ft.troponin_value,
    a.subject_id
  FROM first_troponin ft
  INNER JOIN acs_admissions a
    ON ft.hadm_id = a.hadm_id
  WHERE ft.rn = 1
    AND ft.troponin_value > 0.009  -- Female 99th percentile threshold
)
SELECT 
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(hadm_id) AS admission_count,
  AVG(troponin_value) AS mean_troponin,
  APPROX_QUANTILES(troponin_value, 1000)[OFFSET(500)] AS median_troponin,
  APPROX_QUANTILES(troponin_value, 1000)[OFFSET(750)] 
    - APPROX_QUANTILES(troponin_value, 1000)[OFFSET(250)] AS iqr_troponin
FROM eligible_admissions;