SELECT MAX(DATE_DIFF(stoptime, starttime, 'DAY')) AS max_duration
FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
  ON p.subject_id = pt.subject_id
WHERE pt.gender = 'F'
  AND pt.anchor_age BETWEEN 38 AND 48
  AND p.stoptime IS NOT NULL
  AND p.stoptime > p.starttime
  AND (
    LOWER(p.drug) LIKE '%lisinopril%'
    OR LOWER(p.drug) LIKE '%enalapril%'
    OR LOWER(p.drug) LIKE '%ramipril%'
    OR LOWER(p.drug) LIKE '%captopril%'
    OR LOWER(p.drug) LIKE '%benazepril%'
    OR LOWER(p.drug) LIKE '%quinapril%'
    OR LOWER(p.drug) LIKE '%fosinopril%'
    OR LOWER(p.drug) LIKE '%moexipril%'
    OR LOWER(p.drug) LIKE '%perindopril%'
    OR LOWER(p.drug) LIKE '%trandolapril%'
  );