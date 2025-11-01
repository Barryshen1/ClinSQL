WITH filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 38 AND 48
)
SELECT MAX(duration_days) AS longest_acei_prescription_days
FROM (
  SELECT 
    DATE_DIFF(DATE(p.stoptime), DATE(p.starttime), DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN filtered_patients fp ON p.subject_id = fp.subject_id
  WHERE p.stoptime IS NOT NULL
    AND p.starttime < p.stoptime
    AND (
      LOWER(p.drug) LIKE '%lisinopril%'
      OR LOWER(p.drug) LIKE '%enalapril%'
      OR LOWER(p.drug) LIKE '%ramipril%'
      OR LOWER(p.drug) LIKE '%captopril%'
      OR LOWER(p.drug) LIKE '%benazepril%'
      OR LOWER(p.drug) LIKE '%quinapril%'
      OR LOWER(p.drug) LIKE '%perindopril%'
      OR LOWER(p.drug) LIKE '%trandolapril%'
      OR LOWER(p.drug) LIKE '%fosinopril%'
      OR LOWER(p.drug) LIKE '%moexipril%'
    )
    AND DATE_DIFF(DATE(p.stoptime), DATE(p.starttime), DAY) > 0
) AS durations;