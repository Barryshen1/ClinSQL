WITH death_categories AS (
    SELECT
        i.stay_id,
        i.los,
        CASE
            WHEN a.hospital_expire_flag = 1 THEN 'In-hospital'
            WHEN a.discharge_location = 'HOME' THEN 'Home'
            ELSE 'Facility'
        END AS death_location
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON i.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON i.hadm_id = a.hadm_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 87 AND 97
        AND a.deathtime IS NOT NULL
)
SELECT
    death_location,
    COUNT(*) AS n,
    ROUND(AVG(los), 2) AS mean_los,
    ROUND(STDDEV(los), 2) AS sd_los,
    ROUND(100.0 * SUM(CASE WHEN los < 10 THEN 1 ELSE 0 END) / COUNT(*), 2) AS percent_los_less_than_10
FROM death_categories
GROUP BY death_location
ORDER BY death_location;