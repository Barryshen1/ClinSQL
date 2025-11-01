SELECT
  STDDEV_SAMP(duration_days) AS acei_prescription_duration_sd_days
FROM (
  SELECT
    p.subject_id,
    pr.hadm_id,
    pr.drug,
    DATE_DIFF(CAST(pr.stoptime AS DATE), CAST(pr.starttime AS DATE), DAY) AS duration_days
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
    INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
      ON p.subject_id = a.subject_id
    INNER JOIN physionet-data.mimiciv_3_1_hosp.prescriptions pr
      ON a.subject_id = pr.subject_id
      AND a.hadm_id = pr.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 78 AND 88
    AND pr.drug IS NOT NULL
    AND (
      LOWER(pr.drug) LIKE '%lisinopril%' OR
      LOWER(pr.drug) LIKE '%enalapril%' OR
      LOWER(pr.drug) LIKE '%captopril%' OR
      LOWER(pr.drug) LIKE '%ramipril%' OR
      LOWER(pr.drug) LIKE '%benazepril%' OR
      LOWER(pr.drug) LIKE '%quinapril%' OR
      LOWER(pr.drug) LIKE '%perindopril%' OR
      LOWER(pr.drug) LIKE '%fosinopril%' OR
      LOWER(pr.drug) LIKE '%moexipril%' OR
      LOWER(pr.drug) LIKE '%trandolapril%'
    )
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND DATE_DIFF(CAST(pr.stoptime AS DATE), CAST(pr.starttime AS DATE), DAY) >= 0
);