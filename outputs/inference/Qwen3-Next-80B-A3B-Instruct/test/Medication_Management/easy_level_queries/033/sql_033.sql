SELECT AVG(DATETIME_DIFF(stoptime, starttime, DAY)) AS average_duration_days
FROM physionet-data.mimiciv_3_1_hosp.prescriptions p
JOIN physionet-data.mimiciv_3_1_hosp.patients pat
  ON p.subject_id = pat.subject_id
WHERE pat.gender = 'F'
  AND pat.anchor_age BETWEEN 77 AND 87
  AND p.stoptime IS NOT NULL
  AND p.stoptime >= p.starttime
  AND (
    LOWER(p.drug) LIKE '%losartan%'
    OR LOWER(p.drug) LIKE '%valsartan%'
    OR LOWER(p.drug) LIKE '%irbesartan%'
    OR LOWER(p.drug) LIKE '%candesartan%'
    OR LOWER(p.drug) LIKE '%telmisartan%'
    OR LOWER(p.drug) LIKE '%eprosartan%'
    OR LOWER(p.drug) LIKE '%olmesartan%'
  );