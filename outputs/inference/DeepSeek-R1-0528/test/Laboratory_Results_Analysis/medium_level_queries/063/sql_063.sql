WITH acs_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'F'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime)) - pat.anchor_year) BETWEEN 84 AND 94
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE 
        adm.hadm_id = diag.hadm_id
        AND (
          (diag.icd_version = 9 AND (diag.icd_code LIKE '410%' OR diag.icd_code IN ('4111', '41181')))
          OR (diag.icd_version = 10 AND (
            diag.icd_code = 'I200' 
            OR diag.icd_code LIKE 'I21%' 
            OR diag.icd_code LIKE 'I22%' 
            OR diag.icd_code LIKE 'I23%' 
            OR diag.icd_code IN ('I240', 'I248', 'I249')
          ))
        )
    )
),
troponin_events AS (
  SELECT 
    le.hadm_id,
    le.charttime,
    le.valuenum AS troponin_value,
    SAFE_CAST(le.ref_range_upper AS FLOAT64) AS uln
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN acs_admissions acs 
    ON le.hadm_id = acs.hadm_id
  WHERE 
    le.itemid = 50911  -- Troponin I
    AND le.valuenum IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
),
first_troponin AS (
  SELECT 
    hadm_id,
    troponin_value,
    uln,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime) AS rn
  FROM troponin_events
),
eligible_admissions AS (
  SELECT 
    hadm_id,
    troponin_value
  FROM first_troponin
  WHERE 
    rn = 1 
    AND troponin_value > uln  -- Exceeds ULN
)
SELECT 
  COUNT(*) AS count,
  AVG(troponin_value) AS mean,
  APPROX_QUANTILES(troponin_value, 4)[OFFSET(2)] AS median,
  APPROX_QUANTILES(troponin_value, 4)[OFFSET(3)] - APPROX_QUANTILES(troponin_value, 4)[OFFSET(1)] AS iqr
FROM eligible_admissions;