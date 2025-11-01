WITH ace_prescriptions AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    p.drug,
    p.starttime,
    p.stoptime,
    pa.gender,
    pa.anchor_age,
    a.admission_type,
    DATE(p.stoptime) - DATE(p.starttime) AS duration_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` pa
    ON p.subject_id = pa.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.hadm_id = a.hadm_id
  WHERE 
    pa.anchor_age = 55
    AND pa.gender = 'F'
    AND a.admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT')
    AND p.stoptime IS NOT NULL
    AND (
      LOWER(p.drug) LIKE '%lisinopril%'
      OR LOWER(p.drug) LIKE '%enalapril%'
      OR LOWER(p.drug) LIKE '%ramipril%'
      OR LOWER(p.drug) LIKE '%captopril%'
      OR LOWER(p.drug) LIKE '%benazepril%'
      OR LOWER(p.drug) LIKE '%quinapril%'
      OR LOWER(p.drug) LIKE '%perindopril%'
      OR LOWER(p.drug) LIKE '%trandolapril%'
      OR LOWER(p.drug) LIKE '%moexipril%'
    )
),
single_ace_adms AS (
  SELECT 
    subject_id,
    hadm_id,
    duration_days
  FROM (
    SELECT 
      subject_id,
      hadm_id,
      duration_days,
      COUNT(DISTINCT drug) OVER (PARTITION BY subject_id, hadm_id) AS num_ace_drugs
    FROM ace_prescriptions
    WHERE duration_days > 0
  )
  WHERE num_ace_drugs = 1
)
SELECT 
  PERCENTILE_CONT(0.25) OVER() AS p25_duration_days
FROM single_ace_adms;