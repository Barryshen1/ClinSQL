SELECT
    discharge_outcome,
    COUNT(los) AS n,
    ROUND(AVG(los), 2) AS mean_los,
    -- APPROX_QUANTILES returns an array of percentiles. OFFSET(50) gets the 50th percentile (median).
    ROUND(APPROX_QUANTILES(los, 100)[OFFSET(50)], 2) AS median_los,
    ROUND(SUM(CASE WHEN los <= 10 THEN 1 ELSE 0 END) * 100.0 / COUNT(los), 2) AS percent_le_10_days
FROM (
    SELECT
        icu.los,
        CASE
            WHEN adm.hospital_expire_flag = 1 THEN 'in-hospital death'
            WHEN adm.discharge_location = 'HOSPICE' AND adm.hospital_expire_flag = 0 THEN 'hospice'
            WHEN adm.discharge_location IN ('HOME', 'HOME HEALTH CARE') AND adm.hospital_expire_flag = 0 THEN 'home'
            -- Any other discharge_location not explicitly handled by the above conditions,
            -- and not an in-hospital death, will be excluded by the WHERE clause below.
        END AS discharge_outcome
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON icu.subject_id = pat.subject_id
    JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON icu.hadm_id = adm.hadm_id
    WHERE
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 63 AND 73 -- Age range 63-73 inclusive
        AND (
            (adm.hospital_expire_flag = 1) OR
            (adm.discharge_location = 'HOSPICE' AND adm.hospital_expire_flag = 0) OR
            (adm.discharge_location IN ('HOME', 'HOME HEALTH CARE') AND adm.hospital_expire_flag = 0)
        )
) AS sub
GROUP BY
    discharge_outcome
ORDER BY
    discharge_outcome;