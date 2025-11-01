SELECT MIN(total_duration) AS min_duration_days
FROM (
  SELECT p.subject_id, 
         SUM(TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY)) AS total_duration
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON p.subject_id = pr.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 86 AND 96
    AND LOWER(pr.drug) LIKE '%atorvastatin%'
    AND CAST(pr.dose_val_rx AS FLOAT64) BETWEEN 40 AND 80
    AND LOWER(pr.dose_unit_rx) = 'mg'
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime >= pr.starttime
  GROUP BY p.subject_id
) patient_durations;