WITH cohort AS (
  SELECT DISTINCT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 73 AND 83
)
SELECT STDDEV(
  DATE_DIFF(prescriptions.stoptime, prescriptions.starttime, DAY)
) AS sd_nitrate_prescription_duration_days
FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS prescriptions
INNER JOIN cohort ON prescriptions.subject_id = cohort.subject_id
WHERE prescriptions.stoptime IS NOT NULL
  AND prescriptions.stoptime > prescriptions.starttime
  AND (
    prescriptions.drug LIKE '%NITROGLYCERIN%'
    OR prescriptions.drug LIKE '%DINITRATE%'
    OR prescriptions.drug LIKE '%MONONITRATE%'
  );