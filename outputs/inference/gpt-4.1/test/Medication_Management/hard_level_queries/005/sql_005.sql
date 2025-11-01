WITH hepatic_failure_icds AS (
  -- ICD-9 and ICD-10 codes for hepatic failure
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    (icd_version = 9 AND (
      icd_code LIKE '570%' OR
      icd_code LIKE '5728%' OR
      icd_code LIKE '5722%' OR
      icd_code LIKE '5723%' OR
      icd_code LIKE '5724%' OR
      icd_code LIKE '5729%'
    ))
    OR
    (icd_version = 10 AND (
      icd_code LIKE 'K72%' OR
      icd_code LIKE 'K704%' OR
      icd_code LIKE 'K703%' OR
      icd_code LIKE 'K717%'
    ))
),
hepatic_failure_admissions AS (
  -- Admissions for male patients aged 43-53 with hepatic failure
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    pat.anchor_age,
    pat.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  JOIN hepatic_failure_icds icd
    ON diag.icd_code = icd.icd_code AND diag.icd_version = icd.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 43 AND 53
),
med_complexity AS (
  -- Medication complexity score: count unique drugs in first 72h
  SELECT
    hfa.subject_id,
    hfa.hadm_id,
    hfa.admittime,
    hfa.dischtime,
    hfa.hospital_expire_flag,
    hfa.anchor_age,
    COUNT(DISTINCT LOWER(TRIM(prx.drug))) AS med_complexity_score
  FROM hepatic_failure_admissions hfa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` prx
    ON hfa.hadm_id = prx.hadm_id
    AND prx.starttime >= hfa.admittime
    AND prx.starttime < DATETIME_ADD(hfa.admittime, INTERVAL 72 HOUR)
    AND prx.drug IS NOT NULL
  GROUP BY hfa.subject_id, hfa.hadm_id, hfa.admittime, hfa.dischtime, hfa.hospital_expire_flag, hfa.anchor_age
),
los_and_readmission AS (
  -- Calculate LOS and 30-day readmission
  SELECT
    mc.*,
    SAFE_DIVIDE(TIMESTAMP_DIFF(mc.dischtime, mc.admittime, SECOND), 86400) AS los_days,
    -- 30-day readmission: does another admission for same subject start within 30 days after discharge?
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm2
      WHERE adm2.subject_id = mc.subject_id
        AND adm2.admittime > mc.dischtime
        AND adm2.admittime <= DATETIME_ADD(mc.dischtime, INTERVAL 30 DAY)
    ) THEN 1 ELSE 0 END AS readmit_30d
  FROM med_complexity mc
),
quintiles AS (
  -- Assign quintiles based on med_complexity_score
  SELECT
    *,
    NTILE(5) OVER (ORDER BY med_complexity_score) AS quintile
  FROM los_and_readmission
)
SELECT
  quintile,
  COUNT(*) AS n,
  MIN(med_complexity_score) AS min_score,
  MAX(med_complexity_score) AS max_score,
  ROUND(AVG(med_complexity_score),2) AS mean_score,
  ROUND(AVG(los_days),2) AS mean_los_days,
  ROUND(100 * AVG(CAST(hospital_expire_flag AS FLOAT64)),2) AS in_hosp_mortality_pct,
  ROUND(100 * AVG(CAST(readmit_30d AS FLOAT64)),2) AS readmit_30d_pct
FROM quintiles
GROUP BY quintile
ORDER BY quintile;