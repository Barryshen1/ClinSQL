SELECT
    (CAST(SUM(CASE WHEN t2.average_heart_rate <= 110 THEN 1 ELSE 0 END) AS FLOAT64) / COUNT(t2.average_heart_rate)) * 100 AS percentile_of_110_bpm
FROM
    (
        SELECT
            icu.stay_id, -- Corrected alias from pds to icu
            AVG(ce.valuenum) AS average_heart_rate
        FROM
            `physionet-data.mimiciv_3_1_hosp.patients` p
        JOIN
            `physionet-data.mimiciv_3_1_icu.icustays` icu
            ON p.subject_id = icu.subject_id
        JOIN
            `physionet-data.mimiciv_3_1_icu.chartevents` ce
            ON icu.stay_id = ce.stay_id
        WHERE
            p.gender = 'F'
            AND p.anchor_age BETWEEN 80 AND 90
            AND ce.itemid = 220045 -- ItemID for Heart Rate
            AND ce.valuenum IS NOT NULL
            AND ce.valuenum > 0
            AND ce.valuenum < 300 -- Physiological range for adult Heart Rate
        GROUP BY
            icu.stay_id -- Simplified GROUP BY to just stay_id for per-stay average
    ) AS t2;