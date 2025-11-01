SELECT STDDEV_POP(duration_days) AS sd_duration
FROM (
  SELECT
    DATE_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON a.hadm_id = pr.hadm_id
  WHERE p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age)) BETWEEN 78 AND 88
    AND LOWER(pr.drug) IN (
      'benazepril', 'captopril', 'enalapril', 'fosinopril', 'lisinopril',
      'moexipril', 'perindopril', 'quinapril', 'ramipril', 'trandolapril'
    )
    AND pr.stoptime IS NOT NULL
    AND pr.starttime <= pr.stoptime
) subquery;