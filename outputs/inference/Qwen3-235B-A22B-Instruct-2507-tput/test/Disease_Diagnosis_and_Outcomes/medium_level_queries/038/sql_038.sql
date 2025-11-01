WITH heart_failure_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (icd_version = 9 AND icd_code LIKE '428%')
     OR (icd_version = 10 AND icd_code LIKE 'I50%')
),
ckd_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (icd_version = 9 AND icd_code LIKE '585%')
     OR (icd_version = 10 AND icd_code LIKE 'N18%')
),
diabetes_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (icd_version = 9 AND icd_code LIKE '250%')
     OR (icd_version = 10 AND (icd_code LIKE 'E11%' OR icd_code LIKE 'E10%'))
),
patients_with_heart_failure AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  INNER JOIN heart_failure_codes hfc ON di.icd_code = hfc.icd_code
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
),
first_admission AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag,
         ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN patients_with_heart_failure p ON a.subject_id = p.subject_id
),
first_icu_stay AS (
  SELECT i.subject_id, i.stay_id, i.intime, i.outtime, i.los,
         ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN patients_with_heart_failure p ON i.subject_id = p.subject_id
),
patient_los_mortality AS (
  SELECT 
    fa.subject_id,
    fa.hadm_id,
    fa.hospital_expire_flag,
    -- ICU status and LOS
    CASE WHEN fis.stay_id IS NOT NULL THEN 'ICU' ELSE 'non-ICU' END AS icu_status,
    CASE 
      WHEN fis.stay_id IS NOT NULL THEN fis.los
      ELSE DATETIME_DIFF(fa.dischtime, fa.admittime, DAY)
    END AS los_days
  FROM first_admission fa
  LEFT JOIN first_icu_stay fis ON fa.subject_id = fis.subject_id AND fis.rn = 1
  WHERE fa.rn = 1  -- first admission
),
comorbidity_flags AS (
  SELECT 
    p.subject_id,
    MAX(CASE WHEN di.icd_code IN (SELECT icd_code FROM ckd_codes) THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN di.icd_code IN (SELECT icd_code FROM diabetes_codes) THEN 1 ELSE 0 END) AS has_diabetes
  FROM patients_with_heart_failure p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  GROUP BY p.subject_id
),
final_cohort AS (
  SELECT 
    plos.icu_status,
    CASE WHEN plos.los_days < 8 THEN '<8' ELSE '>=8' END AS los_group,
    AVG(CAST(plos.hospital_expire_flag AS FLOAT64)) * 100 AS mortality_rate,
    AVG(CAST(cf.has_ckd AS FLOAT64)) * 100 AS ckd_prevalence,
    AVG(CAST(cf.has_diabetes AS FLOAT64)) * 100 AS diabetes_prevalence
  FROM patient_los_mortality plos
  INNER JOIN comorbidity_flags cf ON plos.subject_id = cf.subject_id
  GROUP BY plos.icu_status, los_group
)
SELECT * FROM final_cohort
ORDER BY icu_status, los_group;