SELECT AVG(TIMESTAMP_DIFF(stoptime, starttime, DAY)) AS avg_duration_days
FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON p.subject_id = pat.subject_id
WHERE pat.gender = 'F'
  AND pat.anchor_age BETWEEN 77 AND 87
  AND p.drug_type = 'ARB';