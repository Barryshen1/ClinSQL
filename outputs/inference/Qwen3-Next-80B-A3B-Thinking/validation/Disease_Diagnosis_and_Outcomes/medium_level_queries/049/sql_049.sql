WITH diagnoses_flags AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    MAX(CASE WHEN d.icd_code IN ('I21.0', 'I21.1', 'I21.2', 'I21.3') AND d.icd_version = 10 THEN 1 ELSE 0 END) AS has_stemi,
    MAX(CASE WHEN d.icd_code = 'I21.4' AND d.icd_version = 10 THEN 1 ELSE 0 END) AS has_nstemi,
    MAX(CASE WHEN d.icd_code LIKE 'N18%' AND d.icd_version = 10 THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN (d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E13%' OR d.icd_code LIKE 'E14%') AND d.icd_version = 10 THEN 1 ELSE 0 END) AS has_diabetes
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  GROUP BY d.subject_id, d.hadm_id
)
SELECT
  CASE
    WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 2 THEN '1-2'
    WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 3 AND 5 THEN '3-5'
    WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 6 AND 9 THEN '6-9'
    ELSE '>=10'
  END AS los_group,
  CASE
    WHEN (df.has_ckd + df.has_diabetes) <= 1 THEN '0-1'
    WHEN (df.has_ckd + df.has_diabetes) = 2 THEN '2'
    ELSE '>=3'
  END AS comorbidity_group,
  ROUND(SUM(a.hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_rate,
  COUNT(*) AS n,
  ROUND(SUM(df.has_ckd) * 100.0 / COUNT(*), 2) AS ckd_prevalence,
  ROUND(SUM(df.has_diabetes) * 100.0 / COUNT(*), 2) AS diabetes_prevalence
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
LEFT JOIN diagnoses_flags df ON a.subject_id = df.subject_id AND a.hadm_id = df.hadm_id
WHERE
  p.gender = 'M'
  AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 51 AND 61
  AND (df.has_stemi = 1 OR df.has_nstemi = 1)
GROUP BY los_group, comorbidity_group;