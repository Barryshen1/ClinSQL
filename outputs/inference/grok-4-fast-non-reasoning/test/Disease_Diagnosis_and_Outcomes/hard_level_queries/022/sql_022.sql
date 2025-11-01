WITH aki_codes AS (
  SELECT code FROM UNNEST(['N17', 'N170', 'N171', 'N172', 'N173', 'N174', 'N175', 'N176', 'N178', 'N179', 
                           'N00', 'N01', 'N02', 'N03', 'N04', 'N05', 'N06', 'N07', 'N08', 
                           'T795']) AS code
),
chronic_codes AS (
  SELECT code FROM UNNEST(['I10', 'I11', 'I12', 'I13', 'I14', 'I15', 'I16', 
                           'E10', 'E11', 'E12', 'E13', 'E14', 
                           'I50', 
                           'I20', 'I21', 'I22', 'I23', 'I24', 'I25', 
                           'J44', 
                           'N18', 
                           'C00', 'C01', 'C02', 'C03', 'C04', 'C05', 'C06', 'C07', 'C08', 'C09', 'C10', 'C11', 'C12', 'C13', 'C14', 'C15', 'C16', 'C17', 'C18', 'C19', 'C20', 'C21', 'C22', 'C23', 'C24', 'C25', 'C26', 'D00', 'D01', 'D02', 'D03', 'D04', 'D05', 'D06', 'D07', 'D08', 'D49', 
                           'K70', 'K71', 'K72', 'K73', 'K74', 'K75', 'K76', 'K77', 
                           'I63', 
                           'E66']) AS code  -- Simplified; expand as needed for full chronic list
),
ards_codes AS (
  SELECT code FROM UNNEST(['J80', 'J800', 'J801', 'J802', 'J808', 'J809']) AS code
),
cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.dod,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.anchor_age BETWEEN 40 AND 50
    AND p.gender = 'F'
    AND a.admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT')
    AND a.hospital_expire_flag = 0  -- Exclude in-hospital deaths
    AND EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` daki 
      WHERE daki.subject_id = a.subject_id 
        AND daki.hadm_id = a.hadm_id 
        AND daki.icd_version = '10'
        AND (dak.iicd_code LIKE 'N17%' OR REGEXP_CONTAINS(daki.icd_code, '^N0[0-8]') OR daki.icd_code = 'T795')
    )
),
comorb_ards AS (
  SELECT 
    c.*,
    COUNT(DISTINCT CASE WHEN dc.icd_version = '10' 
      AND NOT (dc.icd_code LIKE 'N17%' OR REGEXP_CONTAINS(dc.icd_code, '^N0[0-8]') OR dc.icd_code = 'T795')  -- Exclude AKI
      AND dc.icd_code IN (SELECT code FROM chronic_codes) 
      THEN dc.icd_code END) AS comorbidities,
    MAX(CASE WHEN da.icd_version = '10' AND da.icd_code IN (SELECT code FROM ards_codes) THEN 1 ELSE 0 END) AS ards_flag
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dc 
    ON c.subject_id = dc.subject_id AND c.hadm_id = dc.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` da 
    ON c.subject_id = da.subject_id AND c.hadm_id = da.hadm_id
  GROUP BY c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.dod, c.anchor_age, c.gender
),
risk_quintiles AS (
  SELECT 
    *,
    5 * comorbidities + (50 * ards_flag) AS risk_score,
    NTILE(5) OVER (ORDER BY 5 * comorbidities + (50 * ards_flag)) AS quintile
  FROM comorb_ards
),
metrics AS (
  SELECT 
    quintile,
    COUNT(*) AS N,
    SAFE_DIVIDE(SUM(CASE WHEN dod IS NOT NULL AND dod <= DATE_ADD(DATE(dischtime), INTERVAL 30 DAY) THEN 1 ELSE 0 END), COUNT(*)) * 100 AS mortality_30d_pct,
    SAFE_DIVIDE(SUM(ards_flag), COUNT(*)) * 100 AS ards_cooccur_pct,
    -- Median LOS for survivors (30-day post-discharge)
    PERCENTILE_CONT(0.5) OVER (PARTITION BY quintile ORDER BY 
      CASE WHEN (dod IS NULL OR dod > DATE_ADD(DATE(dischtime), INTERVAL 30 DAY)) 
           THEN DATE_DIFF(DATE(dischtime), DATE(admittime), DAY) 
           ELSE NULL END
    ) AS median_los_days
  FROM risk_quintiles
  GROUP BY quintile
)
SELECT 
  quintile,
  N,
  ROUND(mortality_30d_pct, 2) AS mortality_30d_pct,
  ROUND(ards_cooccur_pct, 2) AS ards_cooccur_pct,
  ROUND(median_los_days, 2) AS median_los_days
FROM metrics
ORDER BY quintile;