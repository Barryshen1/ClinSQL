SELECT MIN(DATE_DIFF(p.stoptime, p.starttime, DAY)) AS min_duration_days
FROM physionet-data.mimiciv_3_1_hosp.prescriptions p
JOIN physionet-data.mimiciv_3_1_hosp.patients pat
  ON p.subject_id = pat.subject_id
WHERE LOWER(p.drug) = 'atorvastatin'
  AND SAFE_CAST(p.dose_val_rx AS FLOAT64) BETWEEN 40 AND 80
  AND LOWER(p.dose_unit_rx) = 'mg'
  AND pat.gender = 'F'
  AND pat.anchor_age BETWEEN 86 AND 96
  AND p.stoptime IS NOT NULL;