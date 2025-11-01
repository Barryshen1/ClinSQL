WITH filtered_admissions AS (
  SELECT 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 48 AND 58
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
    AND a.dischtime - a.admittime >= INTERVAL '12' HOUR
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE d.hadm_id = a.hadm_id 
        AND d.icd_code LIKE 'E11%'
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE d.hadm_id = a.hadm_id 
        AND d.icd_code LIKE 'I50%'
    )
),
glp1_flags AS (
  SELECT 
    a.hadm_id,
    MAX(CASE WHEN p.starttime BETWEEN a.admittime AND a.admittime + INTERVAL '12' HOUR THEN 1 ELSE 0 END) AS first_12h,
    MAX(CASE WHEN p.starttime BETWEEN a.dischtime - INTERVAL '12' HOUR AND a.dischtime THEN 1 ELSE 0 END) AS last_12h
  FROM filtered_admissions a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON a.hadm_id = p.hadm_id
    AND (
      LOWER(p.drug) LIKE '%liraglutide%' 
      OR LOWER(p.drug) LIKE '%semaglutide%' 
      OR LOWER(p.drug) LIKE '%exenatide%' 
      OR LOWER(p.drug) LIKE '%dulaglutide%' 
      OR LOWER(p.drug) LIKE '%albiglutide%'
    )
  GROUP BY a.hadm_id
)
SELECT 
  AVG(first_12h) * 100 AS percent_first_12h,
  AVG(last_12h) * 100 AS percent_last_12h,
  (AVG(first_12h) - AVG(last_12h)) * 100 AS net_change
FROM glp1_flags;