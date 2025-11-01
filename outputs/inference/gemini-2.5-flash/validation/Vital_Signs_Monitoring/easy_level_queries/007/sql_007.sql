SELECT
    STDDEV(frr.respiratory_rate_value) AS sd_of_first_respiratory_rate
FROM
    (
        -- CTE to find the chronologically first respiratory rate for each qualifying ICU stay
        SELECT
            ce.valuenum AS respiratory_rate_value,
            ROW_NUMBER() OVER (PARTITION BY icu.stay_id ORDER BY ce.charttime ASC) AS rn
        FROM
            `physionet-data.mimiciv_3_1_hosp.patients` p
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.admissions` a
            ON p.subject_id = a.subject_id
        INNER JOIN
            `physionet-data.mimiciv_3_1_icu.icustays` icu
            ON a.subject_id = icu.subject_id AND a.hadm_id = icu.hadm_id
        INNER JOIN
            `physionet-data.mimiciv_3_1_icu.chartevents` ce
            ON icu.subject_id = ce.subject_id
            AND icu.hadm_id = ce.hadm_id
            AND icu.stay_id = ce.stay_id
        WHERE
            p.gender = 'F'
            -- Calculate age at admission
            AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 73 AND 83
            AND ce.itemid = 220210 -- Itemid for 'Respiratory Rate' from d_items
            AND ce.valuenum IS NOT NULL
            AND ce.valuenum > 0 -- Exclude null, zero, or improbable negative rates
            AND ce.charttime >= icu.intime -- Only consider measurements at or after ICU admission
    ) AS frr
WHERE
    frr.rn = 1;