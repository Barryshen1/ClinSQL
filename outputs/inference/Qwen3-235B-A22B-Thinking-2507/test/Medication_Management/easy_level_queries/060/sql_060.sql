SELECT 
  MAX((UNIX_SECONDS(CAST(pr.stoptime AS TIMESTAMP)) - UNIX_SECONDS(CAST(pr.starttime AS TIMESTAMP))) / (24 * 60 * 60)) AS longest_duration_days
FROM 
  `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
INNER JOIN 
  `physionet-data.mimiciv_3_1_hosp.patients` pa
  ON pr.subject_id = pa.subject_id
WHERE 
  pa.gender = 'F'
  AND pr.hadm_id IS NOT NULL
  AND pr.starttime IS NOT NULL
  AND pr.stoptime IS NOT NULL
  AND pr.stoptime > pr.starttime
  AND (
    LOWER(pr.drug) LIKE '%benazepril%' OR
    LOWER(pr.drug) LIKE '%captopril%' OR
    LOWER(pr.drug) LIKE '%enalapril%' OR
    LOWER(pr.drug) LIKE '%fosinopril%' OR
    LOWER(pr.drug) LIKE '%lisinopril%' OR
    LOWER(pr.drug) LIKE '%moexipril%' OR
    LOWER(pr.drug) LIKE '%perindopril%' OR
    LOWER(pr.drug) LIKE '%quinapril%' OR
    LOWER(pr.drug) LIKE '%ramipril%' OR
    LOWER(pr.drug) LIKE '%trandolapril%'
  )
  AND (
    EXTRACT(YEAR FROM pr.starttime) - pa.anchor_year + pa.anchor_age
  ) BETWEEN 38 AND 48;