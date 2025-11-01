SELECT
  MAX(DATE_DIFF(DATE(pr.stoptime), DATE(pr.starttime), DAY)) AS max_duration_days
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` AS pat
JOIN
  `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
ON
  pat.subject_id = pr.subject_id
WHERE
  pat.gender = 'F'
  AND pat.anchor_age BETWEEN 38 AND 48
  AND (
    LOWER(pr.drug) LIKE '%lisinopril%'
    OR LOWER(pr.drug) LIKE '%enalapril%'
    OR LOWER(pr.drug) LIKE '%ramipril%'
    OR LOWER(pr.drug) LIKE '%captopril%'
    OR LOWER(pr.drug) LIKE '%perindopril%'
    OR LOWER(pr.drug) LIKE '%quinapril%'
    OR LOWER(pr.drug) LIKE '%trandolapril%'
    OR LOWER(pr.drug) LIKE '%benazepril%'
  );