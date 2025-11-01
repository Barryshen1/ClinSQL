SELECT
    MIN(initial_hs_tnt) AS min_initial_hs_tnt,
    APPROX_QUANTILES(initial_hs_tnt, 100)[OFFSET(25)] AS p25_initial_hs_tnt,
    APPROX_QUANTILES(initial_hs_tnt, 100)[OFFSET(50)] AS median_initial_hs_tnt, -- 50th percentile is the median
    APPROX_QUANTILES(initial_hs_tnt, 100)[OFFSET(75)] AS p75_initial_hs_tnt,
    MAX(initial_hs_tnt) AS max_initial_hs_tnt
FROM (
    -- Step 3: Filter the cohort based on admission criteria
    SELECT
        tnt.initial_hs_tnt
    FROM (
        -- Step 2: Get the first Troponin T value for each unique admission
        SELECT
            subject_id,
            hadm_id,
            valuenum AS initial_hs_tnt
        FROM (
            -- Step 1: Identify Troponin T lab events and rank them by charttime
            SELECT
                le.subject_id,
                le.hadm_id,
                le.charttime,
                le.valuenum,
                le.labevent_id, -- Used for deterministic tie-breaking
                ROW_NUMBER() OVER (PARTITION BY le.subject_id, le.hadm_id ORDER BY le.charttime, le.labevent_id) AS rn
            FROM
                `physionet-data.mimiciv_3_1_hosp.labevents` AS le
            INNER JOIN
                `physionet-data.mimiciv_3_1_hosp.d_labitems` AS di
                ON le.itemid = di.itemid
            WHERE
                le.itemid = 51003 -- Specific itemid for 'Troponin T'
                AND le.valuenum IS NOT NULL
                AND le.valuenum >= 0 -- Ensure positive values
                AND di.label = 'Troponin T' -- Confirm label matches
                AND le.valueuom = 'ng/mL' -- Ensure consistent units
        ) AS ranked_tnt
        WHERE
            rn = 1
    ) AS tnt
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON tnt.hadm_id = adm.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON tnt.subject_id = pat.subject_id
    WHERE
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 59 AND 69
        AND tnt.initial_hs_tnt > 0.014
);