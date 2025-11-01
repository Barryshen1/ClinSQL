SELECT
    percentiles.q1_max_hr,
    percentiles.q3_max_hr,
    percentiles.q3_max_hr - percentiles.q1_max_hr AS iqr_max_hr
FROM (
    SELECT
        PERCENTILE_CONT(max_hr_per_stay, 0.25) OVER () AS q1_max_hr,
        PERCENTILE_CONT(max_hr_per_stay, 0.75) OVER () AS q3_max_hr
    FROM (
        SELECT
            icu.subject_id,
            icu.stay_id,
            MAX(ce.valuenum) AS max_hr_per_stay
        FROM
            `physionet-data.mimiciv_3_1_icu.icustays` icu
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.patients` p
            ON icu.subject_id = p.subject_id
        INNER JOIN
            `physionet-data.mimiciv_3_1_icu.chartevents` ce
            ON icu.subject_id = ce.subject_id
            AND icu.hadm_id = ce.hadm_id
            AND icu.stay_id = ce.stay_id
        WHERE
            p.gender = 'M'
            AND p.anchor_age BETWEEN 55 AND 65 -- Age anchored to first hospital admission, suitable for ICU stay context
            AND ce.itemid = 220045 -- itemid for Heart Rate
            AND ce.valuenum IS NOT NULL -- Ensure a numeric value exists
            AND ce.valuenum > 0 -- Heart rate must be positive
            AND ce.charttime BETWEEN icu.intime AND icu.outtime -- Ensure measurement is within ICU stay
        GROUP BY
            icu.subject_id,
            icu.stay_id
    ) AS patient_max_hrs
    QUALIFY ROW_NUMBER() OVER () = 1
) AS percentiles;