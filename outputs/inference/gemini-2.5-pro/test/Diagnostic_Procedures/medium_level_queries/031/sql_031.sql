WITH
-- 1. Identify the base cohort of female AKI patients aged 38-48.
aki_admissions AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        -- Calculate length of stay in days, rounding up to the nearest whole day.
        CEIL(DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0) AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    -- Ensure the admission has an AKI diagnosis.
    WHERE adm.hadm_id IN (
        SELECT DISTINCT hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        WHERE
            -- ICD-10 codes for Acute Kidney Injury
            icd_code LIKE 'N17%'
            -- ICD-9 codes for Acute Kidney Failure
            OR icd_code LIKE '584%'
    )
    AND pat.gender = 'F'
    AND pat.anchor_age BETWEEN 38 AND 48
    -- Pre-filter to ensure dischtime is after admittime to calculate a valid LOS
    AND adm.dischtime > adm.admittime
),

-- 2. Count non-invasive diagnostic procedures (defined as diagnostic radiology) for each admission.
diagnostic_counts AS (
    SELECT
        hcp.hadm_id,
        COUNT(*) AS num_diagnostics
    FROM
        `physionet-data.mimiciv_3_1_hosp.hcpcsevents` AS hcp
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_hcpcs` AS d_hcp
        ON hcp.hcpcs_cd = d_hcp.code
    WHERE
        d_hcp.category = 2 -- '2' is the category for Diagnostic Radiology Services
    GROUP BY
        hcp.hadm_id
),

-- 3. Combine cohort with LOS, ICU status, and diagnostic counts.
final_cohort AS (
    SELECT
        aki.hadm_id,
        aki.los_days,
        -- If an admission had no diagnostic procedures, its count will be 0.
        COALESCE(diag.num_diagnostics, 0) AS num_diagnostics,
        CASE
            WHEN icu.hadm_id IS NOT NULL THEN 'ICU'
            ELSE 'No ICU'
        END AS icu_status,
        CASE
            WHEN aki.los_days BETWEEN 1 AND 4 THEN '1-4 day stay'
            WHEN aki.los_days BETWEEN 5 AND 7 THEN '5-7 day stay'
        END AS stay_length_group
    FROM
        aki_admissions AS aki
    LEFT JOIN
        diagnostic_counts AS diag
        ON aki.hadm_id = diag.hadm_id
    LEFT JOIN (
        -- Get a unique list of admissions that had an ICU stay.
        SELECT DISTINCT hadm_id FROM `physionet-data.mimiciv_3_1_icu.icustays`
    ) AS icu
        ON aki.hadm_id = icu.hadm_id
    -- Filter for the specific length of stay groups requested.
    WHERE aki.los_days BETWEEN 1 AND 7
)

-- 4. Final aggregation to compute statistics for each stratum.
SELECT
    stay_length_group,
    icu_status,
    COUNT(hadm_id) AS number_of_admissions,
    ROUND(AVG(num_diagnostics), 2) AS mean_diagnostics,
    MIN(num_diagnostics) AS min_diagnostics,
    MAX(num_diagnostics) AS max_diagnostics
FROM
    final_cohort
GROUP BY
    stay_length_group,
    icu_status
ORDER BY
    stay_length_group,
    icu_status;