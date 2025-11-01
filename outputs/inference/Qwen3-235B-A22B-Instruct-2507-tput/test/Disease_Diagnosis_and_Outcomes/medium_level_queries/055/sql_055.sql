WITH patient_admissions AS (
  SELECT
    p.subject_id,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    -- Calculate age at admission
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 71 AND 81
),

-- Filter for complications of care: ICD-10 codes T80-T88
complication_diagnoses AS (
  SELECT DISTINCT
    di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  WHERE di.icd_version = 10
    AND SUBSTR(di.icd_code, 1, 3) IN ('T80','T81','T82','T83','T84','T85','T86','T87','T88')
),

-- ICU status: had at least one ICU stay
icu_status AS (
  SELECT DISTINCT
    subject_id,
    hadm_id,
    1 AS had_icu
  FROM `physionet-data.mimiciv_3_1_icu`.icustays
),

-- Hospital LOS in days
admission_los AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    pa.gender,
    pa.age_at_admit,
    pa.admittime,
    pa.dischtime,
    pa.hospital_expire_flag,
    DATETIME_DIFF(pa.dischtime, pa.admittime, HOUR) / 24.0 AS los_days
  FROM patient_admissions pa
  INNER JOIN complication_diagnoses cd
    ON pa.hadm_id = cd.hadm_id
),

-- Add ICU flag to admissions
admissions_with_icu AS (
  SELECT
    alo.*,
    COALESCE(icu.had_icu, 0) AS had_icu
  FROM admission_los alo
  LEFT JOIN icu_status icu
    ON alo.hadm_id = icu.hadm_id
),

-- Define LOS quartiles within ICU and non-ICU groups
quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (PARTITION BY had_icu ORDER BY los_days) AS los_quartile
  FROM admissions_with_icu
),

-- Mechanical ventilation: use procedureevents with itemid = 225468 ('Mechanical Ventilation')
ventilation AS (
  SELECT DISTINCT
    stay_id
  FROM `physionet-data.mimiciv_3_1_icu`.procedureevents
  WHERE itemid = 225468  -- Mechanical Ventilation
),

-- Vasopressors: norepinephrine, epinephrine, vasopressin, dopamine, phenylephrine
vasopressors AS (
  SELECT DISTINCT
    stay_id
  FROM `physionet-data.mimiciv_3_1_icu`.inputevents
  WHERE itemid IN (221906, 221289, 222315, 221662, 221749)  -- Known vasopressor itemids
),

-- RRT: CRRT and Dialysis
rrt AS (
  SELECT DISTINCT
    stay_id
  FROM `physionet-data.mimiciv_3_1_icu`.procedureevents
  WHERE itemid IN (225802, 227438)  -- CRRT, Dialysis
),

-- Combine ICU procedures back to admissions via icustays
procedures AS (
  SELECT
    i.hadm_id,
    MAX(CASE WHEN v.stay_id IS NOT NULL THEN 1 ELSE 0 END) AS had_ventilation,
    MAX(CASE WHEN va.stay_id IS NOT NULL THEN 1 ELSE 0 END) AS had_vasopressors,
    MAX(CASE WHEN r.stay_id IS NOT NULL THEN 1 ELSE 0 END) AS had_rrt
  FROM `physionet-data.mimiciv_3_1_icu`.icustays i
  LEFT JOIN ventilation v ON i.stay_id = v.stay_id
  LEFT JOIN vasopressors va ON i.stay_id = va.stay_id
  LEFT JOIN rrt r ON i.stay_id = r.stay_id
  GROUP BY i.hadm_id
),

-- Final dataset with quartiles and procedures
final_cohort AS (
  SELECT
    q.*,
    COALESCE(p.had_ventilation, 0) AS had_ventilation,
    COALESCE(p.had_vasopressors, 0) AS had_vasopressors,
    COALESCE(p.had_rrt, 0) AS had_rrt
  FROM quartiles q
  LEFT JOIN procedures p
    ON q.hadm_id = p.hadm_id
)

-- Aggregate by ICU status and LOS quartile
SELECT
  had_icu,
  los_quartile,
  COUNT(*) AS n_admissions,
  AVG(IF(hospital_expire_flag = 1, 1.0, 0.0)) AS mortality_rate,
  -- Absolute difference vs Q1
  AVG(IF(hospital_expire_flag = 1, 1.0, 0.0)) - 
    FIRST_VALUE(AVG(IF(hospital_expire_flag = 1, 1.0, 0.0))) OVER (PARTITION BY had_icu ORDER BY los_quartile) AS mortality_diff_vs_q1,
  -- Relative difference vs Q1 (risk ratio)
  AVG(IF(hospital_expire_flag = 1, 1.0, 0.0)) / 
    NULLIF(FIRST_VALUE(AVG(IF(hospital_expire_flag = 1, 1.0, 0.0))) OVER (PARTITION BY had_icu ORDER BY los_quartile), 0) AS mortality_rr_vs_q1,
  AVG(CAST(had_ventilation AS FLOAT64)) AS pct_ventilation,
  AVG(CAST(had_vasopressors AS FLOAT64)) AS pct_vasopressors,
  AVG(CAST(had_rrt AS FLOAT64)) AS pct_rrt
FROM final_cohort
GROUP BY had_icu, los_quartile
ORDER BY had_icu, los_quartile;