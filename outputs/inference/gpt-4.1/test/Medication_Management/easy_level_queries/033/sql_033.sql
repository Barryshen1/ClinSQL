SELECT
  AVG(duration_days) AS avg_arb_prescription_duration_days
FROM (
  SELECT
    p.subject_id,
    pr.hadm_id,
    pr.drug,
    DATE(pr.starttime) AS start_date,
    DATE(pr.stoptime) AS stop_date,
    DATE_DIFF(DATE(pr.stoptime), DATE(pr.starttime), DAY) + 1 AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON p.subject_id = pr.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pr.subject_id = adm.subject_id AND pr.hadm_id = adm.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
    AND adm.admission_type IN ('EMERGENCY', 'URGENT', 'ELECTIVE')
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND LOWER(pr.drug) LIKE '%losartan%'
      OR LOWER(pr.drug) LIKE '%valsartan%'
      OR LOWER(pr.drug) LIKE '%candesartan%'
      OR LOWER(pr.drug) LIKE '%irbesartan%'
      OR LOWER(pr.drug) LIKE '%olmesartan%'
      OR LOWER(pr.drug) LIKE '%telmisartan%'
      OR LOWER(pr.drug) LIKE '%eprosartan%'
      OR LOWER(pr.drug) LIKE '%azilsartan%'
)
WHERE
  duration_days > 0;