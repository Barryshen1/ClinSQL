SELECT MAX(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)) AS max_hospital_los_days
FROM physionet-data.mimiciv_3_1_hosp.admissions a
JOIN physionet-data.mimiciv_3_1_hosp.patients p
  ON a.subject_id = p.subject_id
WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 58 AND 68
  AND a.dischtime IS NOT NULL;