SELECT MAX(DATETIME_DIFF(p.stoptime, p.starttime, DAY)) AS max_duration_days
FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON p.subject_id = pat.subject_id
WHERE LOWER(p.drug) IN ('hydralazine', 'isosorbide dinitrate')
  AND pat.gender = 'F'
  AND p.stoptime IS NOT NULL
  AND p.starttime IS NOT NULL
  AND (EXTRACT(YEAR FROM p.starttime) - (pat.anchor_year - pat.anchor_age)) BETWEEN 51 AND 61;