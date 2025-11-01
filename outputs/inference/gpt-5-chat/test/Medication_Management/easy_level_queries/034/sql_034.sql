SELECT 
  MAX(TIMESTAMP_DIFF(pres.stoptime, pres.starttime, DAY)) AS max_duration_days
FROM `physionet-data.mimiciv_3_1_hosp.patients` pat
JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
  ON pat.subject_id = pres.subject_id
WHERE pat.gender = 'F'
  AND pat.anchor_age BETWEEN 51 AND 61
  AND pres.starttime IS NOT NULL
  AND pres.stoptime IS NOT NULL
  AND (
    LOWER(pres.drug) LIKE '%hydralazine%' 
    OR LOWER(pres.drug) LIKE '%isosorbide dinitrate%'
  );