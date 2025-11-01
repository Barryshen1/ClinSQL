WITH chest_pain_admissions AS (
    SELECT DISTINCT
        diag.subject_id,
        diag.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
        ON diag.icd_code = d_diag.icd_code
        AND diag.icd_version = d_diag.icd_version
    WHERE
        LOWER(d_diag.long_title) LIKE '%chest pain%'
),
first_troponin_t_measurements AS (
    -- Step 2: Identify the first hs-Troponin T measurement for each hospital admission
    SELECT
        le.subject_id,
        le.hadm_id,
        le.valuenum AS first_troponin_valuenum,
        ROW_NUMBER() OVER (PARTITION BY le.subject_id, le.hadm_id ORDER BY le.charttime, le.labevent_id) AS rn
    FROM
        `physionet-data.mimiciv_3_1_hosp.labevents` le
    WHERE
        le.itemid = 51002 -- ItemID for Troponin T (commonly used for hs-TnT in MIMIC-IV studies)
        AND le.valuenum IS NOT NULL
        AND le.valuenum >= 0 -- Exclude potentially erroneous negative values
),
troponin_99th_percentile AS (
    -- Step 1: Calculate the 99th percentile for hs-Troponin T values globally
    SELECT
        PERCENTILE_CONT(le.valuenum, 0.99) AS threshold_value -- FIX: Added 'le.valuenum' as the required first argument.
                                             -- REFINEMENT: Removed OVER() and QUALIFY as PERCENTILE_CONT without OVER()
                                             -- correctly produces a single aggregate row for the entire dataset.
    FROM
        `physionet-data.mimiciv_3_1_hosp.labevents` le
    WHERE
        le.itemid = 51002 -- ItemID for Troponin T
        AND le.valuenum IS NOT NULL
        AND le.valuenum >= 0
),
identified_cohort AS (
    SELECT
        p.subject_id,
        adm.hadm_id,
        first_troponin.first_troponin_valuenum,
        adm.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON adm.subject_id = p.subject_id
    INNER JOIN
        chest_pain_admissions cpa
        ON adm.subject_id = cpa.subject_id AND adm.hadm_id = cpa.hadm_id
    INNER JOIN
        first_troponin_t_measurements first_troponin
        ON adm.subject_id = first_troponin.subject_id AND adm.hadm_id = first_troponin.hadm_id
    CROSS JOIN -- Use CROSS JOIN for scalar CTE
        troponin_99th_percentile t99
    WHERE
        p.gender = 'M'
        AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 64 AND 74
        AND first_troponin.rn = 1 -- Ensure it's the first measurement
        AND first_troponin.first_troponin_valuenum > t99.threshold_value
)
SELECT
    COUNT(DISTINCT subject_id) AS total_unique_patients,
    COUNT(DISTINCT hadm_id) AS total_admissions_in_cohort,
    CAST(SUM(hospital_expire_flag) AS NUMERIC) / COUNT(hadm_id) AS in_hospital_mortality_rate,
    MIN(first_troponin_valuenum) AS min_first_troponin_val,
    MAX(first_troponin_valuenum) AS max_first_troponin_val,
    AVG(first_troponin_valuenum) AS avg_first_troponin_val
FROM
    identified_cohort;