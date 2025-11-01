WITH dx_flags AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    MAX(CASE 
          WHEN di.icd_version = 9 AND di.icd_code LIKE '410%' THEN 1
          WHEN di.icd_version = 10 AND (di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%') THEN 1
          ELSE 0 END) AS ami_flag,
    MAX(CASE 
          WHEN di.icd_version = 9 AND (
            di.icd_code LIKE '7855%' OR di.icd_code LIKE '78551%' OR di.icd_code LIKE '78550%' OR di.icd_code LIKE '9980%' -- shock codes ICD9
            ) THEN 1
          WHEN di.icd_version = 10 AND (
            di.icd_code LIKE 'R57%' ) THEN 1
          ELSE 0 END) AS shock_flag,
    MAX(CASE 
          WHEN di.icd_version = 9 AND di.icd_code LIKE '51881%' THEN 1
          WHEN di.icd_version = 9 AND di.icd_code LIKE '51882%' THEN 1
          WHEN di.icd_version = 9 AND di.icd_code LIKE '51884%' THEN 1
          WHEN di.icd_version = 10 AND di.icd_code LIKE 'J96%' THEN 1
          ELSE 0 END) AS resp_fail_flag,
    MAX(CASE 
          WHEN di.icd_version = 9 AND di.icd_code LIKE '585%' THEN 1
          WHEN di.icd_version = 10 AND di.icd_code LIKE 'N18%' THEN 1
          ELSE 0 END) AS ckd_flag,
    MAX(CASE 
          WHEN di.icd_version = 9 AND di.icd_code LIKE '250%' THEN 1
          WHEN di.icd_version = 10 AND (
            di.icd_code LIKE 'E10%' OR di.icd_code LIKE 'E11%' 
            OR di.icd_code LIKE 'E13%' OR di.icd_code LIKE 'E14%'
          ) THEN 1
          ELSE 0 END) AS dm_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  GROUP BY di.subject_id, di.hadm_id
),
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days,
    a.hospital_expire_flag,
    dx.ckd_flag,
    dx.dm_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN dx_flags dx
    ON a.subject_id = dx.subject_id AND a.hadm_id = dx.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 62 AND 72
    AND dx.ami_flag = 1
    AND dx.shock_flag = 0
    AND dx.resp_fail_flag = 0
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
cohort_los AS (
  SELECT
    *,
    CASE WHEN los_days <= 5 THEN '≤5d'
         ELSE '>5d' END AS los_group
  FROM cohort
),
summary AS (
  SELECT
    los_group,
    COUNT(*) AS n_adm,
    SUM(hospital_expire_flag) AS deaths,
    AVG(hospital_expire_flag) AS mort_rate,
    AVG(CASE WHEN ckd_flag = 1 THEN 1 ELSE 0 END) AS ckd_prev,
    AVG(CASE WHEN dm_flag = 1 THEN 1 ELSE 0 END) AS dm_prev
  FROM cohort_los
  GROUP BY los_group
)
SELECT
  s.*,
  ROUND((SELECT mort_rate FROM summary WHERE los_group='>5d') - 
        (SELECT mort_rate FROM summary WHERE los_group='≤5d'), 4) AS abs_mort_diff,
  ROUND((SELECT mort_rate FROM summary WHERE los_group='>5d') / 
        NULLIF((SELECT mort_rate FROM summary WHERE los_group='≤5d'),0), 4) AS rel_mort_ratio
FROM summary s
ORDER BY los_group;