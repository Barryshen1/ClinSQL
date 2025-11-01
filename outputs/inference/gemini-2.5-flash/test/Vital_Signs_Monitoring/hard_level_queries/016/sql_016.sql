WITH cohort_base AS (
    SELECT
        p.subject_id,
        adm.hadm_id,
        icu.stay_id,
        icu.intime,
        icu.outtime,
        p.anchor_age,
        adm.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON adm.hadm_id = icu.hadm_id AND p.subject_id = icu.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 57 AND 67
),
transplant_diagnoses AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_code IN (
        -- ICD-9 transplant codes (V42.x) stored as V42X
        'V420', 'V421', 'V426', 'V427', 'V428', 'V4281', 'V4282', 'V4283', 'V4284', 'V4289',
        -- ICD-10 transplant codes (Z94.x) stored as Z94X
        'Z940', 'Z941', 'Z942', 'Z943', 'Z944', 'Z948', 'Z9481', 'Z9482', 'Z9483', 'Z9484', 'Z9485', 'Z949'
    )
),
patient_cohort_final AS (
    SELECT
        cb.subject_id,
        cb.hadm_id,
        cb.stay_id,
        cb.intime,
        cb.outtime,
        cb.hospital_expire_flag,
        -- Calculate ICU LOS in days
        DATETIME_DIFF(cb.outtime, cb.intime, HOUR) / 24.0 AS icu_los_days,
        -- Classify transplant status
        CASE WHEN td.hadm_id IS NOT NULL THEN 'Transplant' ELSE 'Non-Transplant' END AS transplant_status
    FROM
        cohort_base cb
    LEFT JOIN
        transplant_diagnoses td
        ON cb.hadm_id = td.hadm_id
),
vitals_first_72h AS (
    SELECT
        ce.subject_id,
        ce.stay_id,
        -- Collect distinct charttimes for each event type
        ARRAY_AGG(DISTINCT CASE WHEN ce.itemid = 223762 AND ce.valuenum > 38.5 THEN ce.charttime END IGNORE NULLS) AS fever_charttimes,
        ARRAY_AGG(DISTINCT CASE WHEN ce.itemid = 220277 AND ce.valuenum < 90 THEN ce.charttime END IGNORE NULLS) AS spo2_charttimes,
        ARRAY_AGG(DISTINCT CASE WHEN ce.itemid = 220210 AND ce.valuenum > 20 THEN ce.charttime END IGNORE NULLS) AS rr_charttimes
    FROM
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN
        patient_cohort_final pcf
        ON ce.subject_id = pcf.subject_id
        AND ce.stay_id = pcf.stay_id
    WHERE
        ce.charttime >= pcf.intime
        AND ce.charttime < DATETIME_ADD(pcf.intime, INTERVAL 72 HOUR) -- Correctly capture first 72 hours (exclusive of 72h mark)
        AND ce.itemid IN (223762, 220277, 220210) -- Filter for relevant itemids for performance
        AND ce.valuenum IS NOT NULL -- Ensure only valid numeric values are considered
    GROUP BY
        ce.subject_id, ce.stay_id
)
SELECT
    pdws.transplant_status,
    -- Median and Percentiles for Composite Instability Score
    APPROX_QUANTILES(pdws.composite_instability_score, 100)[OFFSET(50)] AS median_instability_score,
    APPROX_QUANTILES(pdws.composite_instability_score, 100)[OFFSET(25)] AS p25_instability_score,
    APPROX_QUANTILES(pdws.composite_instability_score, 100)[OFFSET(75)] AS p75_instability_score,
    -- Median and Percentiles for ICU LOS
    APPROX_QUANTILES(pdws.icu_los_days, 100)[OFFSET(50)] AS median_icu_los_days,
    APPROX_QUANTILES(pdws.icu_los_days, 100)[OFFSET(25)] AS p25_icu_los_days,
    APPROX_QUANTILES(pdws.icu_los_days, 100)[OFFSET(75)] AS p75_icu_los_days,
    -- Mortality Rate
    AVG(CASE WHEN pdws.hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END) AS mortality_rate
FROM
    (
        SELECT
            pcf.subject_id,
            pcf.hadm_id,
            pcf.stay_id,
            pcf.transplant_status,
            pcf.icu_los_days,
            pcf.hospital_expire_flag,
            -- Calculate composite instability score: sum of distinct event counts
            COALESCE(ARRAY_LENGTH(v72.fever_charttimes), 0) +
            COALESCE(ARRAY_LENGTH(v72.spo2_charttimes), 0) +
            COALESCE(ARRAY_LENGTH(v72.rr_charttimes), 0) AS composite_instability_score
        FROM
            patient_cohort_final pcf
        LEFT JOIN
            vitals_first_72h v72
            ON pcf.subject_id = v72.subject_id AND pcf.stay_id = v72.stay_id
        WHERE
            pcf.icu_los_days IS NOT NULL -- Ensure valid LOS for aggregation
    ) AS pdws
GROUP BY
    pdws.transplant_status
ORDER BY
    pdws.transplant_status;