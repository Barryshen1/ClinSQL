WITH hf_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime, 
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '428%') OR
      (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
    )
),
ckd_flags AS (
  SELECT hadm_id, 
         MAX(1) AS ckd_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '585%')
     OR (icd_version = 10 AND icd_code LIKE 'N18%')
  GROUP BY hadm_id
),
dm_flags AS (
  SELECT hadm_id, 
         MAX(1) AS dm_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '250%')
     OR (icd_version = 10 AND (
       icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR 
       icd_code LIKE 'E12%' OR icd_code LIKE 'E13%' OR icd_code LIKE 'E14%'
     ))
  GROUP BY hadm_id
)
SELECT 
  CASE 
    WHEN los_days < 8 THEN 'LOS<8'
    ELSE 'LOS≥8'
  END AS los_group,
  COUNT(*) AS total_admissions,
  100 * SUM(hospital_expire_flag) / COUNT(*) AS mortality_pct,
  100 * SUM(IFNULL(ckd_flag,0)) / COUNT(*) AS ckd_prevalence_pct,
  100 * SUM(IFNULL(dm_flag,0)) / COUNT(*) AS dm_prevalence_pct
FROM hf_admissions hf
LEFT JOIN ckd_flags ck ON hf.hadm_id = ck.hadm_id
LEFT JOIN dm_flags dm ON hf.hadm_id = dm.hadm_id
GROUP BY los_group
ORDER BY los_group;