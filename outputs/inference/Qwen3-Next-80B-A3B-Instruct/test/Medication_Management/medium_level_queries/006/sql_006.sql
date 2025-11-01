WITH eligible_patients AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, p.gender, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1 ON a.subject_id = d1.subject_id AND a.hadm_id = d1.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2 ON a.subject_id = d2.subject_id AND a.hadm_id = d2.hadm_id
  WHERE p.anchor_age BETWEEN 48 AND 58
    AND p.gender = 'F'
    AND (
      (d1.icd_version = 9 AND d1.icd_code LIKE '250%') OR
      (d1.icd_version = 10 AND d1.icd_code LIKE 'E11%')
    )
    AND (
      (d2.icd_version = 9 AND d2.icd_code LIKE '428%') OR
      (d2.icd_version = 10 AND d2.icd_code LIKE 'I50%')
    )
    AND d1.icd_code != d2.icd_code
),

glp1_initiations AS (
  SELECT 
    ep.subject_id,
    ep.hadm_id,
    ep.admittime,
    ep.dischtime,
    MIN(pr.starttime) AS first_glp1_starttime
  FROM eligible_patients ep
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
    ON ep.hadm_id = pr.hadm_id
  WHERE LOWER(pr.drug) IN (
    'liraglutide', 'semaglutide', 'exenatide', 'dulaglutide', 'lixisenatide'
  )
  AND pr.starttime IS NOT NULL
  GROUP BY ep.subject_id, ep.hadm_id, ep.admittime, ep.dischtime
),

calculated_intervals AS (
  SELECT 
    gi.subject_id,
    gi.hadm_id,
    gi.admittime,
    gi.dischtime,
    gi.first_glp1_starttime,
    CASE 
      WHEN gi.first_glp1_starttime IS NOT NULL 
        AND gi.first_glp1_starttime >= gi.admittime 
        AND gi.first_glp1_starttime <= gi.admittime + INTERVAL 72 HOUR 
      THEN 1 
      ELSE 0 
    END AS glp1_first_72h,
    CASE 
      WHEN gi.first_glp1_starttime IS NOT NULL 
        AND gi.first_glp1_starttime >= gi.dischtime - INTERVAL 48 HOUR 
        AND gi.first_glp1_starttime <= gi.dischtime 
      THEN 1 
      ELSE 0 
    END AS glp1_last_48h
  FROM glp1_initiations gi
)

SELECT 
  ROUND(100.0 * SUM(glp1_first_72h) / COUNT(*), 2) AS initiation_rate_first_72h_percent,
  ROUND(100.0 * SUM(glp1_last_48h) / COUNT(*), 2) AS initiation_rate_last_48h_percent,
  ROUND(100.0 * (SUM(glp1_first_72h) - SUM(glp1_last_48h)) / COUNT(*), 2) AS absolute_difference_pp
FROM calculated_intervals;