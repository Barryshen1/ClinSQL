WITH Admissions_ICH AS (
    -- Step 1: Identify eligible admissions and patients based on cohort criteria
    SELECT DISTINCT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.deathtime, -- In-hospital deathtime from admissions table
        pat.gender,
        pat.anchor_age,
        pat.dod -- Overall patient date of death from patients table
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON ad.subject_id = pat.subject_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 68 AND 78
        -- Check for Intracranial Hemorrhage (ICH) based on ICD codes
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            WHERE di.subject_id = ad.subject_id AND di.hadm_id = ad.hadm_id
            AND (
                (di.icd_version = 9 AND (di.icd_code IN ('430', '431') OR di.icd_code LIKE '432%'))
                OR
                (di.icd_version = 10 AND (di.icd_code IN ('I60', 'I61') OR di.icd_code LIKE 'I62%'))
            )
        )
        -- Interpret "transferred from ICU" as having had an ICU stay during this admission
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
            WHERE icu.subject_id = ad.subject_id AND icu.hadm_id = ad.hadm_id
        )
),
Cohort_Admission_Flags_Scores AS (
    -- Step 2: Calculate admission-level flags and the composite risk score proxy
    SELECT
        ich.subject_id,
        ich.hadm_id,
        ich.admittime,
        -- Flag for 30-day mortality for this admission
        CASE
            WHEN ich.deathtime IS NOT NULL AND DATETIME_DIFF(ich.deathtime, ich.admittime, DAY) <= 30 THEN 1
            WHEN ich.deathtime IS NULL AND ich.dod IS NOT NULL AND DATE_DIFF(ich.dod, DATE(ich.admittime), DAY) <= 30 THEN 1
            ELSE 0
        END AS admission_thirty_day_mortality_flag,
        -- Determine the definitive deathtime for survival calculation (if any and after admission)
        COALESCE(
            ich.deathtime,
            CASE WHEN ich.dod IS NOT NULL AND ich.dod >= DATE(ich.admittime) THEN CAST(ich.dod AS DATETIME) ELSE NULL END
        ) AS admission_final_deathtime,
        -- Flag for AKI diagnosis during this admission
        MAX(CASE
            WHEN di_aki.icd_version = 9 AND di_aki.icd_code IN ('5845', '5846', '5847', '5848', '5849') THEN 1
            WHEN di_aki.icd_version = 10 AND di_aki.icd_code LIKE 'N17%' THEN 1
            ELSE 0
        END) AS had_aki_admission_flag,
        -- Flag for ARDS diagnosis during this admission
        MAX(CASE
            WHEN di_ards.icd_version = 9 AND di_ards.icd_code = '51882' THEN 1
            WHEN di_ards.icd_version = 10 AND di_ards.icd_code = 'J80' THEN 1
            ELSE 0
        END) AS had_ards_admission_flag,
        -- Composite Risk Score Proxy: Count of distinct ICD diagnosis codes for this admission
        COUNT(DISTINCT di_all.icd_code) AS composite_risk_score_proxy
    FROM
        Admissions_ICH ich
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_aki
        ON ich.subject_id = di_aki.subject_id AND ich.hadm_id = di_aki.hadm_id
        AND (
            (di_aki.icd_version = 9 AND di_aki.icd_code IN ('5845', '5846', '5847', '5848', '5849'))
            OR
            (di_aki.icd_version = 10 AND di_aki.icd_code LIKE 'N17%')
        )
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_ards
        ON ich.subject_id = di_ards.subject_id AND ich.hadm_id = di_ards.hadm_id
        AND (
            (di_ards.icd_version = 9 AND di_ards.icd_code = '51882')
            OR
            (di_ards.icd_version = 10 AND di_ards.icd_code = 'J80')
        )
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_all -- For general ICD count
        ON ich.subject_id = di_all.subject_id AND ich.hadm_id = di_all.hadm_id
    GROUP BY
        ich.subject_id, ich.hadm_id, ich.admittime, ich.deathtime, ich.dod
),
Patient_Level_Data AS (
    -- Step 3: Aggregate admission-level data to patient-level
    -- A patient can have multiple relevant admissions, consolidate flags and sum composite scores.
    SELECT
        subject_id,
        -- A patient is considered 30-day mortality if *any* of their relevant admissions meet the criteria
        MAX(admission_thirty_day_mortality_flag) AS patient_thirty_day_mortality_flag,
        -- A patient is considered to have AKI if *any* of their relevant admissions had it
        MAX(had_aki_admission_flag) AS patient_had_aki_flag,
        -- A patient is considered to have ARDS if *any* of their relevant admissions had it
        MAX(had_ards_admission_flag) AS patient_had_ards_flag,
        -- Sum of composite risk scores across all relevant admissions for the patient
        SUM(composite_risk_score_proxy) AS patient_composite_risk_score_sum,
        -- Minimum survival time in days for patients who died, across all relevant admissions
        MIN(
            CASE WHEN admission_final_deathtime IS NOT NULL THEN
                DATETIME_DIFF(admission_final_deathtime, admittime, HOUR) / 24.0 -- Survival in days
            ELSE NULL END
        ) AS patient_survival_days_if_decedent
    FROM
        Cohort_Admission_Flags_Scores
    GROUP BY
        subject_id
)
-- Step 4: Aggregate patient-level data to produce the final cohort statistics
SELECT
    COUNT(pld.subject_id) AS cohort_size,
    AVG(pld.patient_thirty_day_mortality_flag) AS thirty_day_mortality_rate, -- AVG of 0/1 flag is the rate
    AVG(pld.patient_had_aki_flag) AS aki_rate,
    AVG(pld.patient_had_ards_flag) AS ards_rate,
    -- Composite risk score percentiles (using subqueries with PERCENTILE_CONT for exactness)
    (SELECT PERCENTILE_CONT(p.patient_composite_risk_score_sum, 0.25) OVER() FROM Patient_Level_Data p LIMIT 1) AS composite_risk_score_25_percentile,
    (SELECT PERCENTILE_CONT(p.patient_composite_risk_score_sum, 0.50) OVER() FROM Patient_Level_Data p LIMIT 1) AS composite_risk_score_50_percentile,
    (SELECT PERCENTILE_CONT(p.patient_composite_risk_score_sum, 0.75) OVER() FROM Patient_Level_Data p LIMIT 1) AS composite_risk_score_75_percentile,
    -- Median survival among decedents (50th percentile)
    (SELECT PERCENTILE_CONT(p.patient_survival_days_if_decedent, 0.50) OVER() FROM Patient_Level_Data p WHERE p.patient_survival_days_if_decedent IS NOT NULL LIMIT 1) AS median_survival_among_decedents_days
FROM
    Patient_Level_Data pld;