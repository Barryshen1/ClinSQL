WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS icu_flag,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
    ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 52 AND 62
),
comorbidity_and_conditions AS (
  SELECT
    pa.*,
    -- Count of secondary diagnoses as comorbidity burden
    COALESCE(COUNT(CASE WHEN di.seq_num > 1 THEN 1 END) OVER (PARTITION BY pa.hadm_id), 0) AS comorbidity_count,
    -- Flag if CKD (ICD-10 N18*) is present in any diagnosis
    MAX(CASE WHEN di.icd_version = 10 AND di.icd_code LIKE 'N18%' THEN 1 ELSE 0 END) OVER (PARTITION BY pa.hadm_id) AS has_ckd,
    -- Flag if diabetes (ICD-10 E10, E11, E13) is present
    MAX(CASE WHEN di.icd_version = 10 AND SUBSTR(di.icd_code, 1, 3) IN ('E10', 'E11', 'E13') THEN 1 ELSE 0 END) OVER (PARTITION BY pa.hadm_id) AS has_diabetes
  FROM patient_admissions pa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON pa.hadm_id = di.hadm_id
),
tertiles AS (
  SELECT
    *,
    NTILE(3) OVER (ORDER BY comorbidity_count) AS comorbidity_tertile
  FROM comorbidity_and_conditions
),
grouped_data AS (
  SELECT
    icu_flag,
    CASE WHEN los_days <= 5 THEN '≤5 days' ELSE '>5 days' END AS los_group,
    comorbidity_tertile,
    COUNT(*) AS patient_count,
    AVG(hospital_expire_flag) * 100 AS mortality_rate,
    AVG(has_ckd) * 100 AS ckd_prevalence,
    AVG(has_diabetes) * 100 AS diabetes_prevalence
  FROM tertiles
  GROUP BY icu_flag, los_group, comorbidity_tertile
)
SELECT
  icu_flag,
  los_group,
  comorbidity_tertile,
  mortality_rate,
  ckd_prevalence,
  diabetes_prevalence
FROM grouped_data
ORDER BY icu_flag, los_group, comorbidity_tertile;