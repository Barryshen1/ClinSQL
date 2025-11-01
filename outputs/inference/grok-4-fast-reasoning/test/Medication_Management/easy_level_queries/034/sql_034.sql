SELECT
  MAX(DATE_DIFF(stoptime, starttime, DAY)) AS max_duration_days
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` p
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
ON
  p.subject_id = pr.subject_id
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 51 AND 61
  AND (LOWER(pr.drug) LIKE '%hydralazine%' OR LOWER(pr.drug) LIKE '%isosorbide dinitrate%')
  AND pr.stoptime IS NOT NULL;