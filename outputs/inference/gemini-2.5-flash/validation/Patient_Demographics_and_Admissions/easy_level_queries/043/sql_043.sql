SELECT
    PERCENTILE_DISC(a.hospital_expire_flag, 0.25) OVER () AS q1_mortality,
    PERCENTILE_DISC(a.hospital_expire_flag, 0.75) OVER () AS q3_mortality,
    (PERCENTILE_DISC(a.hospital_expire_flag, 0.75) OVER () - PERCENTILE_DISC(a.hospital_expire_flag, 0.25) OVER ()) AS iqr_mortality_rate
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61;