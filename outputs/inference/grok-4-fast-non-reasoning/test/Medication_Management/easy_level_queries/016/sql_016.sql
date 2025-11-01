WITH eligible_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 76 AND 86
),
nitrate_prescriptions AS (
  SELECT pr.pharmacy_id, pr.starttime, pr.stoptime,
    DATE_DIFF(DATE(pr.stoptime), DATE(pr.starttime), DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN eligible_patients ep
    ON pr.subject_id = ep.subject_id
  WHERE pr.hadm_id IS NOT NULL  -- Inpatients only
    AND UPPER(pr.drug) LIKE '%NITRAT%'
    AND (UPPER(pr.route) LIKE '%IV%' OR UPPER(pr.route) = 'PO')
    AND pr.stoptime > pr.starttime
    AND DATE_DIFF(DATE(pr.stoptime), DATE(pr.starttime), DAY) > 0
)
SELECT PERCENTILE_CONT(duration_days, 0.25) AS p25_duration_days
FROM nitrate_prescriptions;