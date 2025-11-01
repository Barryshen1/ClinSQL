WITH eligible_admissions AS (
  SELECT 
    a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 75 AND 85
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2 
      WHERE d2.hadm_id = a.hadm_id 
        AND (
          (d2.icd_version = 9 AND d2.icd_code LIKE '038.%') 
          OR (d2.icd_version = 10 AND d2.icd_code LIKE 'A4[01]%')
        )
    )
    AND NOT EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d3 
      WHERE d3.hadm_id = a.hadm_id 
        AND (
          (d3.icd_version = 9 AND d3.icd_code = '785.52') 
          OR (d3.icd_version = 10 AND d3.icd_code LIKE 'R65.2%')
        )
    )
),
comorbidities AS (
  SELECT 
    ea.hadm_id,
    MAX(CASE WHEN (
      (di.icd_version = 9 AND di.icd_code LIKE '58[2-7].%') 
      OR (di.icd_version = 10 AND di.icd_code LIKE 'N18%')
    ) THEN 1 ELSE 0 END) AS has_CKD,
    MAX(CASE WHEN (
      (di.icd_version = 9 AND di.icd_code LIKE '250.%') 
      OR (di.icd_version = 10 AND di.icd_code LIKE 'E1[0-4]%')
    ) THEN 1 ELSE 0 END) AS has_diabetes,
    MAX(CASE WHEN (
      (di.icd_version = 9 AND di.icd_code = '427.31') 
      OR (di.icd_version = 10 AND di.icd_code LIKE 'I48.%')
    ) THEN 1 ELSE 0 END) AS has_AFib,
    MAX(CASE WHEN (
      (di.icd_version = 9 AND di.icd_code LIKE '40[1-5].%') 
      OR (di.icd_version = 10 AND di.icd_code LIKE 'I1[0-6]%')
    ) THEN 1 ELSE 0 END) AS has_hypertension
  FROM eligible_admissions ea
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON ea.hadm_id = di.hadm_id
  GROUP BY ea.hadm_id
)
SELECT 
  CASE WHEN DATE_DIFF(ea.dischtime, ea.admittime, DAY) <= 5 THEN '<=5 days' ELSE '>5 days' END AS los_group,
  COALESCE(c.has_CKD, 0) AS has_CKD,
  COALESCE(c.has_diabetes, 0) AS has_diabetes,
  COALESCE(c.has_AFib, 0) AS has_AFib,
  COALESCE(c.has_hypertension, 0) AS has_hypertension,
  COUNT(*) AS n_patients,
  SUM(CASE WHEN ea.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS n_deaths,
  ROUND(100.0 * SUM(CASE WHEN ea.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS mortality_pct
FROM eligible_admissions ea
LEFT JOIN comorbidities c ON ea.hadm_id = c.hadm_id
GROUP BY los_group, has_CKD, has_diabetes, has_AFib, has_hypertension
ORDER BY los_group, has_CKD, has_diabetes, has_AFib, has_hypertension;