SELECT MAX(TIMESTAMP_DIFF(stoptime, starttime, MINUTE)) AS max_duration_minutes
FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt ON p.subject_id = pt.subject_id
WHERE pt.gender = 'F'
  AND pt.anchor_age BETWEEN 80 AND 90
  AND LOWER(p.drug) LIKE '%nitrate%'
  AND LOWER(p.route) IN ('iv', 'oral', 'sublingual')
  AND p.starttime IS NOT NULL
  AND p.stoptime IS NOT NULL;