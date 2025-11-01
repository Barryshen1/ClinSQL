WITH eligible_admissions AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 58 AND 68
    AND a.dischtime IS NOT NULL
    AND a.hadm_id IS NOT NULL
),
procedure_counts AS (
  SELECT 
    pr.hadm_id, 
    COUNT(*) AS num_procs
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
    ON pr.icd_code = d.icd_code 
    AND pr.icd_version = d.icd_version
  INNER JOIN eligible_admissions ea 
    ON pr.hadm_id = ea.hadm_id
  WHERE LOWER(d.long_title) LIKE '%radiography%'
     OR LOWER(d.long_title) LIKE '%x-ray%'
     OR LOWER(d.long_title) LIKE '%ct%'
     OR LOWER(d.long_title) LIKE '%computed tomography%'
     OR LOWER(d.long_title) LIKE '%tomography%'
  GROUP BY pr.hadm_id
)
SELECT 
  CASE 
    WHEN ea.los BETWEEN 1 AND 4 THEN '1-4 days' 
    ELSE '5-7 days' 
  END AS los_group,
  COUNT(DISTINCT ea.subject_id) AS patient_count,
  COUNT(*) AS admission_count,
  AVG(COALESCE(pc.num_procs, 0)) AS mean_procs_per_admission
FROM eligible_admissions ea
LEFT JOIN procedure_counts pc 
  ON ea.hadm_id = pc.hadm_id
WHERE ea.los BETWEEN 1 AND 7
GROUP BY los_group
ORDER BY CASE WHEN los_group = '1-4 days' THEN 1 ELSE 2 END;