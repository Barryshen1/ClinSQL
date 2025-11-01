WITH patient_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    p.gender,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS hosp_los_days,
    CASE WHEN icu.stay_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS icu_status
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON a.hadm_id = icu.hadm_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 77 AND 87
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.admittime <= a.dischtime
),

hf_admissions AS (
  SELECT DISTINCT pa.*
  FROM patient_admissions pa
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON pa.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%heart failure%'
     OR LOWER(dd.long_title) LIKE '%cardiomyopathy%'
     OR (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
     OR (di.icd_version = 9 AND di.icd_code LIKE '428%')
),

comorbidity_flags AS (
  SELECT
    ha.hadm_id,
    ha.icu_status,
    ha.hosp_los_days,
    ha.hospital_expire_flag,
    MAX(CASE
      WHEN (d_icd.icd_version = 10 AND d_icd.icd_code LIKE 'N18%')
        OR (d_icd.icd_version = 9 AND d_icd.icd_code LIKE '585%') THEN 1
      ELSE 0
    END) AS has_ckd,
    MAX(CASE
      WHEN (d_icd.icd_version = 10 AND d_icd.icd_code LIKE 'E11%')
        OR (d_icd.icd_version = 9 AND d_icd.icd_code LIKE '250.%' AND di.seq_num = 1) THEN 1
      ELSE 0
    END) AS has_diabetes
  FROM hf_admissions ha
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON ha.hadm_id = di.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd ON di.icd_code = d_icd.icd_code AND di.icd_version = d_icd.icd_version
  GROUP BY ha.hadm_id, ha.icu_status, ha.hosp_los_days, ha.hospital_expire_flag
),

los_categories AS (
  SELECT
    icu_status,
    CASE
      WHEN hosp_los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN hosp_los_days BETWEEN 4 AND 7 THEN '4-7 days'
      WHEN hosp_los_days >= 8 THEN '>=8 days'
      ELSE NULL
    END AS los_group,
    hospital_expire_flag,
    hosp_los_days,
    has_ckd,
    has_diabetes
  FROM comorbidity_flags
  WHERE hosp_los_days IS NOT NULL
)

SELECT
  icu_status,
  los_group,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_pct,
  APPROX_QUANTILES(hosp_los_days, 2)[OFFSET(1)] AS median_los_days,
  ROUND(100.0 * SUM(has_ckd) / COUNT(*), 2) AS ckd_prevalence_pct,
  ROUND(100.0 * SUM(has_diabetes) / COUNT(*), 2) AS diabetes_prevalence_pct
FROM los_categories
WHERE los_group IS NOT NULL
GROUP BY icu_status, los_group
ORDER BY icu_status, 
  CASE los_group
    WHEN '1-3 days' THEN 1
    WHEN '4-7 days' THEN 2
    WHEN '>=8 days' THEN 3
  END;