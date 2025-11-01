WITH TargetICUPatients AS (
    SELECT
        p.subject_id,
        adm.hadm_id,
        icu.stay_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON adm.hadm_id = icu.hadm_id
        AND p.subject_id = icu.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age = 89 -- Filtering for 89-year-old patients
),
FirstSerumSodium AS (
    SELECT
        tip.subject_id,
        tip.hadm_id,
        tip.stay_id,
        le.valuenum,
        ROW_NUMBER() OVER (PARTITION BY tip.stay_id ORDER BY le.charttime ASC) AS rn
    FROM
        TargetICUPatients tip
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON tip.subject_id = le.subject_id
        AND tip.hadm_id = le.hadm_id
    WHERE
        le.itemid = 50983 -- itemid for 'Sodium, Serum' found in d_labitems
        AND le.valuenum IS NOT NULL -- Exclude records with no numeric value
        -- Optional: Add a clinically plausible range to exclude erroneous values, e.g.,
        -- AND le.valuenum BETWEEN 100 AND 180
)
SELECT
    -- Calculate the IQR using APPROX_QUANTILES and array indexing.
    -- APPROX_QUANTILES(value_column, number_of_quantiles) returns an array.
    -- For 4 quantiles, it returns 5 values: [min, Q1, Q2 (median), Q3, max].
    APPROX_QUANTILES(fsn.valuenum, 4)[OFFSET(3)] - APPROX_QUANTILES(fsn.valuenum, 4)[OFFSET(1)] AS iqr_first_serum_sodium
FROM
    FirstSerumSodium fsn
WHERE
    fsn.rn = 1; -- Select only the first serum sodium measurement for each ICU stay;