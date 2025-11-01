WITH drug_mapping AS (
    -- Define common drug names and map them to their respective classes
    -- This list is not exhaustive but covers commonly used medications for these classes.
    SELECT 'insulin' AS drug_key_term, 'ANTIDIABETICS' AS drug_class
    UNION ALL SELECT 'metformin', 'ANTIDIABETICS'
    UNION ALL SELECT 'glyburide', 'ANTIDIABETICS'
    UNION ALL SELECT 'glipizide', 'ANTIDIABETICS'
    UNION ALL SELECT 'glimepiride', 'ANTIDIABETICS'
    UNION ALL SELECT 'sitagliptin', 'ANTIDIABETICS'
    UNION ALL SELECT 'empagliflozin', 'ANTIDIABETICS'
    UNION ALL SELECT 'dapagliflozin', 'ANTIDIABETICS'
    UNION ALL SELECT 'canagliflozin', 'ANTIDIABETICS'
    UNION ALL SELECT 'liraglutide', 'ANTIDIABETICS'
    UNION ALL SELECT 'dulaglutide', 'ANTIDIABETICS'
    UNION ALL SELECT 'semaglutide', 'ANTIDIABETICS'
    UNION ALL SELECT 'lispro', 'ANTIDIABETICS'
    UNION ALL SELECT 'aspart', 'ANTIDIABETICS'
    UNION ALL SELECT 'glargine', 'ANTIDIABETICS'
    UNION ALL SELECT 'detemir', 'ANTIDIABETICS'

    UNION ALL SELECT 'metoprolol', 'BETA_BLOCKERS'
    UNION ALL SELECT 'carvedilol', 'BETA_BLOCKERS'
    UNION ALL SELECT 'labetalol', 'BETA_BLOCKERS'
    UNION ALL SELECT 'atenolol', 'BETA_BLOCKERS'
    UNION ALL SELECT 'bisoprolol', 'BETA_BLOCKERS'
    UNION ALL SELECT 'propranolol', 'BETA_BLOCKERS'
    UNION ALL SELECT 'esmolol', 'BETA_BLOCKERS'

    UNION ALL SELECT 'lisinopril', 'ACEI_ARB_ARNI'
    UNION ALL SELECT 'enalapril', 'ACEI_ARB_ARNI'
    UNION ALL SELECT 'ramipril', 'ACEI_ARB_ARNI'
    UNION ALL SELECT 'captopril', 'ACEI_ARB_ARNI'
    UNION ALL SELECT 'valsartan', 'ACEI_ARB_ARNI' -- Covers ARB and combination ARNI (Sacubitril/Valsartan)
    UNION ALL SELECT 'losartan', 'ACEI_ARB_ARNI'
    UNION ALL SELECT 'candesartan', 'ACEI_ARB_ARNI'
    UNION ALL SELECT 'irbesartan', 'ACEI_ARB_ARNI'
    UNION ALL SELECT 'olmesartan', 'ACEI_ARB_ARNI'
    UNION ALL SELECT 'sacubitril/valsartan', 'ACEI_ARB_ARNI' -- Explicit ARNI

    UNION ALL SELECT 'furosemide', 'LOOP_DIURETICS'
    UNION ALL SELECT 'torsemide', 'LOOP_DIURETICS'
    UNION ALL SELECT 'bumetanide', 'LOOP_DIURETICS'
),
-- 1. Identify the patient cohort: Male, 77-87 yo, with Diabetes and Heart Failure
EligibleAdmissions AS (
    SELECT DISTINCT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        DATETIME_ADD(a.admittime, INTERVAL 48 HOUR) AS first_48h_window_end,
        DATETIME_SUB(a.dischtime, INTERVAL 12 HOUR) AS last_12h_window_start
    FROM
        `physionet-data.mimiciv_3_1_hosp`.admissions a
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp`.patients p
        ON a.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 77 AND 87
        -- Check for Diabetes diagnosis (ICD-10: E08-E13, ICD-9: 250%)
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di_dm
            WHERE
                di_dm.subject_id = a.subject_id
                AND di_dm.hadm_id = a.hadm_id
                AND (
                    (di_dm.icd_version = 10 AND di_dm.icd_code BETWEEN 'E08' AND 'E13')
                    OR (di_dm.icd_version = 9 AND di_dm.icd_code LIKE '250%')
                )
        )
        -- Check for Heart Failure diagnosis (ICD-10: I50%, ICD-9: 428%)
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di_hf
            WHERE
                di_hf.subject_id = a.subject_id
                AND di_hf.hadm_id = a.hadm_id
                AND (
                    (di_hf.icd_version = 10 AND di_hf.icd_code LIKE 'I50%')
                    OR (di_hf.icd_version = 9 AND di_hf.icd_code LIKE '428%')
                )
        )
),
TotalCohortSize AS (
    -- Calculate the total number of unique admissions in the cohort for percentage calculations
    SELECT COUNT(DISTINCT hadm_id) AS total_admissions FROM EligibleAdmissions
),
-- 2. Find the first prescription time for any medication within each defined drug class
--    for each eligible admission. This defines 'initiation'.
FirstRxPerClass AS (
    SELECT
        ea.hadm_id,
        dm.drug_class,
        MIN(pr.starttime) AS first_class_rx_time_admission,
        ea.admittime,
        ea.dischtime,
        ea.first_48h_window_end,
        ea.last_12h_window_start
    FROM
        EligibleAdmissions ea
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp`.prescriptions pr
        ON ea.subject_id = pr.subject_id AND ea.hadm_id = pr.hadm_id
    INNER JOIN
        drug_mapping dm
        ON LOWER(pr.drug) LIKE '%' || dm.drug_key_term || '%' -- Case-insensitive fuzzy match for drug names
    WHERE
        pr.starttime IS NOT NULL
        AND pr.starttime >= ea.admittime -- Ensure prescription is within the admission
        AND pr.starttime <= ea.dischtime -- Ensure prescription is within the admission
    GROUP BY
        ea.hadm_id, dm.drug_class, ea.admittime, ea.dischtime, ea.first_48h_window_end, ea.last_12h_window_start
),
-- 3. Determine if the initiation occurred within the specified time windows
Initiations AS (
    SELECT
        fpc.hadm_id,
        fpc.drug_class,
        -- Flag for initiation in the first 48 hours of admission
        CASE
            WHEN fpc.first_class_rx_time_admission >= fpc.admittime
            AND fpc.first_class_rx_time_admission <= fpc.first_48h_window_end
            THEN 1 ELSE 0
        END AS initiated_first_48h,
        -- Flag for initiation in the last 12 hours of admission
        CASE
            WHEN fpc.last_12h_window_start IS NOT NULL -- check if dischtime-12h is valid
            AND fpc.first_class_rx_time_admission >= fpc.last_12h_window_start
            AND fpc.first_class_rx_time_admission <= fpc.dischtime
            THEN 1 ELSE 0
        END AS initiated_last_12h
    FROM
        FirstRxPerClass fpc
)
-- 4. Calculate initiation rates and net change for each drug class
SELECT
    i.drug_class,
    COUNT(DISTINCT CASE WHEN i.initiated_first_48h = 1 THEN i.hadm_id END) AS initiated_first_48h_count,
    ROUND(COUNT(DISTINCT CASE WHEN i.initiated_first_48h = 1 THEN i.hadm_id END) * 100.0 / tcs.total_admissions, 2) AS initiation_rate_first_48h_percent,
    COUNT(DISTINCT CASE WHEN i.initiated_last_12h = 1 THEN i.hadm_id END) AS initiated_last_12h_count,
    ROUND(COUNT(DISTINCT CASE WHEN i.initiated_last_12h = 1 THEN i.hadm_id END) * 100.0 / tcs.total_admissions, 2) AS initiation_rate_last_12h_percent,
    -- Calculate net change as the difference between the two rates
    ROUND((COUNT(DISTINCT CASE WHEN i.initiated_first_48h = 1 THEN i.hadm_id END) * 100.0 / tcs.total_admissions) -
          (COUNT(DISTINCT CASE WHEN i.initiated_last_12h = 1 THEN i.hadm_id END) * 100.0 / tcs.total_admissions), 2) AS net_change_percent
FROM
    Initiations i, TotalCohortSize tcs -- Use cross join to access total_admissions
GROUP BY
    i.drug_class, tcs.total_admissions
ORDER BY
    i.drug_class;