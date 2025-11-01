SELECT
  PERCENTILE_CONT(duration_days, 0.25) OVER () AS percentile_25
FROM (
  SELECT
    TIMESTAMP_DIFF(p.stoptime, p.starttime, SECOND) / 86400.0 AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.hadm_id = a.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON a.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (pat.anchor_year - pat.anchor_age) = 55
    AND p.stoptime IS NOT NULL
    AND (
      LOWER(p.drug) LIKE '%benazepril%' OR
      LOWER(p.drug) LIKE '%captopril%' OR
      LOWER(p.drug) LIKE '%enalapril%' OR
      LOWER(p.drug) LIKE '%fosinopril%' OR
      LOWER(p.drug) LIKE '%lisinopril%' OR
      LOWER(p.drug) LIKE '%moexipril%' OR
      LOWER(p.drug) LIKE '%perindopril%' OR
      LOWER(p.drug) LIKE '%quinapril%' OR
      LOWER(p.drug) LIKE '%ramipril%' OR
      LOWER(p.drug) LIKE '%trandolapril%'
    )
)
WHERE
  duration_days >= 0
LIMIT 1;