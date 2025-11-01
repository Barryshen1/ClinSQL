WITH eligible_prescriptions AS (
  SELECT 
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON a.subject_id = pr.subject_id AND a.hadm_id = pr.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age = 55
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime > pr.starttime
    AND UPPER(pr.drug) IN (
      'LISINOPRIL', 'ENALAPRIL', 'RAMIPRIL', 'CAPTOPRIL', 
      'FOSINOPRIL', 'QUINAPRIL', 'BENAZEPRIL', 'MOEXIPRIL', 
      'PERINDOPRIL', 'TRANDOLAPRIL', 'ENALAPRILAT'
    )
)
SELECT 
  APPROX_QUANTILES(duration_days, 4)[OFFSET(1)] AS p25_duration_days
FROM 
  eligible_prescriptions;