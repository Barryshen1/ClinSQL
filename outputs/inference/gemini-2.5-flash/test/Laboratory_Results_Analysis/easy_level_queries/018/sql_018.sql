SELECT
    PERCENTILE_CONT(ph_value, 0.5) OVER() AS median_arterial_ph_on_icu_admission
FROM (
    SELECT
        le.valuenum AS ph_value,
        ROW_NUMBER() OVER (PARTITION BY ie.stay_id ORDER BY le.charttime ASC) AS rn
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON ie.subject_id = le.subject_id
        AND ie.hadm_id = le.hadm_id
    WHERE
        p.gender = 'F'
        AND le.itemid = 50820 -- itemid for Arterial pH as found in d_labitems (label='pH', fluid='ART')
        AND le.valuenum IS NOT NULL
        AND le.charttime >= ie.intime -- Ensure lab was taken during or after ICU admission
)
WHERE
    rn = 1; -- Select only the first arterial pH value for each unique ICU stay;