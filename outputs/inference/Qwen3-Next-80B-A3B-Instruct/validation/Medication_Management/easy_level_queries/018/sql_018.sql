SELECT MAX(TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY)) AS longest_digoxin_duration_days
FROM physionet-data.mimiciv_3_1_hosp.prescriptions p
JOIN physionet-data.mimiciv_3_1_hosp.patients pat
  ON p.subject_id = pat.subject_id
WHERE pat.gender = 'M'
  AND pat.anchor_age BETWEEN 82 AND 92
  AND LOWER(p.drug) LIKE '%digoxin%'
  AND p.starttime IS NOT NULL
  AND p.stoptime IS NOT NULL;