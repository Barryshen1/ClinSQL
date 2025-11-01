WITH patient_cohort AS (
    -- Step 1: Identify male patients aged 81-91 at the time of admission
    SELECT DISTINCT
        pat.subject_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON pat.subject_id = adm.subject_id
    WHERE
        pat.gender = 'M'
        AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 81 AND 91
),

all_ecg_procs AS (
    -- Step 2: Gather all ECG/Telemetry procedure codes from both ICD and HCPCS tables
    -- ICD procedures
    SELECT
        proc.subject_id,
        proc.icd_code AS proc_code
    FROM
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
    JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d_proc
        ON proc.icd_code = d_proc.icd_code AND proc.icd_version = d_proc.icd_version
    WHERE
        LOWER(d_proc.long_title) LIKE '%electrocardiogram%'
        OR LOWER(d_proc.long_title) LIKE '%telemetry%'

    UNION ALL

    -- HCPCS procedures
    SELECT
        hcpcs.subject_id,
        hcpcs.hcpcs_cd AS proc_code
    FROM
        `physionet-data.mimiciv_3_1_hosp.hcpcsevents` AS hcpcs
    JOIN
        `physionet-data.mimiciv_3_1_hosp.d_hcpcs` AS d_hcpcs
        ON hcpcs.hcpcs_cd = d_hcpcs.code
    WHERE
        LOWER(d_hcpcs.long_description) LIKE '%electrocardiogram%'
        OR LOWER(d_hcpcs.short_description) LIKE '%ecg%'
        OR LOWER(d_hcpcs.long_description) LIKE '%telemetry%'
),

patient_proc_counts AS (
    -- Step 3: Count the number of distinct procedure codes for each patient in the cohort
    SELECT
        cohort.subject_id,
        COUNT(DISTINCT procs.proc_code) AS num_distinct_codes
    FROM
        patient_cohort AS cohort
    LEFT JOIN
        all_ecg_procs AS procs
        ON cohort.subject_id = procs.subject_id
    GROUP BY
        cohort.subject_id
)

-- Step 4: Calculate the standard deviation of the per-patient counts
SELECT
    STDDEV(num_distinct_codes) AS sd_distinct_ecg_codes
FROM
    patient_proc_counts;