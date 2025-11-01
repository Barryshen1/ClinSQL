WITH raw_icu_patients AS (
    -- Base population: Female ICU patients aged 83-93
    SELECT
        ie.subject_id,
        ie.hadm_id,
        ie.stay_id,
        ie.intime,
        ie.los AS icu_los,
        adm.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON ie.hadm_id = adm.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 83 AND 93
),
asthma_hadm_ids AS (
    -- Admissions identified with asthma exacerbation diagnosis
    -- Specifically looking for 'exacerbation' in long_title to filter for exacerbation, not just general asthma.
    SELECT DISTINCT
        diag.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did
        ON diag.icd_code = did.icd_code AND diag.icd_version = did.icd_version
    WHERE
        (
            (diag.icd_version = 10 AND diag.icd_code LIKE 'J45%' AND LOWER(did.long_title) LIKE '%exacerbation%')
            OR
            (diag.icd_version = 9 AND diag.icd_code LIKE '493%' AND LOWER(did.long_title) LIKE '%exacerbation%')
        )
),
cohort_details AS (
    -- Classify patients into ASTHMA or NON_ASTHMA cohorts
    -- NON_ASTHMA cohort serves as the age-matched comparison group
    SELECT
        rip.subject_id,
        rip.hadm_id,
        rip.stay_id,
        rip.intime,
        rip.icu_los,
        rip.hospital_expire_flag,
        CASE
            WHEN aha.hadm_id IS NOT NULL THEN 'ASTHMA'
            ELSE 'NON_ASTHMA'
        END AS cohort_type
    FROM
        raw_icu_patients rip
    LEFT JOIN
        asthma_hadm_ids aha
        ON rip.hadm_id = aha.hadm_id
),
instability_scores_72h_avg AS (
    -- Calculate the average instability score per ICU stay for ALL patients in cohort_details within the first 72 hours
    -- ASSUMPTION: "instability score" refers to a numeric `valuenum` recorded in `chartevents` for a specific `itemid`.
    -- For demonstration, Heart Rate (itemid: 220045) is used as a proxy for an "instability score".
    -- !!! IMPORTANT: REPLACE `220045` with the actual itemid for the desired instability score you wish to analyze.
    SELECT
        cd.subject_id,
        cd.hadm_id,
        cd.stay_id,
        cd.cohort_type, -- Include cohort_type so it's available for later filtering/grouping
        AVG(ce.valuenum) AS avg_instability_score_72h_per_stay
    FROM
        cohort_details cd -- Use cohort_details to filter for relevant stays and get cohort_type
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON cd.stay_id = ce.stay_id
    WHERE
        ce.itemid = 220045 -- The placeholder was located here. Replaced with Heart Rate (220045).
        AND ce.valuenum IS NOT NULL
        AND ce.charttime BETWEEN cd.intime AND DATETIME_ADD(cd.intime, INTERVAL 72 HOUR)
    GROUP BY
        cd.subject_id,
        cd.hadm_id,
        cd.stay_id,
        cd.cohort_type -- Group by all identifying keys and cohort_type to pass it along
)
-- Main query to calculate and compare outcomes
SELECT
    'ASTHMA COHORT INSTABILITY SCORE STATISTICS (first 72h)' AS analysis_type,
    'ASTHMA' AS cohort_type,
    SQ1.stddev_instability_score AS stddev_score,
    SQ1.p25_instability_score AS p25_score,
    SQ1.p50_instability_score AS p50_score,
    SQ1.p75_instability_score AS p75_score,
    SQ1.p95_instability_score AS p95_score,
    CAST(NULL AS FLOAT64) AS avg_score_burden,
    CAST(NULL AS FLOAT64) AS avg_icu_los,
    CAST(NULL AS FLOAT64) AS mortality_rate
FROM (
    SELECT
        STDDEV(avg_instability_score_72h_per_stay) AS stddev_instability_score,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY avg_instability_score_72h_per_stay) AS p25_instability_score,
        PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY avg_instability_score_72h_per_stay) AS p50_instability_score,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY avg_instability_score_72h_per_stay) AS p75_instability_score,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY avg_instability_score_72h_per_stay) AS p95_instability_score
    FROM
        instability_scores_72h_avg
    WHERE
        cohort_type = 'ASTHMA' -- Filter here for asthma cohort percentiles
) AS SQ1

UNION ALL

-- For comparison, calculate average burden, LOS, and mortality for ASTHMA and NON_ASTHMA
SELECT
    'COHORT COMPARISON' AS analysis_type,
    cd.cohort_type, -- Use cd.cohort_type from cohort_details
    CAST(NULL AS FLOAT64) AS stddev_score, -- placeholder
    CAST(NULL AS FLOAT64) AS p25_score,
    CAST(NULL AS FLOAT64) AS p50_score,
    CAST(NULL AS FLOAT64) AS p75_score,
    CAST(NULL AS FLOAT64) AS p95_score,
    AVG(iscore.avg_instability_score_72h_per_stay) AS avg_score_burden, -- Score burden (average of per-stay averages)
    AVG(cd.icu_los) AS avg_icu_los,
    AVG(cd.hospital_expire_flag) AS mortality_rate -- 1=expired, 0=not
FROM
    cohort_details cd
LEFT JOIN
    instability_scores_72h_avg iscore
    ON cd.stay_id = iscore.stay_id
GROUP BY
    cd.cohort_type
ORDER BY
    analysis_type DESC, cohort_type
;