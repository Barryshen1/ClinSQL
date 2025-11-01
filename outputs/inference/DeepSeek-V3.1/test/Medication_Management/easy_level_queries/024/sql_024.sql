SELECT
  MAX(DATETIME_DIFF(stoptime, starttime, DAY)) AS max_duration_days
FROM
  `physionet-data.mimiciv_3_1_hosp`.prescriptions pr
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp`.patients p
  ON pr.subject_id = p.subject_id
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON pr.hadm_id = a.hadm_id
WHERE
  p.gender = 'M'
  AND p.anchor_age BETWEEN 84 AND 94
  AND pr.stoptime IS NOT NULL
  AND (
    LOWER(pr.drug) LIKE '%aspirin%'
    OR LOWER(pr.drug) LIKE '%clopidogrel%'
    OR LOWER(pr.drug) LIKE '%prasugrel%'
    OR LOWER(pr.drug) LIKE '%ticagrelor%'
    OR LOWER(pr.drug) LIKE '%plavix%'
  );