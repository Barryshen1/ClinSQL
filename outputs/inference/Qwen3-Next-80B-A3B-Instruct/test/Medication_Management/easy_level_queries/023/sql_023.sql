SELECT STDDEV(DATE_DIFF(p.stoptime, p.starttime, DAY)) AS sd_duration_days
FROM physionet-data.mimiciv_3_1_hosp.prescriptions p
JOIN physionet-data.mimiciv_3_1_hosp.patients pat
  ON p.subject_id = pat.subject_id
WHERE pat.gender = 'F'
  AND pat.anchor_age BETWEEN 78 AND 88
  AND p.stoptime IS NOT NULL
  AND p.starttime IS NOT NULL
  AND p.stoptime >= p.starttime
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