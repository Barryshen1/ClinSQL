SELECT
  AVG(DATETIME_DIFF(pres.stoptime, pres.starttime, DAY)) AS avg_duration_days
FROM
  `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON pres.subject_id = pat.subject_id
WHERE
  pat.gender = 'F'
  AND pat.anchor_age BETWEEN 77 AND 87
  AND LOWER(pres.drug) IN (
    'losartan', 'valsartan', 'irbesartan', 'candesartan', 
    'telmisartan', 'olmesartan', 'eprosartan', 'azilsartan'
  )
  AND pres.starttime IS NOT NULL
  AND pres.stoptime IS NOT NULL
  AND pres.stoptime >= pres.starttime;