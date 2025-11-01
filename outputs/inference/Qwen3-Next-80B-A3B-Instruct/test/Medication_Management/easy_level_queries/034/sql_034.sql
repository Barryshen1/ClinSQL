SELECT MAX(EXTRACT(DAY FROM (p.stoptime - p.starttime))) AS longest_duration_days
FROM physionet-data.mimiciv_3_1_hosp.prescriptions p
JOIN physionet-data.mimiciv_3_1_hosp.patients pat
  ON p.subject_id = pat.subject_id
WHERE pat.gender = 'F'
  AND pat.anchor_age BETWEEN 51 AND 61
  AND p.stoptime IS NOT NULL
  AND (LOWER(p.drug) LIKE '%hydralazine%' OR LOWER(p.drug) LIKE '%isosorbide dinitrate%');