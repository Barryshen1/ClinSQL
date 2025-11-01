WITH dka_cohort AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    pat.dod,
    -- Check for AKI during this admission
    MAX(CASE WHEN diag.icd_code LIKE 'N17%' THEN 1 ELSE 0 END) AS aki,
    -- Check for ARDS during this admission
    MAX(CASE WHEN diag.icd_code = 'J80' THEN 1 ELSE 0 END) AS ards
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 59 AND 69
    AND (d.icd_code LIKE 'E10.1%' OR d.icd_code LIKE 'E11.1%' OR d.icd_code LIKE 'E13.1%')
  GROUP BY adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime, pat.dod
),
control_cohort AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    pat.dod,
    -- Check for AKI during this admission
    MAX(CASE WHEN diag.icd_code LIKE 'N17%' THEN 1 ELSE 0 END) AS aki,
    -- Check for ARDS during this admission
    MAX(CASE WHEN diag.icd_code = 'J80' THEN 1 ELSE 0 END) AS ards
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  LEFT JOIN (
    -- Subquery to find DKA diagnoses
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
      ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
    WHERE d.icd_code LIKE 'E10.1%' OR d.icd_code LIKE 'E11.1%' OR d.icd_code LIKE 'E13.1%'
  ) dka
    ON adm.hadm_id = dka.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 59 AND 69
    AND dka.hadm_id IS NULL  -- Exclude DKA patients
  GROUP BY adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime, pat.dod
)
SELECT
  'DKA' AS cohort,
  COUNT(*) AS num_admissions,
  NULL AS mean_risk_score,  -- Placeholder since risk score is not defined
  -- 30-day mortality
  ROUND(100 * AVG(CASE WHEN dod IS NOT NULL AND DATE_DIFF(dod, admittime, DAY) <= 30 THEN 1 ELSE 0 END), 2) AS mortality_30d_percent,
  -- AKI rate
  ROUND(100 * AVG(aki), 2) AS aki_rate_percent,
  -- ARDS rate
  ROUND(100 * AVG(ards), 2) AS ards_rate_percent,
  -- Average LOS for survivors (those who didn't die in hospital or within 30 days)
  ROUND(AVG(CASE WHEN dod IS NULL OR DATE_DIFF(dod, admittime, DAY) > 30 THEN DATE_DIFF(dischtime, admittime, DAY) END), 2) AS avg_los_survivors_days
FROM dka_cohort

UNION ALL

SELECT
  'Control' AS cohort,
  COUNT(*) AS num_admissions,
  NULL AS mean_risk_score,
  ROUND(100 * AVG(CASE WHEN dod IS NOT NULL AND DATE_DIFF(dod, admittime, DAY) <= 30 THEN 1 ELSE 0 END), 2) AS mortality_30d_percent,
  ROUND(100 * AVG(aki), 2) AS aki_rate_percent,
  ROUND(100 * AVG(ards), 2) AS ards_rate_percent,
  ROUND(AVG(CASE WHEN dod IS NULL OR DATE_DIFF(dod, admittime, DAY) > 30 THEN DATE_DIFF(dischtime, admittime, DAY) END), 2) AS avg_los_survivors_days
FROM control_cohort;