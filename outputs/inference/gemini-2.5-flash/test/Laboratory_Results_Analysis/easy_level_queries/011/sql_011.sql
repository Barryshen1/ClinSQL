SELECT
    STDDEV(peak_potassium_per_stay) AS stddev_peak_serum_potassium_mEqL
FROM (
    SELECT
        p.subject_id,
        ics.stay_id,
        MAX(le.valuenum) AS peak_potassium_per_stay
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` ics
        ON p.subject_id = ics.subject_id
    JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON p.subject_id = le.subject_id
        AND ics.hadm_id = le.hadm_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age = 56
        AND le.itemid = 50971 -- itemid for 'Potassium, Serum' based on d_labitems
        AND le.valuenum IS NOT NULL
        -- Ensure the lab event occurred during the specific ICU stay
        AND le.charttime BETWEEN ics.intime AND ics.outtime
    GROUP BY
        p.subject_id,
        ics.stay_id
) AS peak_values_per_stay;