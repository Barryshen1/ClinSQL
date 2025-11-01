WITH cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 45 AND 55
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_code LIKE 'E11%'
        AND d.icd_version = 10
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_code LIKE 'I50%'
        AND d.icd_version = 10
    )
),

glp1_prescriptions AS (
  SELECT 
    p.hadm_id,
    MAX(CASE 
      WHEN p.starttime >= a.admittime 
        AND p.starttime <= a.admittime + INTERVAL 72 HOUR 
      THEN 1 ELSE 0 
    END) AS started_within_72h,
    MAX(CASE 
      WHEN (p.stoptime IS NULL OR p.stoptime >= a.dischtime - INTERVAL 48 HOUR) 
        AND p.starttime <= a.dischtime 
      THEN 1 ELSE 0 
    END) AS on_last_48h
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN cohort a 
    ON p.hadm_id = a.hadm_id
  WHERE 
    LOWER(p.drug) LIKE '%liraglutide%' 
    OR LOWER(p.drug) LIKE '%semaglutide%' 
    OR LOWER(p.drug) LIKE '%exenatide%' 
    OR LOWER(p.drug) LIKE '%dulaglutide%' 
    OR LOWER(p.drug) LIKE '%albiglutide%' 
    OR LOWER(p.drug) LIKE '%lixisenatide%' 
    OR LOWER(p.drug) LIKE '%tirzepatide%'
  GROUP BY p.hadm_id
)

SELECT 
  AVG(COALESCE(g.started_within_72h, 0)) * 100 AS percent_started_within_72h,
  AVG(COALESCE(g.on_last_48h, 0)) * 100 AS percent_on_last_48h,
  (AVG(COALESCE(g.on_last_48h, 0)) - AVG(COALESCE(g.started_within_72h, 0))) * 100 AS net_change
FROM cohort c
LEFT JOIN glp1_prescriptions g 
  ON c.hadm_id = g.hadm_id;