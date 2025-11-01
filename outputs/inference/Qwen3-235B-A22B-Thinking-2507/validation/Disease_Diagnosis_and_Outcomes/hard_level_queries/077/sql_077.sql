WITH cohort AS (
  SELECT 
    adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'M'
    AND (
      (pat.anchor_age >= 88 AND pat.anchor_age <= 89) 
      OR pat.anchor_age = 300
    )
    AND EXISTS (  -- Pneumonia diagnosis
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE 
        diag.hadm_id = adm.hadm_id
        AND (
          (diag.icd_version = 9 AND diag.icd_code BETWEEN '480' AND '486')
          OR (diag.icd_version = 10 AND diag.icd_code >= 'J12' AND diag.icd_code < 'J19')
        )
    )
    AND EXISTS (  -- ICU stay
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
      WHERE icu.hadm_id = adm.hadm_id
    )
),
cohort_details AS (
  SELECT 
    c.hadm_id,
    adm.hospital_expire_flag,
    MAX(CASE  -- AKI flag
      WHEN (diag.icd_version = 9 AND diag.icd_code = '584') 
        OR (diag.icd_version = 10 AND diag.icd_code LIKE 'N17%') 
      THEN 1 ELSE 0 
    END) AS has_aki,
    MAX(CASE  -- ARDS flag
      WHEN (diag.icd_version = 9 AND diag.icd_code = '5185') 
        OR (diag.icd_version = 10 AND diag.icd_code = 'J80') 
      THEN 1 ELSE 0 
    END) AS has_ards,
    MAX(drg.drg_severity) AS drg_severity,  -- Max severity per admission
    CASE  -- Survival days (for decedents only)
      WHEN adm.hospital_expire_flag = 1 
      THEN DATETIME_DIFF(adm.deathtime, adm.admittime, DAY) 
      ELSE NULL 
    END AS survival_days
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON c.hadm_id = adm.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON c.hadm_id = diag.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.drgcodes` drg
    ON c.hadm_id = drg.hadm_id AND drg.drg_type = 'HCFA'
  GROUP BY c.hadm_id, adm.hospital_expire_flag, adm.deathtime, adm.admittime
)
SELECT 
  COUNT(*) AS cohort_size,
  MIN(IF(drg_severity IS NOT NULL, drg_severity, NULL)) AS min_score,
  APPROX_QUANTILES(IF(drg_severity IS NOT NULL, drg_severity, NULL), 100)[OFFSET(25)] AS p25_score,
  APPROX_QUANTILES(IF(drg_severity IS NOT NULL, drg_severity, NULL), 100)[OFFSET(50)] AS median_score,
  APPROX_QUANTILES(IF(drg_severity IS NOT NULL, drg_severity, NULL), 100)[OFFSET(75)] AS p75_score,
  MAX(IF(drg_severity IS NOT NULL, drg_severity, NULL)) AS max_score,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(has_aki) AS aki_rate,
  AVG(has_ards) AS ards_rate,
  APPROX_QUANTILES(survival_days, 100)[OFFSET(50)] AS median_survival_days
FROM cohort_details;