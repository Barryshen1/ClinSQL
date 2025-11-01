SELECT MAX(p.stoptime - p.starttime) AS max_duration
FROM physionet-data.mimiciv_3_1_hosp.prescriptions p
JOIN physionet-data.mimiciv_3_1_hosp.patients pat
  ON p.subject_id = pat.subject_id
WHERE pat.gender = 'F'
  AND pat.anchor_age BETWEEN 80 AND 90
  AND LOWER(p.drug) LIKE '%nitro%'
  AND LOWER(p.route) IN ('iv', 'oral', 'sublingual')
  AND p.stoptime IS NOT NULL
  AND p.stoptime >= p.starttime;