SELECT AVG(DATE_DIFF(p.stoptime, p.starttime, DAY)) AS average_duration_days
FROM physionet-data.mimiciv_3_1_hosp.prescriptions p
JOIN physionet-data.mimiciv_3_1_hosp.patients pat
  ON p.subject_id = pat.subject_id
WHERE pat.gender = 'M'
  AND pat.anchor_age BETWEEN 43 AND 53
  AND LOWER(p.drug) LIKE '%warfarin%'
  AND p.stoptime IS NOT NULL
  AND p.stoptime >= p.starttime;