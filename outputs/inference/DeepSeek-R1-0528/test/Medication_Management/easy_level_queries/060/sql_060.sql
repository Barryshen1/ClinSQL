SELECT
  MAX(duration_days) AS max_duration_days
FROM (
  SELECT
    DISTINCT p.subject_id,
    p.hadm_id,
    DATETIME_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.hadm_id = a.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON p.subject_id = pt.subject_id
  WHERE
    -- Filter for female patients
    pt.gender = 'F'
    -- Calculate age at admission: anchor_age + (admission year - anchor_year)
    AND pt.anchor_age + (EXTRACT(YEAR FROM a.admittime) - pt.anchor_year) BETWEEN 38 AND 48
    -- Identify ACE inhibitors using regex for common drugs
    AND REGEXP_CONTAINS(LOWER(p.drug), r'captopril|enalapril|lisinopril|ramipril|quinapril|perindopril|trandolapril|benazepril|fosinopril')
    -- Ensure valid prescription duration
    AND p.stoptime IS NOT NULL
    AND p.stoptime > p.starttime
);