WITH imaging AS (
  SELECT 
    h.hadm_id, 
    COUNT(*) AS num_scans
  FROM 
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d 
    ON h.hcpcs_cd = d.code
  WHERE 
    LOWER(d.short_description) LIKE '%ct%' 
    OR LOWER(d.long_description) LIKE '%ct%' 
    OR LOWER(d.short_description) LIKE '%computed tomography%'
    OR LOWER(d.short_description) LIKE '%x-ray%' 
    OR LOWER(d.short_description) LIKE '%radiograph%' 
    OR LOWER(d.long_description) LIKE '%x-ray%'
  GROUP BY 
    h.hadm_id
),
lgib_class AS (
  SELECT DISTINCT 
    di.hadm_id,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di2 
        WHERE di2.hadm_id = di.hadm_id 
          AND di2.seq_num = 1
          AND (
            (di2.icd_version = '9' AND di2.icd_code IN ('562.12', '569.3', '569.5', '578.1', '578.9'))
            OR (di2.icd_version = '10' AND di2.icd_code IN ('K92.2', 'K62.5', 'K57.81', 'K57.91'))
          )
      ) THEN 'Primary'
      ELSE 'Secondary'
    END AS diagnosis_type
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  WHERE 
    (
      (di.icd_version = '9' AND di.icd_code IN ('562.12', '569.3', '569.5', '578.1', '578.9'))
      OR (di.icd_version = '10' AND di.icd_code IN ('K92.2', 'K62.5', 'K57.81', 'K57.91'))
    )
)
SELECT 
  CASE 
    WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) <= 3 THEN '1-3 days'
    ELSE '4-7 days'
  END AS los_group,
  lc.diagnosis_type,
  AVG(COALESCE(i.num_scans, 0)) AS mean_radiography_cts_per_admission
FROM 
  `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN 
  `physionet-data.mimiciv_3_1_hosp.patients` p 
  ON a.subject_id = p.subject_id
JOIN 
  lgib_class lc 
  ON a.hadm_id = lc.hadm_id
LEFT JOIN 
  imaging i 
  ON a.hadm_id = i.hadm_id
WHERE 
  p.gender = 'F'
  AND p.anchor_age BETWEEN 71 AND 81
  AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
GROUP BY 
  los_group, 
  lc.diagnosis_type
ORDER BY 
  los_group, 
  lc.diagnosis_type;