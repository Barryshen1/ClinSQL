WITH cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    p.gender, 
    p.anchor_age,
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    MAX(CASE WHEN (
      (d.icd_version = 9 AND d.icd_code LIKE '428%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
    ) THEN 1 ELSE 0 END) AS has_hf,
    MAX(CASE WHEN (
      (d.icd_version = 9 AND d.icd_code LIKE '585%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'N18%')
    ) THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN (
      (d.icd_version = 9 AND d.icd_code LIKE '250%')
      OR (d.icd_version = 10 AND (d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%'))
    ) THEN 1 ELSE 0 END) AS has_dm
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.dischtime IS NOT NULL
  GROUP BY 
    a.subject_id, a.hadm_id, p.gender, p.anchor_age, 
    a.admittime, a.dischtime, a.hospital_expire_flag
  HAVING has_hf = 1
),
los_cohort AS (
  SELECT 
    *,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days,
    CASE 
      WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) < 8 THEN '<8 days' 
      ELSE '≥8 days' 
    END AS los_group
  FROM cohort
)
SELECT 
  los_group,
  COUNT(*) AS total_admissions,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_pct,
  ROUND(AVG(has_ckd) * 100, 2) AS ckd_prevalence_pct,
  ROUND(AVG(has_dm) * 100, 2) AS diabetes_prevalence_pct
FROM los_cohort
GROUP BY los_group
ORDER BY 
  CASE WHEN los_group = '<8 days' THEN 1 ELSE 2 END;