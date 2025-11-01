SELECT
    icu_pop.discharge_outcome,
    -- Calculate LOS approximate percentiles for each discharge outcome group using APPROX_QUANTILES
    APPROX_QUANTILES(icu_pop.los, 100)[OFFSET(50)] AS los_p50,
    APPROX_QUANTILES(icu_pop.los, 100)[OFFSET(75)] AS los_p75,
    APPROX_QUANTILES(icu_pop.los, 100)[OFFSET(90)] AS los_p90,
    APPROX_QUANTILES(icu_pop.los, 100)[OFFSET(95)] AS los_p95,
    -- Calculate percentage of LOS <= 7 days
    (COUNTIF(icu_pop.los <= 7) * 100.0 / COUNT(icu_pop.los)) AS percent_los_le_7_days
FROM
    (
        SELECT
            icu.subject_id,
            icu.hadm_id,
            icu.stay_id,
            icu.los,
            -- Categorize discharge outcome based on hospital admission details
            CASE
                -- Check for in-hospital death first, as it overrides discharge location
                WHEN adm.hospital_expire_flag = 1 THEN 'In-hospital Death'
                -- Use LIKE for partial matches and case-insensitivity if needed, but per question it's specific
                WHEN LOWER(adm.discharge_location) LIKE '%hospice%' THEN 'Hospice'
                WHEN LOWER(adm.discharge_location) LIKE '%home%' THEN 'Home'
                ELSE NULL -- Exclude other discharge locations not specified in the question
            END AS discharge_outcome
        FROM
            `physionet-data.mimiciv_3_1_icu.icustays` AS icu
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
            ON icu.subject_id = adm.subject_id AND icu.hadm_id = adm.hadm_id
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.patients` AS pat
            ON icu.subject_id = pat.subject_id
        WHERE
            pat.gender = 'F' -- Filter for female patients
            AND pat.anchor_age BETWEEN 40 AND 50 -- Filter for age between 40 and 50
    ) AS icu_pop
WHERE
    icu_pop.discharge_outcome IS NOT NULL -- Only include the three specified discharge outcomes
GROUP BY
    icu_pop.discharge_outcome
ORDER BY
    icu_pop.discharge_outcome;