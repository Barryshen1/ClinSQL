WITH type_2_diabetes AS (
  SELECT 
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE d.icd_version = 10
    AND d.icd_code LIKE 'E11%'
  UNION ALL
  SELECT 
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE d.icd_version = 9
    AND d.icd_code LIKE '250%'
    AND (SUBSTR(d.icd_code, 4, 1) = '0' OR SUBSTR(d.icd_code, 4, 1) = '2')
),
heart_failure AS (
  SELECT 
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE d.icd_version = 10
    AND d.icd_code LIKE 'I50%'
  UNION ALL
  SELECT 
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE d.icd_version = 9
    AND d.icd_code LIKE '428%'
),
cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 50 AND 60
    AND a.dischtime >= a.admittime + INTERVAL '72' HOUR
    AND a.hadm_id IN (SELECT hadm_id FROM type_2_diabetes)
    AND a.hadm_id IN (SELECT hadm_id FROM heart_failure)
),
glp1 AS (
  SELECT 
    hadm_id,
    starttime,
    stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE 
    LOWER(drug) LIKE '%exenatide%' OR
    LOWER(drug) LIKE '%byetta%' OR
    LOWER(drug) LIKE '%bydureon%' OR
    LOWER(drug) LIKE '%liraglutide%' OR
    LOWER(drug) LIKE '%victoza%' OR
    LOWER(drug) LIKE '%saxenda%' OR
    LOWER(drug) LIKE '%dulaglutide%' OR
    LOWER(drug) LIKE '%trulicity%' OR
    LOWER(drug) LIKE '%semaglutide%' OR
    LOWER(drug) LIKE '%ozempic%' OR
    LOWER(drug) LIKE '%rybelsus%' OR
    LOWER(drug) LIKE '%lixisenatide%'
),
cohort_with_flags AS (
  SELECT 
    c.hadm_id,
    c.admittime,
    MAX(CASE WHEN g.starttime <= c.admittime + INTERVAL '12' HOUR THEN 1 ELSE 0 END) AS init_12h,
    MAX(CASE 
          WHEN g.starttime <= c.admittime + INTERVAL '72' HOUR 
            AND (g.stoptime > c.admittime + INTERVAL '72' HOUR OR g.stoptime IS NULL) 
          THEN 1 ELSE 0 
        END) AS prev_72h
  FROM cohort c
  LEFT JOIN glp1 g ON c.hadm_id = g.hadm_id
  GROUP BY c.hadm_id, c.admittime
)
SELECT 
  (SUM(init_12h) * 100.0 / COUNT(*)) AS init_12h_percent,
  (SUM(prev_72h) * 100.0 / COUNT(*)) AS prev_72h_percent,
  (SUM(prev_72h) * 100.0 / COUNT(*) - SUM(init_12h) * 100.0 / COUNT(*)) AS net_change_percent_points
FROM cohort_with_flags;