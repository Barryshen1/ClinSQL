WITH patient_cohort AS (
    SELECT DISTINCT adm.subject_id, adm.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        ON adm.hadm_id = dx.hadm_id
    WHERE
        pat.gender = 'F'
        AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 57 AND 67
        AND dx.icd_code IN ('785.52', 'R65.21') -- ICD-9 and ICD-10 for Septic Shock
),

-- CTE 2: Consolidate all ultrasound and echocardiogram procedures from different billing code systems.
ultrasound_procedures AS (
    -- Part A: Procedures from ICD codes
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d_proc
        ON proc.icd_code = d_proc.icd_code AND proc.icd_version = d_proc.icd_version
    WHERE
        LOWER(d_proc.long_title) LIKE '%ultrasound%'
        OR LOWER(d_proc.long_title) LIKE '%echocardiogra%'

    UNION ALL

    -- Part B: Procedures from HCPCS/CPT codes
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
    WHERE
        -- CPT codes for diagnostic ultrasound
        (hcpcs_cd >= '76500' AND hcpcs_cd <= '76999')
        -- CPT codes for echocardiography
        OR (hcpcs_cd >= '93300' AND hcpcs_cd <= '93399')
),

-- CTE 3: Count the number of ultrasounds for each admission that had at least one.
ultrasound_counts AS (
    SELECT
        hadm_id,
        COUNT(*) AS ultrasound_count
    FROM ultrasound_procedures
    GROUP BY hadm_id
),

-- CTE 4: Identify all hospital admissions that included an ICU stay.
icu_admissions AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
),

-- CTE 5: Combine cohort with details: LOS, ICU status, and ultrasound count.
admission_details AS (
    SELECT
        cohort.hadm_id,
        -- Categorize Length of Stay (LOS) into specified groups.
        CASE
            WHEN DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 >= 1 AND DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 <= 3 THEN '1-3 days'
            WHEN DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 >= 4 AND DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 <= 7 THEN '4-7 days'
            ELSE NULL
        END AS los_group,
        -- Categorize whether the admission included an ICU stay.
        CASE
            WHEN icu.hadm_id IS NOT NULL THEN 'ICU'
            ELSE 'No ICU'
        END AS icu_group,
        -- Get the count of ultrasounds, defaulting to 0 for admissions with none.
        COALESCE(us.ultrasound_count, 0) AS ultrasound_count
    FROM patient_cohort AS cohort
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON cohort.hadm_id = adm.hadm_id
    LEFT JOIN icu_admissions AS icu
        ON cohort.hadm_id = icu.hadm_id
    LEFT JOIN ultrasound_counts AS us
        ON cohort.hadm_id = us.hadm_id
)

-- Final step: Aggregate results by the defined strata and calculate percentiles.
SELECT
    los_group,
    icu_group,
    COUNT(hadm_id) AS num_admissions,
    APPROX_QUANTILES(ultrasound_count, 100)[OFFSET(25)] AS p25_ultrasounds_per_admission,
    APPROX_QUANTILES(ultrasound_count, 100)[OFFSET(50)] AS p50_ultrasounds_per_admission,
    APPROX_QUANTILES(ultrasound_count, 100)[OFFSET(75)] AS p75_ultrasounds_per_admission
FROM admission_details
WHERE los_group IS NOT NULL -- Only include admissions in the specified LOS ranges.
GROUP BY los_group, icu_group
ORDER BY los_group, icu_group;