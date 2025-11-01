WITH age_calc AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Compute age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 49 AND 59
),

sepsis_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  WHERE icd_version = 10 
    AND (
      icd_code LIKE 'A41%' OR 
      icd_code = 'R6520'
    )
),

septic_shock_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  WHERE icd_version = 10 
    AND (
      icd_code = 'R6521' OR 
      LOWER(long_title) LIKE '%septic shock%'
    )
),

admissions_with_sepsis AS (
  SELECT DISTINCT ac.*
  FROM age_calc ac
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON ac.hadm_id = di.hadm_id
  INNER JOIN sepsis_codes sc
    ON di.icd_code = sc.icd_code
    AND di.icd_version = 10
  WHERE ac.hadm_id NOT IN (
    SELECT DISTINCT di2.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di2
    INNER JOIN septic_shock_codes ssc
      ON di2.icd_code = ssc.icd_code
      AND di2.icd_version = 10
  )
),

icu_day1_flag AS (
  SELECT
    aws.*,
    CASE WHEN i.intime IS NOT NULL AND i.intime <= DATETIME_ADD(aws.admittime, INTERVAL 1 DAY) 
      THEN 1 ELSE 0 END AS icu_on_day1
  FROM admissions_with_sepsis aws
  LEFT JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
    ON aws.hadm_id = i.hadm_id
),

comorbidity_flag AS (
  SELECT
    i1.*,
    -- CKD: ICD-10 N18.*
    MAX(CASE WHEN di.icd_version = 10 AND di.icd_code LIKE 'N18%' THEN 1 ELSE 0 END) AS has_ckd,
    -- Diabetes: E10.*, E11.*, E13.*, but E11.* most common for type 2; include all
    MAX(CASE WHEN di.icd_version = 10 AND (di.icd_code LIKE 'E10%' OR di.icd_code LIKE 'E11%' OR di.icd_code LIKE 'E13%') THEN 1 ELSE 0 END) AS has_diabetes
  FROM icu_day1_flag i1
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON i1.hadm_id = di.hadm_id
  GROUP BY i1.subject_id, i1.gender, i1.anchor_age, i1.anchor_year, i1.hadm_id, i1.admittime, i1.dischtime, i1.hospital_expire_flag, i1.age_at_admit, i1.icu_on_day1
),

los_group AS (
  SELECT
    *,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los_days,
    CASE WHEN DATETIME_DIFF(dischtime, admittime, DAY) <= 5 THEN '≤5 days' ELSE '>5 days' END AS los_group
  FROM comorbidity_flag
),

summary AS (
  SELECT
    los_group,
    CASE WHEN icu_on_day1 = 1 THEN 'ICU day 1' ELSE 'non-ICU day 1' END AS icu_day1_group,
    COUNT(*) AS n,
    AVG(hospital_expire_flag) * 100 AS mortality_pct,
    AVG(has_ckd) * 100 AS ckd_pct,
    AVG(has_diabetes) * 100 AS diabetes_pct
  FROM los_group
  GROUP BY los_group, icu_on_day1
)

SELECT
  los_group,
  icu_day1_group,
  n,
  ROUND(mortality_pct, 2) AS mortality_pct,
  ROUND(ckd_pct, 2) AS ckd_pct,
  ROUND(diabetes_pct, 2) AS diabetes_pct
FROM summary
ORDER BY los_group, 
         CASE WHEN icu_day1_group = 'ICU day 1' THEN 1 ELSE 2 END;