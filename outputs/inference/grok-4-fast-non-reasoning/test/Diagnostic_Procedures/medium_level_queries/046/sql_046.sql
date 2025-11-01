WITH tia_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    COUNT(DISTINCT pr_icd.icd_code) AS procedure_count
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.subject_id = diag.subject_id AND a.hadm_id = diag.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON diag.icd_code = d_icd.icd_code AND diag.icd_version = d_icd.icd_version
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr_icd
    ON a.subject_id = pr_icd.subject_id AND a.hadm_id = pr_icd.hadm_id
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d_proc
    ON pr_icd.icd_code = d_proc.icd_code AND pr_icd.icd_version = d_proc.icd_version
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND a.deathtime IS NULL
    AND d_icd.icd_code = 'G45.9'
    AND diag.icd_version = 10
    AND (pr_icd.icd_version = 10 OR pr_icd.icd_version IS NULL)  -- For left join
    AND pr_icd.icd_code LIKE 'BWG%' OR pr_icd.icd_code LIKE 'BWH%'  -- CT (BWG) or MRI (BWH)
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
  GROUP BY 
    p.subject_id, a.hadm_id, a.admittime, a.dischtime, los_days
),
los_groups AS (
  SELECT 
    *,
    CASE 
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_group
  FROM tia_admissions
)
SELECT 
  los_group,
  COUNT(DISTINCT hadm_id) AS num_admissions,
  ROUND(AVG(procedure_count), 2) AS mean_procedures_per_admission
FROM los_groups
GROUP BY los_group
ORDER BY 
  CASE los_group 
    WHEN '1-3 days' THEN 1 
    WHEN '4-7 days' THEN 2 
  END;