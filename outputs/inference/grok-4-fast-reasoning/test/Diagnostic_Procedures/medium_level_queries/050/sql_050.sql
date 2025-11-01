WITH adm AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    p.gender, 
    p.anchor_age,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' 
    AND p.anchor_age BETWEEN 90 AND 100
),
imaging_procs AS (
  SELECT 
    pi.hadm_id, 
    COUNT(*) AS num_imaging_procs
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip 
    ON pi.icd_code = dip.icd_code 
    AND pi.icd_version = dip.icd_version
  WHERE (
    (pi.icd_version = 9 
      AND pi.icd_code LIKE '87%')
    OR 
    (pi.icd_version = 10 AND pi.icd_code LIKE 'B%')
  )
  GROUP BY pi.hadm_id
)
SELECT 
  CASE 
    WHEN los_days BETWEEN 1 AND 3 THEN '1-3 day stays'
    ELSE '4-7 day stays'
  END AS stay_group,
  AVG(COALESCE(ip.num_imaging_procs, 0)) AS mean_procedures_per_admission,
  MIN(COALESCE(ip.num_imaging_procs, 0)) AS min_procedures_per_admission,
  MAX(COALESCE(ip.num_imaging_procs, 0)) AS max_procedures_per_admission
FROM adm
LEFT JOIN imaging_procs ip 
  ON adm.hadm_id = ip.hadm_id
WHERE los_days BETWEEN 1 AND 7
GROUP BY stay_group
ORDER BY 
  CASE 
    WHEN stay_group = '1-3 day stays' THEN 1 
    ELSE 2 
  END;