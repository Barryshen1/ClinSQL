WITH aki_admissions AS (
  SELECT DISTINCT adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm 
    ON p.subject_id = adm.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
    ON adm.hadm_id = diag.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
    AND (
      (diag.icd_version = 9 AND diag.icd_code LIKE '584%') 
      OR 
      (diag.icd_version = 10 AND diag.icd_code LIKE 'N17%')
    )
)
SELECT 
  ROUND(APPROX_QUANTILES(icu.los, 100)[OFFSET(25)], 2) AS percentile_25_icu_los_days
FROM aki_admissions
INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu 
  ON aki_admissions.hadm_id = icu.hadm_id;