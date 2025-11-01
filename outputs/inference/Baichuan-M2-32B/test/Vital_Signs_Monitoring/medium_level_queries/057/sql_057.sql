WITH avg_temps AS (
    SELECT 
        icu.stay_id,
        AVG(ce.valuenum) AS avg_temp
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON icu.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
        ON icu.subject_id = ce.subject_id
        AND icu.hadm_id = ce.hadm_id
        AND icu.stay_id = ce.stay_id
        AND ce.itemid = 223761
        AND ce.charttime BETWEEN icu.intime AND icu.outtime
    WHERE 
        p.gender = 'M'
        AND p.anchor_year IS NOT NULL
        AND p.anchor_age IS NOT NULL
        AND icu.intime IS NOT NULL
        AND icu.outtime IS NOT NULL
        AND DATE_DIFF(
            icu.intime, 
            DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE), INTERVAL p.anchor_age YEAR),
            YEAR
        ) BETWEEN 85 AND 95
    GROUP BY icu.stay_id
    HAVING COUNT(ce.valuenum) > 0
)
SELECT 
    IFNULL(
        (SELECT COUNT(*) FROM avg_temps WHERE avg_temp <= 36.0) * 100.0 / 
        NULLIF((SELECT COUNT(*) FROM avg_temps), 0),
        NULL
    ) AS percentile_rank
FROM avg_temps
LIMIT 1;