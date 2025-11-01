WITH patient_cohort AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND a.hospital_expire_flag = 0
    AND a.admission_type IN ('ELECTIVE', 'URGENT', 'EMERGENCY')
),
prescription_durations AS (
  SELECT 
    pr.subject_id,
    pr.pharmacy_id,
    DATE_DIFF(
      DATE(pr.stoptime), 
      DATE(pr.starttime), 
      DAY
    ) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN patient_cohort pc
    ON pr.subject_id = pc.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON pr.hadm_id = a.hadm_id
  WHERE pr.stoptime IS NOT NULL
    AND pr.starttime IS NOT NULL
    AND DATE_DIFF(DATE(pr.stoptime), DATE(pr.starttime), DAY) > 0
    AND LOWER(pr.drug) LIKE '%spironolactone%'
    AND pr.poe_seq = 1
    AND a.hospital_expire_flag = 0
    AND a.admission_type IN ('ELECTIVE', 'URGENT', 'EMERGENCY')
  UNION ALL
  SELECT 
    pr.subject_id,
    pr.pharmacy_id,
    DATE_DIFF(
      DATE(pr.stoptime), 
      DATE(pr.starttime), 
      DAY
    ) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN patient_cohort pc
    ON pr.subject_id = pc.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON pr.hadm_id = a.hadm_id
  WHERE pr.stoptime IS NOT NULL
    AND pr.starttime IS NOT NULL
    AND DATE_DIFF(DATE(pr.stoptime), DATE(pr.starttime), DAY) > 0
    AND LOWER(pr.drug) LIKE '%eplerenone%'
    AND pr.poe_seq = 1
    AND a.hospital_expire_flag = 0
    AND a.admission_type IN ('ELECTIVE', 'URGENT', 'EMERGENCY')
)
SELECT 
  AVG(duration_days) AS avg_duration_days
FROM prescription_durations
WHERE subject_id = 10006  -- Replace with the actual subject_id of the 69-year-old male patient;