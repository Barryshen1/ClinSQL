SELECT PERCENTILE_CONT(ARRAY_AGG(TIMESTAMP_DIFF(stoptime, starttime, DAY)), 0.25) AS percentile_25_duration_days
FROM physionet-data.mimiciv_3_1_hosp.prescriptions p
JOIN physionet-data.mimiciv_3_1_hosp.patients pat
  ON p.subject_id = pat.subject_id
WHERE LOWER(TRIM(p.drug)) = 'amiodarone'
  AND pat.gender = 'F'
  AND pat.anchor_age BETWEEN 42 AND 52
  AND p.stoptime IS NOT NULL
  AND p.starttime IS NOT NULL
  AND p.stoptime >= p.starttime;