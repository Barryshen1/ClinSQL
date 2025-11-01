SELECT
    APPROX_QUANTILES(frr.valuenum, 100)[OFFSET(25)] AS p25_first_respiratory_rate
FROM
    (
        SELECT
            ce.stay_id,
            ce.valuenum,
            ROW_NUMBER() OVER (PARTITION BY ce.stay_id ORDER BY ce.charttime ASC) AS rn
        FROM
            `physionet-data.mimiciv_3_1_icu.chartevents` ce
        INNER JOIN
            `physionet-data.mimiciv_3_1_icu.icustays` icu
            ON ce.subject_id = icu.subject_id
            AND ce.hadm_id = icu.hadm_id
            AND ce.stay_id = icu.stay_id
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.patients` pats
            ON icu.subject_id = pats.subject_id
        WHERE
            pats.gender = 'F'
            AND pats.anchor_age BETWEEN 51 AND 61
            AND ce.itemid = 220210 -- Itemid for Respiratory Rate
            AND ce.valuenum IS NOT NULL
            AND ce.valuenum > 0
            AND ce.valuenum < 100 -- Filter for physiologically plausible respiratory rates
            AND ce.charttime >= icu.intime -- Ensure measurement is at or after ICU admission
    ) AS frr
WHERE
    frr.rn = 1;