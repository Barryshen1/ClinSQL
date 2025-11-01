WITH hf_patients AS (
  SELECT DISTINCT p.subject_id, p.gender, p.anchor_age, a.hadm_id,
         a.hospital_expire_flag,
         DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
         MAX(CASE WHEN (d.icd_code LIKE '585%' AND d.icd_version = 9) OR (d.icd_code LIKE 'N18%' AND d.icd_version = 10) THEN 1 ELSE 0 END) AS has_ckd,
         MAX(CASE WHEN (d.icd_code LIKE '250%' AND d.icd_version = 9) OR (d.icd_code LIKE 'E1%' AND d.icd_version = 10) THEN 1 ELSE 0 END) AS has_diabetes
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 39 AND 49
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '428%') OR
      (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
    )
  GROUP BY p.subject_id, p.gender, p.anchor_age, a.hadm_id, a.hospital_expire_flag, a.dischtime, a.admittime
),
comorbidity_data AS (
  SELECT hf.subject_id, hf.hadm_id,
         COUNT(DISTINCT 
           CASE 
             WHEN (d.icd_version = 9 AND d.icd_code NOT LIKE '428%') THEN SUBSTR(d.icd_code, 1, 3)
             WHEN (d.icd_version = 10 AND d.icd_code NOT LIKE 'I50%') THEN SUBSTR(d.icd_code, 1, 3)
             ELSE NULL
           END
         ) AS comorbidity_count
  FROM hf_patients hf
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON hf.hadm_id = d.hadm_id
  GROUP BY hf.subject_id, hf.hadm_id
),
with_tertiles AS (
  SELECT *,
         NTILE(3) OVER (ORDER BY comorbidity_count) AS tertile
  FROM comorbidity_data
)
SELECT 
  CASE WHEN los <= 5 THEN '<=5' ELSE '>5' END AS los_group,
  CASE WHEN tertile = 1 THEN 'Low'
       WHEN tertile = 2 THEN 'Med'
       WHEN tertile = 3 THEN 'High' END AS comorbidity_tertile,
  COUNT(*) AS n,
  ROUND(100 * AVG(hospital_expire_flag), 2) AS mortality_percent,
  ROUND(100 * AVG(has_ckd), 2) AS ckd_prevalence,
  ROUND(100 * AVG(has_diabetes), 2) AS diabetes_prevalence
FROM hf_patients hf
INNER JOIN with_tertiles wt ON hf.hadm_id = wt.hadm_id
GROUP BY los_group, comorbidity_tertile
ORDER BY los_group, comorbidity_tertile;