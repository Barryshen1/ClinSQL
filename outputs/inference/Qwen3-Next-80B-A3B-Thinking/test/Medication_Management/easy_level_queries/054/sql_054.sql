SELECT AVG(DATE_DIFF(p.stoptime, p.starttime, DAY)) AS avg_duration_days
FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
ON p.subject_id = pt.subject_id
WHERE pt.gender = 'M'
  AND pt.anchor_age BETWEEN 66 AND 76
  AND p.drug = 'DIGOXIN'
  AND p.stoptime IS NOT NULL
  AND p.starttime IS NOT NULL
  AND p.stoptime > p.starttime;