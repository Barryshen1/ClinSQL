SELECT
    discharge_outcome,
    COUNT(stay_id) AS n,
    ROUND(AVG(los), 2) AS mean_los_days,
    ROUND(STDDEV(los), 2) AS stddev_los_days,
    ROUND(SUM(CASE WHEN los < 10 THEN 1 ELSE 0 END) * 100.0 / COUNT(stay_id), 2) AS percent_los_lt_10_days
FROM (
    SELECT
        icu.stay_id,
        icu.los,
        CASE
            WHEN adm.hospital_expire_flag = 1 THEN 'In-hospital death'
            WHEN adm.discharge_location IN ('Home', 'Home Health Care') THEN 'Discharged Home'
            ELSE 'Discharged to Facility'
        END AS discharge_outcome
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` icu
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON icu.hadm_id = adm.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON icu.subject_id = pat.subject_id
    WHERE
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 87 AND 97
) AS icu_los_categorized
GROUP BY
    discharge_outcome
ORDER BY
    discharge_outcome;