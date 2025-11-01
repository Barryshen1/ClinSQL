WITH ace_inhibitor_prescriptions AS (
  SELECT
    p.subject_id,
    pr.starttime,
    pr.stoptime,
    pr.drug,
    DATE_DIFF(DATE(pr.stoptime), DATE(pr.starttime), DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON pr.subject_id = p.subject_id
  WHERE
    LOWER(pr.drug) LIKE '%lisinopril%'
    OR LOWER(pr.drug) LIKE '%enalapril%'
    OR LOWER(pr.drug) LIKE '%captopril%'
    OR LOWER(pr.drug) LIKE '%ramipril%'
    OR LOWER(pr.drug) LIKE '%benazepril%'
    OR LOWER(pr.drug) LIKE '%quinapril%'
    OR LOWER(pr.drug) LIKE '%perindopril%'
    OR LOWER(pr.drug) LIKE '%fosinopril%'
    OR LOWER(pr.drug) LIKE '%moexipril%'
    OR LOWER(pr.drug) LIKE '%trandolapril%'
    AND p.gender = 'F'
    AND p.anchor_age = 55
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
)
SELECT
  APPROX_QUANTILES(duration_days, 4)[OFFSET(1)] AS ace_inhibitor_prescription_duration_25th_percentile_days
FROM
  ace_inhibitor_prescriptions
WHERE
  duration_days > 0;