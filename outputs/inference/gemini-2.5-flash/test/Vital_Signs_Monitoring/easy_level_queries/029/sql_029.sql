SELECT
    PERCENTILE_CONT(first_spo2.spo2_value, 0.75) OVER() - PERCENTILE_CONT(first_spo2.spo2_value, 0.25) OVER() AS interquartile_range_spo2
FROM
    (
        SELECT
            p.subject_id,
            ce.valuenum AS spo2_value,
            ROW_NUMBER() OVER(PARTITION BY p.subject_id ORDER BY ce.charttime ASC) AS rn
        FROM
            `physionet-data.mimiciv_3_1_hosp.patients` p
        INNER JOIN
            `physionet-data.mimiciv_3_1_icu.chartevents` ce
            ON p.subject_id = ce.subject_id
        WHERE
            p.gender = 'M'
            AND p.anchor_age BETWEEN 62 AND 72
            AND ce.itemid = 220277 -- itemid for 'O2 Saturation Pulseoxymetry'
            AND ce.valuenum IS NOT NULL
            AND ce.valuenum > 0 -- SpO2 values should be positive
            AND ce.valuenum <= 100 -- SpO2 values are percentages, typically 0-100
    ) AS first_spo2
WHERE
    first_spo2.rn = 1
QUALIFY
    ROW_NUMBER() OVER() = 1; -- Ensures only one row for the final aggregate result;