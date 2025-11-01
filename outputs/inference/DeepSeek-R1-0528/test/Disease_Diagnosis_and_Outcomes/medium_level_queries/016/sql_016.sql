WITH cohort AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    -- Calculate age at admission
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_adm
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'M'
    AND adm.dischtime IS NOT NULL  -- Ensure completed admissions
    -- Age 40-50 at admission
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 40 AND 50
    -- AMI diagnosis (ICD-9 or ICD-10)
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE 
        diag.hadm_id = adm.hadm_id
        AND (
          (diag.icd_version = 9 AND diag.icd_code LIKE '410%')
          OR (diag.icd_version = 10 AND (diag.icd_code LIKE 'I21%' OR diag.icd_code LIKE 'I22%'))
        )
    )
    -- Exclude shock/respiratory failure
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` exc
      WHERE 
        exc.hadm_id = adm.hadm_id
        AND (
          -- Shock codes
          (exc.icd_version = 9 AND exc.icd_code LIKE '785.5%')
          OR (exc.icd_version = 10 AND exc.icd_code LIKE 'R57%')
          -- Respiratory failure codes
          OR (exc.icd_version = 9 AND exc.icd_code IN ('518.81','518.82','518.84','786.09'))
          OR (exc.icd_version = 10 AND exc.icd_code LIKE 'J96%')
        )
    )
),
cohort_icu AS (
  SELECT 
    c.*,
    -- Flag ICU admission within 24h of hospital admission
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
      WHERE 
        icu.hadm_id = c.hadm_id
        AND icu.intime <= DATETIME_ADD(c.admittime, INTERVAL 1 DAY)
    ) THEN 'ICU day1' ELSE 'No ICU day1' END AS icu_status
  FROM cohort c
)
SELECT 
  CASE 
    WHEN los_days <= 5 THEN 'LOS ≤5' 
    ELSE 'LOS >5' 
  END AS los_group,
  icu_status,
  COUNT(*) AS admissions,
  ROUND(100 * AVG(hospital_expire_flag), 2) AS mortality_percent,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los
FROM cohort_icu
GROUP BY los_group, icu_status
ORDER BY los_group, icu_status;