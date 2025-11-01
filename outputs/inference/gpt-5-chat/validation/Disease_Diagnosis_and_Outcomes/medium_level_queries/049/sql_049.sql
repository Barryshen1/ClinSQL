WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.anchor_age,
    pat.gender,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    ROUND(TIMESTAMP_DIFF(adm.dischtime, adm.admittime, HOUR)/24,1) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 51 AND 61
),
mi_flags AS (
  SELECT
    hadm_id,
    MAX(CASE WHEN
        (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^410[0-6]'))
        OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^(I21[0-36]|I22[0-16])'))
      THEN 1 ELSE 0 END) AS stemi_flag,
    MAX(CASE WHEN
        (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^4107'))
        OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^(I214|I222)'))
      THEN 1 ELSE 0 END) AS nstemi_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
comorbid_flags AS (
  SELECT
    hadm_id,
    MAX(CASE WHEN
        (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^585'))
        OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^N18'))
      THEN 1 ELSE 0 END) AS ckd_flag,
    MAX(CASE WHEN
        (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^250'))
        OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^E1[0-4]'))
      THEN 1 ELSE 0 END) AS dm_flag,
    COUNT(DISTINCT CASE
      WHEN NOT (
         (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^410'))
         OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^(I21|I22)'))
      )
      THEN icd_code END) AS n_comorbid
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
merged AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    CASE
      WHEN m.stemi_flag = 1 THEN 'STEMI'
      WHEN m.nstemi_flag = 1 THEN 'NSTEMI'
      ELSE NULL
    END AS mi_type,
    CASE
      WHEN c.los_days BETWEEN 1 AND 2 THEN '1-2'
      WHEN c.los_days BETWEEN 3 AND 5 THEN '3-5'
      WHEN c.los_days BETWEEN 6 AND 9 THEN '6-9'
      WHEN c.los_days >= 10 THEN '>=10'
      ELSE NULL
    END AS los_group,
    CASE
      WHEN com.n_comorbid <= 1 THEN '0-1'
      WHEN com.n_comorbid = 2 THEN '2'
      WHEN com.n_comorbid >= 3 THEN '>=3'
      ELSE NULL
    END AS comorb_group,
    c.hospital_expire_flag,
    com.ckd_flag,
    com.dm_flag
  FROM cohort c
  JOIN mi_flags m
    ON c.hadm_id = m.hadm_id
  JOIN comorbid_flags com
    ON c.hadm_id = com.hadm_id
  WHERE (m.stemi_flag = 1 OR m.nstemi_flag = 1)
)
SELECT
  mi_type,
  los_group,
  comorb_group,
  COUNT(*) AS N,
  ROUND(100*AVG(hospital_expire_flag),1) AS mortality_pct,
  ROUND(100*AVG(ckd_flag),1) AS ckd_pct,
  ROUND(100*AVG(dm_flag),1) AS diabetes_pct
FROM merged
GROUP BY mi_type, los_group, comorb_group
ORDER BY mi_type, los_group, comorb_group;