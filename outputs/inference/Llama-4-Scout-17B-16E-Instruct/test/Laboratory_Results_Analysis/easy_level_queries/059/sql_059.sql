WITH 
-- Identify sepsis patients
sepsis_patients AS (
  SELECT DISTINCT 
    a.subject_id, 
    a.hadm_id,
    a.dischtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      ON a.hadm_id = d.hadm_id
  WHERE 
    d.icd_code IN ('995.91', '995.92', '785.52', '038.0', '038.1', '038.2', '038.3', '038.4', '038.8', '038.9',
                   'S sepsis', 'S septic', 'A septicemia', 'A sepsis', 'B sepsis', 'B septicemia')
    AND a.subject_id IN (
      SELECT 
        subject_id 
      FROM 
        `physionet-data.mimiciv_3_1_hosp.patients` 
      WHERE 
        gender = 'M' 
        AND anchor_age >= 93
    )
),

-- Find platelet count on discharge day
platelet_counts AS (
  SELECT 
    s.hadm_id,
    l.valuenum AS platelet_count
  FROM 
    sepsis_patients s
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.labevents` l 
      ON s.hadm_id = l.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_labitems` i 
      ON l.itemid = i.itemid
  WHERE 
    i.label = 'Platelets'
    AND l.charttime BETWEEN 
      TIMESTAMP_SUB(s.dischtime, INTERVAL 1 DAY)
    AND 
      s.dischtime
)

-- Calculate 75th percentile platelet count
SELECT 
  APPROX_QUANTILES(platelet_count, 1000)[OFFSET(750)] AS percentile_75th
FROM 
  platelet_counts;