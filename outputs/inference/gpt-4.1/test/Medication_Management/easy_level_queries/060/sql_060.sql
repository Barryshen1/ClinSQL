WITH ace_inhibitors AS (
  SELECT DISTINCT LOWER(drug) AS drug_name
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) LIKE '%lisinopril%'
     OR LOWER(drug) LIKE '%enalapril%'
     OR LOWER(drug) LIKE '%captopril%'
     OR LOWER(drug) LIKE '%ramipril%'
     OR LOWER(drug) LIKE '%benazepril%'
     OR LOWER(drug) LIKE '%fosinopril%'
     OR LOWER(drug) LIKE '%moexipril%'
     OR LOWER(drug) LIKE '%perindopril%'
     OR LOWER(drug) LIKE '%quinapril%'
     OR LOWER(drug) LIKE '%trandolapril%'
)

SELECT
  p.subject_id,
  p.anchor_age,
  pr.drug,
  pr.starttime,
  pr.stoptime,
  DATE_DIFF(DATE(pr.stoptime), DATE(pr.starttime), DAY) AS duration_days
FROM
  `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` p
  ON pr.subject_id = p.subject_id
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 38 AND 48
  AND LOWER(pr.drug) IN (
    'lisinopril', 'enalapril', 'captopril', 'ramipril',
    'benazepril', 'fosinopril', 'moexipril', 'perindopril',
    'quinapril', 'trandolapril'
  )
  AND pr.starttime IS NOT NULL
  AND pr.stoptime IS NOT NULL
  AND DATE(pr.stoptime) > DATE(pr.starttime)
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY pr.subject_id
  ORDER BY DATE_DIFF(DATE(pr.stoptime), DATE(pr.starttime), DAY) DESC
) = 1
ORDER BY duration_days DESC;