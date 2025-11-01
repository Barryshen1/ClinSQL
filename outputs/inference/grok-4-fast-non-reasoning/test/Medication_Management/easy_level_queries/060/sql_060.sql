WITH eligible_prescriptions AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    p.drug,
    p.starttime,
    p.stoptime,
    DATE_DIFF(DATE(p.stoptime), DATE(p.starttime), DAY) AS duration_days,
    pat.gender,
    pat.anchor_age
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON p.subject_id = pat.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.hadm_id = adm.hadm_id
  WHERE 
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 38 AND 48
    AND adm.admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT')
    AND (LOWER(p.drug) LIKE '%ace%' OR LOWER(p.drug) LIKE '%inhibitor%')
    AND p.stoptime IS NOT NULL
    AND p.starttime IS NOT NULL
    AND p.stoptime > p.starttime
)

SELECT 
  MAX(duration_days) AS longest_ace_inhibitor_duration_days
FROM 
  eligible_prescriptions;