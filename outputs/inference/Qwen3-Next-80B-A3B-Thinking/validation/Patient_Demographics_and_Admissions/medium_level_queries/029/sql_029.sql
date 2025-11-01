SELECT
    a.hospital_expire_flag,
    AVG(i.los) AS mean_los,
    STDDEV(i.los) AS std_los,
    (SUM(CASE WHEN i.los < 7 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS percent_less_than_7
FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
WHERE
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 35 AND 45
GROUP BY
    a.hospital_expire_flag;