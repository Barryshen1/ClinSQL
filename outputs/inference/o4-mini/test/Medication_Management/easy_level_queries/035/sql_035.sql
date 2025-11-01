SELECT
  MAX(DATETIME_DIFF(pr.stoptime, pr.starttime, DAY)) AS max_nitrate_prescription_duration_days
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON a.hadm_id = pr.hadm_id
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 80 AND 90
  AND pr.starttime IS NOT NULL
  AND pr.stoptime IS NOT NULL
  AND pr.stoptime > pr.starttime
  -- capture nitroglycerin and isosorbide formulations
  AND (
    LOWER(pr.drug) LIKE '%nitro%'
    OR LOWER(pr.drug) LIKE '%isosorbide%'
  )
  -- restrict to IV, Oral, or Sublingual routes
  AND LOWER(pr.route) IN ('iv', 'oral', 'sublingual');