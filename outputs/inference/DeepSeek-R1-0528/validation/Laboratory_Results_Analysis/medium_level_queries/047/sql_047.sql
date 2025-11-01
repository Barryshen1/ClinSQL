WITH acs_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 67 AND 77
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE diag.subject_id = adm.subject_id
        AND diag.hadm_id = adm.hadm_id
        AND (
          (diag.icd_version = 9 AND (diag.icd_code LIKE '410%' OR diag.icd_code IN ('4111', '41181')))
          OR 
          (diag.icd_version = 10 AND (diag.icd_code LIKE 'I21%' OR diag.icd_code LIKE 'I22%' OR diag.icd_code = 'I200'))
        )
    )
),
first_troponin AS (
  SELECT 
    aa.subject_id,
    aa.hadm_id,
    l.valuenum,
    l.valueuom,
    SAFE_CAST(l.ref_range_upper AS FLOAT64) AS ref_upper_numeric,  -- Fixed: direct cast
    ROW_NUMBER() OVER (PARTITION BY aa.hadm_id ORDER BY l.charttime) AS rn
  FROM acs_admissions aa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON aa.subject_id = l.subject_id
    AND aa.hadm_id = l.hadm_id
  WHERE l.itemid IN (51003, 51006)  -- Troponin T and High-Sensitivity Troponin T
    AND l.valuenum IS NOT NULL
    AND l.valueuom IN ('ng/mL', 'ng/L')
),
valid_troponin AS (
  SELECT 
    subject_id,
    hadm_id,
    CASE 
      WHEN valueuom = 'ng/mL' THEN valuenum 
      WHEN valueuom = 'ng/L' THEN valuenum / 1000.0 
    END AS troponin_ngml
  FROM first_troponin
  WHERE rn = 1
    AND ref_upper_numeric IS NOT NULL
    AND valuenum > ref_upper_numeric
),
stats AS (
  SELECT 
    COUNT(DISTINCT subject_id) AS patient_count,
    COUNT(DISTINCT hadm_id) AS admission_count,
    AVG(troponin_ngml) AS mean_initial_troponin,
    APPROX_QUANTILES(troponin_ngml, 4) AS quantiles
  FROM valid_troponin
)
SELECT 
  patient_count,
  admission_count,
  mean_initial_troponin,
  quantiles[OFFSET(1)] AS q1,
  quantiles[OFFSET(2)] AS median_initial_troponin,
  quantiles[OFFSET(3)] AS q3,
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS iqr
FROM stats;