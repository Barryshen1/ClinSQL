WITH icu_base AS (
    -- Select base ICU stay and patient demographic information
    SELECT
        ie.subject_id,
        ie.hadm_id,
        ie.stay_id,
        ie.intime,
        ie.outtime,
        ie.los,
        adm.hospital_expire_flag,
        pat.gender,
        -- Calculate age at ICU admission
        pat.anchor_age + (EXTRACT(YEAR FROM ie.intime) - pat.anchor_year) AS age_at_icu_admission
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON ie.hadm_id = adm.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON ie.subject_id = pat.subject_id
    WHERE
        pat.gender = 'M'
        AND (pat.anchor_age + (EXTRACT(YEAR FROM ie.intime) - pat.anchor_year)) BETWEEN 55 AND 65
),
hfnc_in_24hr AS (
    -- Identify patients who received High Flow Nasal Cannula (HFNC) within the first 24 hours of ICU admission
    SELECT DISTINCT
        ce.stay_id
    FROM
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN
        icu_base ib
        ON ce.stay_id = ib.stay_id
    WHERE
        ce.itemid = 227289 -- itemid for 'High Flow Nasal cannula'
        AND ce.charttime BETWEEN ib.intime AND DATETIME_ADD(ib.intime, INTERVAL 24 HOUR)
),
acute_resp_failure_diag AS (
    -- Identify patients with a primary diagnosis of acute respiratory failure (ICD-10 code J96.x)
    SELECT DISTINCT
        da.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` da
    WHERE
        da.icd_version = 10 -- Using ICD-10
        AND da.icd_code LIKE 'J96%' -- J96: Respiratory failure, not elsewhere classified
        AND da.seq_num = 1 -- Limit to primary diagnosis for matching
),
cohort_with_flags AS (
    -- Combine base cohort with HFNC and acute respiratory failure flags
    SELECT
        ib.*,
        CASE WHEN hfnc.stay_id IS NOT NULL THEN TRUE ELSE FALSE END AS has_hfnc_24hr,
        CASE WHEN arf.hadm_id IS NOT NULL THEN TRUE ELSE FALSE END AS has_acute_resp_failure
    FROM
        icu_base ib
    LEFT JOIN
        hfnc_in_24hr hfnc
        ON ib.stay_id = hfnc.stay_id
    INNER JOIN -- Use INNER JOIN here to ensure "condition-matched" by requiring acute respiratory failure
        acute_resp_failure_diag arf
        ON ib.hadm_id = arf.hadm_id
),
final_cohort_groups AS (
    -- Assign patients to 'HFNC_Case' or 'Control' groups
    SELECT
        cf.*,
        CASE
            WHEN cf.has_hfnc_24hr THEN 'HFNC_Case'
            ELSE 'Control'
        END AS group_type
    FROM
        cohort_with_flags cf
),
vitals_first_24hr AS (
    -- Extract relevant vital signs within the first 24 hours for the final cohort
    SELECT
        fcg.stay_id,
        fcg.group_type,
        fcg.los,
        fcg.hospital_expire_flag,
        ce.charttime,
        MAX(CASE WHEN ce.itemid = 220045 AND ce.valuenum IS NOT NULL AND ce.valuenum > 0 THEN ce.valuenum END) AS heart_rate,    -- Heart Rate (bpm)
        MAX(CASE WHEN ce.itemid = 220179 AND ce.valuenum IS NOT NULL AND ce.valuenum > 0 THEN ce.valuenum END) AS sbp,           -- BP Systolic (mmHg)
        MAX(CASE WHEN ce.itemid = 220052 AND ce.valuenum IS NOT NULL AND ce.valuenum > 0 THEN ce.valuenum END) AS map            -- Arterial Blood Pressure mean (mmHg)
    FROM
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN
        final_cohort_groups fcg
        ON ce.stay_id = fcg.stay_id
    WHERE
        ce.charttime BETWEEN fcg.intime AND DATETIME_ADD(fcg.intime, INTERVAL 24 HOUR)
        AND ce.itemid IN (220045, 220179, 220052) -- Filter for specific vital sign itemids
    GROUP BY
        fcg.stay_id, fcg.group_type, fcg.los, fcg.hospital_expire_flag, ce.charttime
),
patient_vitals_summary AS (
    -- Calculate counts of tachycardia and hypotension events per patient stay based on distinct charttimes
    SELECT
        stay_id,
        group_type,
        los,
        hospital_expire_flag,
        COUNT(DISTINCT charttime) AS total_valid_vitals_charts,
        COUNT(DISTINCT CASE WHEN heart_rate > 100 THEN charttime END) AS tachy_charts, -- Tachycardia: HR > 100 bpm
        COUNT(DISTINCT CASE WHEN sbp < 90 OR map < 60 THEN charttime END) AS hypo_charts -- Hypotension: SBP < 90 mmHg OR MAP < 60 mmHg
    FROM
        vitals_first_24hr
    GROUP BY
        stay_id, group_type, los, hospital_expire_flag
),
patient_metrics AS (
    -- Calculate final patient-level metrics
    SELECT
        stay_id,
        group_type,
        los,
        hospital_expire_flag,
        -- Calculate burdens as proportion of charttimes with respective events
        SAFE_DIVIDE(tachy_charts, total_valid_vitals_charts) AS tachycardia_burden,
        SAFE_DIVIDE(hypo_charts, total_valid_vitals_charts) AS hypotension_burden
    FROM
        patient_vitals_summary
)
-- Final aggregation to get median, percentiles, and mortality for each group
SELECT
    group_type,
    -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
    -- Note on "Instability Score": This metric is not a standard pre-calculated field in MIMIC-IV.
    -- Without a specific definition (e.g., how to combine vital signs into a score), it cannot be directly computed.
    -- The request for 'tachycardia and hypotension burden' directly addresses aspects of physiological instability.
    -- Therefore, this query will provide the requested burden metrics rather than a generic "instability score".
    -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

    -- Tachycardia Burden: Median and Percentiles
    APPROX_QUANTILES(t.tachycardia_burden, 100)[OFFSET(50)] AS tachycardia_burden_median,
    APPROX_QUANTILES(t.tachycardia_burden, 100)[OFFSET(25)] AS tachycardia_burden_p25,
    APPROX_QUANTILES(t.tachycardia_burden, 100)[OFFSET(75)] AS tachycardia_burden_p75,
    APPROX_QUANTILES(t.tachycardia_burden, 100)[OFFSET(95)] AS tachycardia_burden_p95,

    -- Hypotension Burden: Median and Percentiles
    APPROX_QUANTILES(t.hypotension_burden, 100)[OFFSET(50)] AS hypotension_burden_median,
    APPROX_QUANTILES(t.hypotension_burden, 100)[OFFSET(25)] AS hypotension_burden_p25,
    APPROX_QUANTILES(t.hypotension_burden, 100)[OFFSET(75)] AS hypotension_burden_p75,
    APPROX_QUANTILES(t.hypotension_burden, 100)[OFFSET(95)] AS hypotension_burden_p95,

    -- ICU Length of Stay (LOS): Median and Percentiles
    APPROX_QUANTILES(t.los, 100)[OFFSET(50)] AS icu_los_median,
    APPROX_QUANTILES(t.los, 100)[OFFSET(25)] AS icu_los_p25,
    APPROX_QUANTILES(t.los, 100)[OFFSET(75)] AS icu_los_p75,
    APPROX_QUANTILES(t.los, 100)[OFFSET(95)] AS icu_los_p95,

    -- Hospital Mortality: Percentage
    AVG(t.hospital_expire_flag) AS hospital_mortality_percentage
FROM
    patient_metrics t
WHERE
    t.group_type IS NOT NULL -- Ensures only patients in defined groups are included
GROUP BY
    group_type
ORDER BY
    group_type;