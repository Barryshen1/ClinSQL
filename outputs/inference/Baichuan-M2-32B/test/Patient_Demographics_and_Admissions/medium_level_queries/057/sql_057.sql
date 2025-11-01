WITH filtered_data AS (
    SELECT
        a.hadm_id,
        a.subject_id,
        a.hospital_expire_flag,
        a.discharge_location,
        i.stay_id,
        i.los AS icu_los,
        CASE
            WHEN a.hospital_expire_flag = 1 THEN 'in-hospital death'
            WHEN a.discharge_location = 'Home' THEN 'home'
            WHEN a.discharge_location = 'Hospice care' THEN 'hospice'
            ELSE NULL
        END AS discharge_outcome
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON i.subject_id = a.subject_id
        AND i.hadm_id = a.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 40 AND 50
        AND i.stay_id IS NOT NULL
        AND i.los IS NOT NULL
)
SELECT
    discharge_outcome,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY icu_los) AS p50,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY icu_los) AS p75,
    PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY icu_los) AS p90,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY icu_los) AS p95,
    (SUM(CASE WHEN icu_los <= 7 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS pct_le_7_days
FROM
    filtered_data
WHERE
    discharge_outcome IS NOT NULL
GROUP BY
    discharge_outcome
ORDER BY
    discharge_outcome;