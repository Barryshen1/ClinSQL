WITH hhs_admissions AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 58 AND 68
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di 
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND (di.long_title LIKE '%hyperosmolar%' OR di.long_title LIKE '%HHS%')
    )
),
ct_procedures AS (
  SELECT 
    hadm_id, 
    COUNT(*) AS procedure_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh 
    ON h.hcpcs_cd = dh.code
  WHERE dh.short_description LIKE '%CT%' 
    OR dh.short_description LIKE '%radiography%'
  GROUP BY hadm_id
)
SELECT 
  CASE 
    WHEN ha.los_days BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN ha.los_days BETWEEN 5 AND 7 THEN '5-7 days'
    ELSE NULL
  END AS los_group,
  COUNT(DISTINCT ha.subject_id) AS patient_count,
  COUNT(DISTINCT ha.hadm_id) AS admission_count,
  AVG(COALESCE(cp.procedure_count, 0)) AS mean_procedures_per_admission
FROM hhs_admissions ha
LEFT JOIN ct_procedures cp 
  ON ha.hadm_id = cp.hadm_id
WHERE ha.los_days BETWEEN 1 AND 7
GROUP BY los_group;