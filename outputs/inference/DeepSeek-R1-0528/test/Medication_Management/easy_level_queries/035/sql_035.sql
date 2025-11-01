SELECT
  MAX(TIMESTAMP_DIFF(p.stoptime, p.starttime, HOUR)) AS max_duration_hours
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` pat
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` adm
  ON pat.subject_id = adm.subject_id
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  ON adm.hadm_id = p.hadm_id
  AND adm.subject_id = p.subject_id
WHERE
  pat.gender = 'F'
  AND pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year BETWEEN 80 AND 90
  AND (LOWER(p.drug) LIKE '%nitro%' OR LOWER(p.drug) LIKE '%nitrate%')
  AND (
    LOWER(p.route) LIKE '%iv%'
    OR LOWER(p.route) LIKE '%po%'
    OR LOWER(p.route) LIKE '%oral%'
    OR LOWER(p.route) LIKE '%sl%'
    OR LOWER(p.route) LIKE '%sublingual%'
  )
  AND p.starttime IS NOT NULL
  AND p.stoptime IS NOT NULL
  AND p.stoptime > p.starttime;