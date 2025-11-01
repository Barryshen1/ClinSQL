SELECT
  PERCENTILE_CONT(DATE_DIFF(pres.stoptime, pres.starttime, DAY), 0.75) OVER() AS p75_arb_duration_days
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` AS pat
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  ON pat.subject_id = adm.subject_id
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pres
  ON adm.hadm_id = pres.hadm_id AND pat.subject_id = pres.subject_id
WHERE
  pat.gender = 'M'
  AND pat.anchor_age BETWEEN 38 AND 48
  AND LOWER(pres.drug) LIKE ('%valsartan%')
  OR LOWER(pres.drug) LIKE ('%losartan%')
  OR LOWER(pres.drug) LIKE ('%irbesartan%')
  OR LOWER(pres.drug) LIKE ('%candesartan%')
  OR LOWER(pres.drug) LIKE ('%olmesartan%')
  OR LOWER(pres.drug) LIKE ('%telmisartan%')
  OR LOWER(pres.drug) LIKE ('%azilsartan%')
  -- Ensure valid start and stop times for duration calculation
  AND pres.starttime IS NOT NULL
  AND pres.stoptime IS NOT NULL
  AND pres.stoptime >= pres.starttime
QUALIFY ROW_NUMBER() OVER () = 1 -- Only one row for the single percentile value;