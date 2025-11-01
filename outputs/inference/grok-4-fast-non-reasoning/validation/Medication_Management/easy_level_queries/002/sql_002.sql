WITH eligible_patients AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    WHERE admission_type IN ('ELECTIVE', 'URGENT', 'EMERGENCY')
    GROUP BY subject_id
    HAVING COUNT(*) = 1
  ) single_adm ON p.subject_id = single_adm.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
),
amio_durations AS (
  SELECT 
    EXTRACT(DAY FROM (DATE(pr.stoptime) - DATE(pr.starttime))) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN eligible_patients ep ON pr.subject_id = ep.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON pr.subject_id = a.subject_id AND pr.hadm_id = a.hadm_id
  WHERE LOWER(pr.drug) LIKE '%amiodarone%'
    AND pr.drug IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.starttime IS NOT NULL
    AND a.admission_type IN ('ELECTIVE', 'URGENT', 'EMERGENCY')
)
SELECT 
  PERCENTILE_CONT(0.25, duration_days) AS iqr_q1,
  PERCENTILE_CONT(0.75, duration_days) AS iqr_q3
FROM amio_durations
WHERE duration_days > 0;