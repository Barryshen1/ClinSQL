WITH ace_presc AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    DATE_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
      ON pat.subject_id = adm.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      ON adm.hadm_id = p.hadm_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age = 55
    AND LOWER(p.drug) LIKE '%pril%'   -- ACE inhibitors usually end in "-pril"
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND DATE_DIFF(p.stoptime, p.starttime, DAY) > 0
)
SELECT
  -- Extract the 25th percentile (first quartile)
  APPROX_QUANTILES(duration_days, 100)[SAFE_OFFSET(25)] AS duration_25th_percentile_days
FROM
  ace_presc;