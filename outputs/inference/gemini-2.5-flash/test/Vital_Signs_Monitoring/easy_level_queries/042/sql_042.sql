SELECT
    STDDEV(max_resp_rate) AS sd_patients_max_respiratory_rate
FROM (
    SELECT
        p.subject_id,
        MAX(ce.valuenum) AS max_resp_rate
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON p.subject_id = icu.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON icu.subject_id = ce.subject_id
        AND icu.hadm_id = ce.hadm_id
        AND icu.stay_id = ce.stay_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 63 AND 73
        AND ce.itemid IN (
            220210, -- Respiratory Rate
            224690  -- Respiratory Rate (Spontaneous)
        )
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum > 0
        -- Optional: Consider an upper bound for physiological plausibility, e.g., AND ce.valuenum < 100
    GROUP BY
        p.subject_id
) AS patient_max_respiratory_rates;