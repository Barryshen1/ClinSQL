SELECT
  AVG(DATE_DIFF(pr.stoptime, pr.starttime, DAY)) AS avg_duration_days
FROM
  `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` adm
ON
  pr.hadm_id = adm.hadm_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` pat
ON
  pr.subject_id = pat.subject_id
WHERE
  pat.gender = 'F'
  AND pat.anchor_age BETWEEN 77 AND 87
  AND pr.starttime IS NOT NULL
  AND pr.stoptime IS NOT NULL
  AND DATE_DIFF(pr.stoptime, pr.starttime, DAY) >= 0
  AND (
    LOWER(pr.drug) LIKE '%losartan%' OR
    LOWER(pr.drug) LIKE '%valsartan%' OR
    LOWER(pr.drug) LIKE '%irbesartan%' OR
    LOWER(pr.drug) LIKE '%candesartan%' OR
    LOWER(pr.drug) LIKE '%telmisartan%' OR
    LOWER(pr.drug) LIKE '%olmesartan%'
  );