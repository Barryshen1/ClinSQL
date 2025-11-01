with APPROX_QUANTILES
    ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(75)], 2) AS p75_los_days,   -- Replaced PERCENTILE_CONT with APPROX_QUANTILES
    ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(90)], 2) AS p90_los_days    -- Replaced PERCENTILE_CONT with APPROX_QUANTILES
FROM (
    SELECT
        p.subject_id,
        adm.hadm_id,
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        CASE
            WHEN adm.hospital_expire_flag = 1 THEN 'In-Hospital Death'
            WHEN adm.discharge_location IN ('HOME', 'HOME HEALTH CARE', 'AGAINST ADVICE') THEN 'Home'
            ELSE 'Facility'
        END AS discharge_category
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON adm.subject_id = icu.subject_id AND adm.hadm_id = icu.hadm_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 38 AND 48
        AND adm.dischtime IS NOT NULL
        -- Ensure admission and discharge times are valid for LOS calculation
        AND adm.admittime < adm.dischtime
)
GROUP BY
    discharge_category
ORDER BY
    discharge_category;