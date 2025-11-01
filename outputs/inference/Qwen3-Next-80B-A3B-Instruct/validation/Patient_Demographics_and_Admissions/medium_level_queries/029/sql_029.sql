SELECT
    a.hospital_expire_flag,
    AVG(i.los) AS mean_los,
    STDDEV(i.los) AS sd_los,
    AVG(CASE WHEN i.los < 7 THEN 1 ELSE 0 END) * 100 AS percent_los_less_than_7_days
FROM
    physionet-data.mimiciv_3_1_icu.icustays i
INNER JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON i.hadm_id = a.hadm_id
INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON i.subject_id = p.subject_id
WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 35 AND 45
    AND i.los IS NOT NULL
    AND a.hospital_expire_flag IS NOT NULL
GROUP BY
    a.hospital_expire_flag
ORDER BY
    a.hospital_expire_flag;