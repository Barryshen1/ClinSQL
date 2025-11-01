WITH AdmissionsCohort AS (
            -- 1. Define the Cohort: Females, age 39-49, T2DM, HF, LOS >= 72h
            SELECT
                a.subject_id,
                a.hadm_id,
                a.admittime,
                a.dischtime
            FROM
                `physionet-data.mimiciv_3_1_hosp.admissions` a
            INNER JOIN
                `physionet-data.mimiciv_3_1_hosp.patients` p
                ON a.subject_id = p.subject_id
            WHERE
                p.gender = 'F'
                -- Age 39-49 at admission
                AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 39 AND 49
                -- LOS >= 72 hours
                AND DATETIME_DIFF(a.dischtime, a.admittime, HOUR) >= 72
                -- T2DM diagnosis
                AND EXISTS (
                    SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_t2dm
                    WHERE di_t2dm.subject_id = a.subject_id
                    AND di_t2dm.hadm_id = a.hadm_id
                    AND (
                        (di_t2dm.icd_version = 10 AND di_t2dm.icd_code LIKE 'E11%') OR -- ICD-10 for Type 2 DM
                        (di_t2dm.icd_version = 9 AND di_t2dm.icd_code LIKE '250.%')    -- ICD-9 for Diabetes Mellitus (general, often used for T2DM in broader queries). Using 250.% to be slightly more specific than 250%
                    )
                )
                -- Heart Failure diagnosis
                AND EXISTS (
                    SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_hf
                    WHERE di_hf.subject_id = a.subject_id
                    AND di_hf.hadm_id = a.hadm_id
                    AND (
                        (di_hf.icd_version = 10 AND di_hf.icd_code LIKE 'I50%') OR -- ICD-10 for Heart Failure
                        (di_hf.icd_version = 9 AND di_hf.icd_code LIKE '428%')    -- ICD-9 for Heart Failure
                    )
                )
        ),
        TotalCohortCount AS (
            -- 2. Calculate the total number of eligible admissions in the cohort
            SELECT COUNT(DISTINCT hadm_id) AS total_admissions_in_cohort
            FROM AdmissionsCohort
        ),
        InsulinOrders AS (
            -- 3. Identify all relevant insulin orders for the cohort
            SELECT
                ac.subject_id,
                ac.hadm_id,
                p.starttime,
                LOWER(p.medication) AS medication_lower,
                LOWER(COALESCE(p.disp_sched, '')) AS disp_sched_lower, -- COALESCE to handle NULLs for string matching
                LOWER(COALESCE(p.frequency, '')) AS frequency_lower, -- COALESCE to handle NULLs for string matching
                ac.admittime,
                ac.dischtime
            FROM
                AdmissionsCohort ac
            INNER JOIN
                `physionet-data.mimiciv_3_1_hosp.pharmacy` p
                ON ac.subject_id = p.subject_id
                AND ac.hadm_id = p.hadm_id
            WHERE
                p.medication IS NOT NULL
                -- Broad filter for common insulin types to reduce processing
                AND (LOWER(p.medication) LIKE '%insulin%' OR LOWER(p.medication) LIKE '%nph%' OR LOWER(p.medication) LIKE '%glargine%'
                     OR LOWER(p.medication) LIKE '%detemir%' OR LOWER(p.medication) LIKE '%lispro%' OR LOWER(p.medication) LIKE '%aspart%'
                     OR LOWER(p.medication) LIKE '%regular%')
                AND p.starttime IS NOT NULL
                AND p.starttime >= ac.admittime
                AND p.starttime < ac.dischtime -- Ensure order start time is within the overall admission
        ),
        PatientInsulinInitiationFlags AS (
            -- 4. Determine for each patient/admission if they initiated each insulin type within the defined windows
            SELECT
                subject_id,
                hadm_id,
                admittime,
                dischtime,
                -- Flags for First 72 hours
                MAX(CASE WHEN (medication_lower LIKE '%glargine%' OR medication_lower LIKE '%detemir%' OR medication_lower LIKE '%nph%')
                              AND starttime >= admittime AND starttime < DATETIME_ADD(admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS initiates_basal_72h,
                MAX(CASE WHEN (medication_lower LIKE '%lispro%' OR medication_lower LIKE '%aspart%' OR medication_lower LIKE '%regular%')
                              AND starttime >= admittime AND starttime < DATETIME_ADD(admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS initiates_bolus_72h,
                MAX(CASE WHEN (medication_lower LIKE '%sliding scale%' OR disp_sched_lower LIKE '%sliding scale%' OR frequency_lower LIKE '%sliding scale%')
                              AND starttime >= admittime AND starttime < DATETIME_ADD(admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS initiates_ss_72h,

                -- Flags for Final 48 hours
                MAX(CASE WHEN (medication_lower LIKE '%glargine%' OR medication_lower LIKE '%detemir%' OR medication_lower LIKE '%nph%')
                              AND starttime >= DATETIME_SUB(dischtime, INTERVAL 48 HOUR) AND starttime < dischtime THEN 1 ELSE 0 END) AS initiates_basal_48h,
                MAX(CASE WHEN (medication_lower LIKE '%lispro%' OR medication_lower LIKE '%aspart%' OR medication_lower LIKE '%regular%')
                              AND starttime >= DATETIME_SUB(dischtime, INTERVAL 48 HOUR) AND starttime < dischtime THEN 1 ELSE 0 END) AS initiates_bolus_48h,
                MAX(CASE WHEN (medication_lower LIKE '%sliding scale%' OR disp_sched_lower LIKE '%sliding scale%' OR frequency_lower LIKE '%sliding scale%')
                              AND starttime >= DATETIME_SUB(dischtime, INTERVAL 48 HOUR) AND starttime < dischtime THEN 1 ELSE 0 END) AS initiates_ss_48h
            FROM
                InsulinOrders
            GROUP BY
                subject_id, hadm_id, admittime, dischtime
        )
        SELECT
            -- Percentages for first 72 hours
            SAFE_DIVIDE(SUM(pif.initiates_basal_72h), MAX(tcc.total_admissions_in_cohort)) * 100 AS percent_basal_72h,
            SAFE_DIVIDE(SUM(pif.initiates_bolus_72h), MAX(tcc.total_admissions_in_cohort)) * 100 AS percent_bolus_72h,
            SAFE_DIVIDE(SUM(pif.initiates_ss_72h), MAX(tcc.total_admissions_in_cohort)) * 100 AS percent_ss_72h,
            SAFE_DIVIDE(SUM(CASE WHEN pif.initiates_basal_72h = 1 AND pif.initiates_bolus_72h = 1 THEN 1 ELSE 0 END), MAX(tcc.total_admissions_in_cohort)) * 100 AS percent_basal_bolus_72h,

            -- Percentages for final 48 hours
            SAFE_DIVIDE(SUM(pif.initiates_basal_48h), MAX(tcc.total_admissions_in_cohort)) * 100 AS percent_basal_48h,
            SAFE_DIVIDE(SUM(pif.initiates_bolus_48h), MAX(tcc.total_admissions_in_cohort)) * 100 AS percent_bolus_48h,
            SAFE_DIVIDE(SUM(pif.initiates_ss_48h), MAX(tcc.total_admissions_in_cohort)) * 100 AS percent_ss_48h,
            SAFE_DIVIDE(SUM(CASE WHEN pif.initiates_basal_48h = 1 AND pif.initiates_bolus_48h = 1 THEN 1 ELSE 0 END), MAX(tcc.total_admissions_in_cohort)) * 100 AS percent_basal_bolus_48h,

            -- Absolute percentage-point differences (72h - 48h)
            (SAFE_DIVIDE(SUM(pif.initiates_basal_72h), MAX(tcc.total_admissions_in_cohort)) * 100) -
            (SAFE_DIVIDE(SUM(pif.initiates_basal_48h), MAX(tcc.total_admissions_in_cohort)) * 100) AS diff_basal_pct_pts,

            (SAFE_DIVIDE(SUM(pif.initiates_bolus_72h), MAX(tcc.total_admissions_in_cohort)) * 100) -
            (SAFE_DIVIDE(SUM(pif.initiates_bolus_48h), MAX(tcc.total_admissions_in_cohort)) * 100) AS diff_bolus_pct_pts,

            (SAFE_DIVIDE(SUM(pif.initiates_ss_72h), MAX(tcc.total_admissions_in_cohort)) * 100) -
            (SAFE_DIVIDE(SUM(pif.initiates_ss_48h), MAX(tcc.total_admissions_in_cohort)) * 100) AS diff_ss_pct_pts,

            (SAFE_DIVIDE(SUM(CASE WHEN pif.initiates_basal_72h = 1 AND pif.initiates_bolus_72h = 1 THEN 1 ELSE 0 END), MAX(tcc.total_admissions_in_cohort)) * 100) -
            (SAFE_DIVIDE(SUM(CASE WHEN pif.initiates_basal_48h = 1 AND pif.initiates_bolus_48h = 1 THEN 1 ELSE 0 END), MAX(tcc.total_admissions_in_cohort)) * 100) AS diff_basal_bolus_pct_pts
        FROM
            PatientInsulinInitiationFlags pif
        CROSS JOIN
            TotalCohortCount tcc;