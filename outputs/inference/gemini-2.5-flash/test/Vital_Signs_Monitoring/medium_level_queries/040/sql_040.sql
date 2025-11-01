SELECT
    -- Step 5: Find the minimum of the per-stay mean SBP values.
    MIN(AvgPerStaySBP.mean_sbp) AS minimum_per_stay_mean_sbp
FROM
    (
        -- Step 4: Calculate the mean SBP for each ICU stay that meets all criteria.
        SELECT
            sbp_ce.stay_id, -- Corrected: Used sbp_ce alias
            AVG(sbp_ce.valuenum) AS mean_sbp -- Corrected: Used sbp_ce alias and valuenum column
        FROM
            `physionet-data.mimiciv_3_1_icu.chartevents` AS sbp_ce
        -- The join to d_items is not necessary here as itemids are hardcoded
        -- JOIN
        --    `physionet-data.mimiciv_3_1_icu.d_items` AS sbp_di
        --    ON sbp_ce.itemid = sbp_di.itemid
        JOIN
            -- Subquery to filter for patients in the target cohort
            (
                -- Step 1: Identify the target patient cohort (female, aged 81-91 at admission, having an ICU stay)
                SELECT
                    p.subject_id,
                    ad.hadm_id,
                    ie.stay_id
                FROM
                    `physionet-data.mimiciv_3_1_hosp.patients` AS p
                JOIN
                    `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
                    ON p.subject_id = ad.subject_id
                JOIN
                    `physionet-data.mimiciv_3_1_icu.icustays` AS ie
                    ON ad.hadm_id = ie.hadm_id
                WHERE
                    p.gender = 'F'
                    AND p.anchor_age BETWEEN 81 AND 90 -- anchor_age 90 includes 90+ year olds, appropriate for "81-91" range given data caps
            ) AS PatientCohort
            ON sbp_ce.stay_id = PatientCohort.stay_id
        JOIN
            -- Subquery to identify ICU stays where HFNC was administered
            (
                -- Step 2: Identify unique ICU stays (stay_id) where high-flow nasal cannula (HFNC) was administered.
                SELECT DISTINCT
                    ce_hfnc.stay_id
                FROM
                    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce_hfnc
                WHERE
                    ce_hfnc.itemid = 227299 -- itemid for 'Hi flow nasal cannula' from d_items
                    AND ce_hfnc.valuenum IS NOT NULL -- A recorded value implies usage/measurement
            ) AS HFNC_Stays
            ON sbp_ce.stay_id = HFNC_Stays.stay_id
        WHERE
            -- Step 3: Filter for valid Systolic Blood Pressure measurements.
            sbp_ce.itemid IN (
                220050, -- Arterial Blood Pressure systolic
                220179  -- Non Invasive Blood Pressure systolic
            )
            AND sbp_ce.valuenum IS NOT NULL
            AND sbp_ce.valuenum > 0    -- Physiologically plausible SBP values
            AND sbp_ce.valuenum < 300  -- Upper bound for SBP
        GROUP BY
            sbp_ce.stay_id
    ) AS AvgPerStaySBP;