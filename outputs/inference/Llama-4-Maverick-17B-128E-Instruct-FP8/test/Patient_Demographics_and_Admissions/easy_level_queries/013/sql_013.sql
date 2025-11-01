SELECT MAX(DATE_DIFF(dischtime, admittime, DAY)) AS max_los
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
ON a.subject_id = p.subject_id
WHERE p.gender = 'M' AND p.anchor_age BETWEEN 58 AND 68;