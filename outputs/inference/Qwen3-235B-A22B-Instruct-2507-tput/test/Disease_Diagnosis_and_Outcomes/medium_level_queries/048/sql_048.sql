WITH patient_admissions AS (
  SELECT
    a.hadm_id,
    p.subject_id,
    p.gender,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 68 AND 78
),
hf_admissions AS (
  SELECT DISTINCT
    pa.hadm_id
  FROM patient_admissions pa
  JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON pa.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.icd_version = 10
    AND d.icd_code LIKE 'I50%'
),
comorbidity_flags AS (
  SELECT
    pa.hadm_id,
    pa.los_days,
    pa.hospital_expire_flag,
    MAX(CASE WHEN d.icd_code LIKE 'N18%' THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN d.icd_code IN ('E11', 'E10', 'E13') 
              OR d.icd_code LIKE 'E11.%' OR d.icd_code LIKE 'E10.%' OR d.icd_code LIKE 'E13.%' THEN 1 ELSE 0 END) AS has_diabetes
  FROM patient_admissions pa
  JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON pa.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.icd_version = 10
  GROUP BY pa.hadm_id, pa.los_days, pa.hospital_expire_flag
),
hf_with_comorbidities AS (
  SELECT
    cf.hadm_id,
    cf.los_days,
    cf.hospital_expire_flag,
    cf.has_ckd,
    cf.has_diabetes,
    CASE WHEN cf.los_days < 8 THEN '<8 days' ELSE '>=8 days' END AS los_group
  FROM comorbidity_flags cf
  INNER JOIN hf_admissions hf
    ON cf.hadm_id = hf.hadm_id
)
SELECT
  los_group,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_rate_pct,
  ROUND(AVG(has_ckd) * 100, 2) AS ckd_prevalence_pct,
  ROUND(AVG(has_diabetes) * 100, 2) AS diabetes_prevalence_pct
FROM hf_with_comorbidities
GROUP BY los_group
ORDER BY los_group;