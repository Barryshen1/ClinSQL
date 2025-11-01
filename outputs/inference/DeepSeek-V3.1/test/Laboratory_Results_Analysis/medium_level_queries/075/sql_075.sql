WITH cohort AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.subject_id = adm.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.subject_id = diag.subject_id AND adm.hadm_id = diag.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 41 AND 51
    AND diag.icd_version = 10
    AND (diag.icd_code LIKE 'R07.9' OR diag.icd_code LIKE 'I21%')
),
first_troponin AS (
  SELECT 
    le.subject_id,
    le.hadm_id,
    le.valuenum AS troponin_value,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN cohort c
    ON le.subject_id = c.subject_id AND le.hadm_id = c.hadm_id
  WHERE le.itemid = 51003  -- Troponin T
    AND le.valuenum IS NOT NULL
)
SELECT 
  CASE 
    WHEN troponin_value <= 0.01 THEN 'Normal'
    WHEN troponin_value <= 0.03 THEN 'Borderline'
    ELSE 'Elevated'
  END AS category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(troponin_value), 3) AS mean,
  ROUND(APPROX_QUANTILES(troponin_value, 2)[OFFSET(1)], 3) AS median,
  ROUND(APPROX_QUANTILES(troponin_value, 4)[OFFSET(1)], 3) AS q1,
  ROUND(APPROX_QUANTILES(troponin_value, 4)[OFFSET(3)], 3) AS q3
FROM first_troponin
WHERE rn = 1
GROUP BY category
ORDER BY category;