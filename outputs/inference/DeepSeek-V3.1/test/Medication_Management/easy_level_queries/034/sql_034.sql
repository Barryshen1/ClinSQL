SELECT
  MAX(DATE_DIFF(stoptime, starttime, DAY)) AS max_duration_days
FROM
  `physionet-data.mimiciv_3_1_hosp.prescriptions` p
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` pt
ON
  p.subject_id = pt.subject_id
WHERE
  pt.gender = 'F'
  AND pt.anchor_age BETWEEN 51 AND 61
  AND (LOWER(p.drug) LIKE '%hydralazine%'
       OR LOWER(p.drug) LIKE '%isosorbide dinitrate%')
  AND p.stoptime IS NOT NULL;