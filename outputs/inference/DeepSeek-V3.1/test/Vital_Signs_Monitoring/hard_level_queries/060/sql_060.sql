WITH cohort AS (
  -- Get all male ICU patients aged 78-88
  SELECT 
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id,
    ie.los AS icu_los,
    adm.hospital_expire_flag,
    -- Check if HHS diagnosis exists
    CASE WHEN diag.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_hhs
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON ie.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
  LEFT JOIN (
    -- HHS diagnosis: ICD9: 250.2x; ICD10: E11.00, E13.00
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
      (icd_version = 9 AND icd_code LIKE '2502%') OR
      (icd_version = 10 AND icd_code IN ('E1100', 'E1300'))
    ) diag
    ON ie.hadm_id = diag.hadm_id
  WHERE 
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 78 AND 88
),

-- Group into HHS and control
hhs_group AS (
  SELECT * FROM cohort WHERE has_hhs = 1
),
control_group AS (
  SELECT * FROM cohort WHERE has_hhs = 0
)

-- For HHS group
SELECT 
  'HHS' AS group_name,
  COUNT(*) AS n_patients,
  -- For ICU LOS
  APPROX_QUANTILES(icu_los, 100)[OFFSET(25)] AS los_25perc,
  APPROX_QUANTILES(icu_los, 100)[OFFSET(50)] AS los_median,
  APPROX_QUANTILES(icu_los, 100)[OFFSET(75)] AS los_75perc,
  -- For mortality
  APPROX_QUANTILES(hospital_expire_flag, 100)[OFFSET(50)] AS mortality_median,
  APPROX_QUANTILES(hospital_expire_flag, 100)[OFFSET(25)] AS mortality_25perc,
  APPROX_QUANTILES(hospital_expire_flag, 100)[OFFSET(75)] AS mortality_75perc
FROM hhs_group

UNION ALL

-- For control group
SELECT 
  'Control' AS group_name,
  COUNT(*) AS n_patients,
  APPROX_QUANTILES(icu_los, 100)[OFFSET(25)] AS los_25perc,
  APPROX_QUANTILES(icu_los, 100)[OFFSET(50)] AS los_median,
  APPROX_QUANTILES(icu_los, 100)[OFFSET(75)] AS los_75perc,
  APPROX_QUANTILES(hospital_expire_flag, 100)[OFFSET(50)] AS mortality_median,
  APPROX_QUANTILES(hospital_expire_flag, 100)[OFFSET(25)] AS mortality_25perc,
  APPROX_QUANTILES(hospital_expire_flag, 100)[OFFSET(75)] AS mortality_75perc
FROM control_group;