SELECT MAX(TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY)) AS max_duration_days
FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
  ON p.subject_id = pt.subject_id
WHERE pt.gender = 'F'
  AND pt.anchor_age BETWEEN 80 AND 90
  AND LOWER(p.route) IN ('iv', 'oral', 'sublingual')
  AND (LOWER(p.drug) LIKE '%nitroglycerin%' OR LOWER(p.drug) LIKE '%isosorbide%')
  AND p.stoptime IS NOT NULL
  AND p.starttime IS NOT NULL;