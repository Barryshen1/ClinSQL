WITH 
-- Filter and calculate medication complexity
patients_filtered AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    COUNT(DISTINCT pr.drug) AS medication_count
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON a.hadm_id = pr.hadm_id
  WHERE 
    p.gender = 'M' AND 
    p.anchor_age BETWEEN 58 AND 68 AND
    a.admission_type = 'Emergency' AND
    a.discharge_location NOT LIKE '%Death%' AND
    pr.starttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 3 DAY)
  GROUP BY 
    p.subject_id, p.gender, p.anchor_age, a.hadm_id, a.admittime, a.dischtime, a.deathtime
),

-- Calculate tertiles of medication complexity
medication_tertiles AS (
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    deathtime,
    medication_count,
    NTILE(3) OVER (ORDER BY medication_count) AS tertile
  FROM 
    patients_filtered
),

-- Calculate outcomes
outcomes AS (
  SELECT 
    mt.subject_id,
    mt.hadm_id,
    mt.admittime,
    mt.dischtime,
    mt.deathtime,
    mt.medication_count,
    mt.tertile,
    DATE_DIFF(mt.dischtime, mt.admittime, DAY) AS los,
    IF(mt.deathtime IS NOT NULL, 1, 0) AS mortality,
    -- Assuming readmission data is not directly available, 
    -- a simple 30-day readmission flag is used here for illustration.
    -- In real scenarios, you'd need a readmissions table or similar.
    EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2 
      WHERE a2.subject_id = mt.subject_id 
      AND a2.admittime BETWEEN TIMESTAMP_ADD(mt.dischtime, INTERVAL 1 DAY) 
      AND TIMESTAMP_ADD(mt.dischtime, INTERVAL 30 DAY)
    ) AS readmitted
  FROM 
    medication_tertiles mt
)

-- Final aggregation
SELECT 
  tertile,
  COUNT(*) AS n,
  MIN(medication_count) AS min_complexity,
  MAX(medication_count) AS max_complexity,
  AVG(medication_count) AS mean_complexity,
  AVG(los) AS mean_los,
  AVG(mortality) * 100 AS mortality_pct,
  AVG(IF(readmitted, 1, 0)) * 100 AS readmission_pct
FROM 
  outcomes
GROUP BY 
  tertile;