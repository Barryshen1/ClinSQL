WITH demographic_icu_stays AS (
    -- Select patients matching age and gender criteria, and their ICU stay details
    SELECT
        p.subject_id,
        adm.hadm_id,
        icu.stay_id,
        icu.intime
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
        AND p.anchor_age BETWEEN 66 AND 76
),
ventilated_patients AS (
    -- Identify unique ICU stays where the patient was invasively ventilated
    -- using common itemids for ventilator modes/settings.
    SELECT DISTINCT
        dis.subject_id,
        dis.hadm_id,
        dis.stay_id,
        dis.intime
    FROM
        demographic_icu_stays dis
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON dis.subject_id = ce.subject_id
        AND dis.stay_id = ce.stay_id
    WHERE
        -- Itemids for Vent Mode (224328) and Vent Info (224329) from d_items typically indicate mechanical ventilation.
        ce.itemid IN (224328, 224329)
),
sbp_measurements AS (
    -- Collect Systolic Blood Pressure (SBP) measurements for the ventilated cohort
    -- within the first 6 hours of their ICU stay.
    SELECT
        vp.subject_id,
        vp.hadm_id,
        vp.stay_id,
        ce.valuenum AS sbp_value
    FROM
        ventilated_patients vp
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON vp.subject_id = ce.subject_id
        AND vp.stay_id = ce.stay_id
    WHERE
        -- Itemid for Arterial Blood Pressure systolic (220050) from d_items
        ce.itemid = 220050
        -- Filter for measurements taken within the first 6 hours of ICU admission
        AND ce.charttime BETWEEN vp.intime AND DATETIME_ADD(vp.intime, INTERVAL 6 HOUR)
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum > 0   -- SBP must be positive
        AND ce.valuenum <= 300 -- Set a reasonable upper limit to exclude erroneous entries
)
-- Calculate the Interquartile Range (IQR) of the collected SBP values
-- using percentile_cont for continuous data.
SELECT
    PERCENTILE_CONT(sbp_value, 0.25) OVER() AS q1_sbp,
    PERCENTILE_CONT(sbp_value, 0.75) OVER() AS q3_sbp,
    (PERCENTILE_CONT(sbp_value, 0.75) OVER() - PERCENTILE_CONT(sbp_value, 0.25) OVER()) AS iqr_sbp
FROM
    sbp_measurements
LIMIT 1;