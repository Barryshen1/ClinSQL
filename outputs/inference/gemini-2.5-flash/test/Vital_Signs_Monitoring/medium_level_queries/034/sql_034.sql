WITH base_cohort_aged_male AS (
    -- Step 1: Base cohort of male ICU patients aged 37-47
    SELECT
        p.subject_id,
        adm.hadm_id,
        icu.stay_id,
        icu.intime,
        icu.outtime
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON adm.hadm_id = icu.hadm_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 37 AND 47
),
stays_with_niv_events AS (
    -- Step 2: Identify stays where noninvasive ventilation (CPAP/BiPAP) was administered
    SELECT DISTINCT ce_niv.stay_id
    FROM
        `physionet-data.mimiciv_3_1_icu.chartevents` ce_niv
    WHERE
        ce_niv.itemid IN (
            224697, -- CPAP/BiPAP pressure
            227187, -- CPAP Pressure
            227176, -- BiPAP Pressure
            225792, -- CPAP Mode
            225793  -- BiPAP Mode
        )
        AND ce_niv.valuenum IS NOT NULL -- Must have a recorded value
        AND ce_niv.valuenum > 0 -- Assuming pressure/mode values are positive
),
target_patient_cohort AS (
    -- Step 3: Combine base cohort with NIV stays to get the final study population
    SELECT
        bc.subject_id,
        bc.hadm_id,
        bc.stay_id,
        bc.intime,
        bc.outtime
    FROM base_cohort_aged_male bc
    INNER JOIN stays_with_niv_events snv
        ON bc.stay_id = snv.stay_id
),
max_dbp_per_stay AS (
    -- Step 4: Get all Diastolic BP readings for the target cohort
    -- Step 5: Find the maximum DBP per stay
    SELECT
        tpc.stay_id,
        MAX(ce.valuenum) AS max_dbp
    FROM
        target_patient_cohort tpc
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON tpc.stay_id = ce.stay_id
    WHERE
        ce.itemid IN (
            220059, -- Diastolic BP
            224643, -- Manual DBP
            227242, -- Diastolic BP (Arterial)
            220180, -- Non Invasive Blood Pressure diastolic
            220181  -- Arterial Blood Pressure diastolic
        )
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum > 0 -- DBP must be positive
        AND ce.charttime BETWEEN tpc.intime AND tpc.outtime -- DBP event within ICU stay timeframe
    GROUP BY
        tpc.stay_id
)
-- Final Step: Calculate the 25th percentile of the maximum DBP values
SELECT
    PERCENTILE_CONT(max_dbp, 0.25) AS dbp_25th_percentile
FROM
    max_dbp_per_stay;