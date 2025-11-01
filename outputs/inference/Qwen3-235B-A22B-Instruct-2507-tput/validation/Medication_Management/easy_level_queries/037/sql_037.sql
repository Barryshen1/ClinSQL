SELECT
  APPROX_QUANTILES(duration_days, 100)[OFFSET(25)] AS percentile_25_duration_days
FROM (
  SELECT
    p.subject_id,
    pr.drug,
    pr.starttime,
    pr.stoptime,
    DATETIME_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.prescriptions pr
    ON p.subject_id = pr.subject_id AND a.hadm_id = pr.hadm_id
  WHERE
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) = 55
    AND pr.stoptime IS NOT NULL
    AND LOWER(pr.drug) IN (
      'enalapril', 'lisinopril', 'benazepril', 'captopril',
      'fosinopril', 'moexipril', 'perindopril', 'quinapril',
      'ramipril', 'trandolapril'
    )
);