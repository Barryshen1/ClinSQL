with a heart failure diagnosis,
-- characterizes their admissions based on ICU stay, Length of Stay (LOS), and comorbidity burden,
-- and reports in-hospital mortality rates, absolute/relative differences, and intervention prevalence (MV, Vasopressors, RRT).

-- 1. Cohort Selection: Identify female patients 51-61 with a heart failure diagnosis.
WITH cohort_admissions AS (
    SELECT
        pa.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag,
        -- Calculate age at admission
        pa.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - pa.anchor_year) AS age_at_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pa
        ON ad.subject_id = pa.subject_id
    WHERE
        pa.gender = 'F'
        AND (pa.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - pa.anchor_year)) BETWEEN 51 AND 61
),
heart_failure_admissions AS (
    SELECT DISTINCT
        ca.subject_id,
        ca.hadm_id,
        ca.admittime,
        ca.dischtime,
        ca.hospital_expire_flag
    FROM
        cohort_admissions ca
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON ca.hadm_id = di.hadm_id
    WHERE
        -- ICD-9 for Heart Failure: 428%
        (di.icd_version = 9 AND di.icd_code LIKE '428%') OR
        -- ICD-10 for Heart Failure: I50%
        (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
),
-- Pre-calculate number of distinct diagnoses per admission for comorbidity burden
hadm_diagnoses_count AS (
    SELECT
        hadm_id,
        COUNT(DISTINCT icd_code) AS num_diagnoses_icd
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY
        hadm_id
),
-- 2. Characterize admissions: LOS, Comorbidity Burden, ICU Stay Status
admission_characteristics AS (
    SELECT
        hf.subject_id,
        hf.hadm_id,
        hf.hospital_expire_flag,
        DATE_DIFF(hf.dischtime, hf.admittime, DAY) AS los_days,
        CASE
            WHEN DATE_DIFF(hf.dischtime, hf.admittime, DAY) IS NULL THEN 'Unknown' -- Handle cases where dischtime might be null
            WHEN DATE_DIFF(hf.dischtime, hf.admittime, DAY) < 8 THEN '<8 days'
            ELSE '>=8 days'
        END AS los_category,
        -- Comorbidity Burden: Use pre-calculated distinct ICD diagnoses per admission
        COALESCE(hdc.num_diagnoses_icd, 0) AS num_diagnoses_icd,
        CASE
            WHEN COALESCE(hdc.num_diagnoses_icd, 0) <= 5 THEN 'Low'
            WHEN COALESCE(hdc.num_diagnoses_icd, 0) BETWEEN 6 AND 10 THEN 'Medium'
            ELSE 'High'
        END AS comorbidity_burden,
        -- ICU Stay Status: True if the admission had any ICU stay
        EXISTS (SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` icu WHERE icu.hadm_id = hf.hadm_id) AS has_icu_stay
    FROM
        heart_failure_admissions hf
    LEFT JOIN
        hadm_diagnoses_count hdc
        ON hf.hadm_id = hdc.hadm_id
),
-- 3. Identify specific interventions (MV, Vasopressors, RRT) during ICU stays
-- Mechanical Ventilation (MV) during any ICU stay for the admission
mv_events AS (
    SELECT DISTINCT
        ic.hadm_id,
        TRUE AS received_mv
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` ic
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON ic.stay_id = ce.stay_id
    WHERE
        ce.itemid IN (
            223848, -- Ventilator Mode
            224700, -- Tidal Volume
            224701, -- Respiratory Rate
            224702, -- PIP
            224707 -- PSV Level
            -- These are common starting points for MV itemids. More could be added as needed.
        )
),
-- Vasopressors during any ICU stay for the admission
vaso_events AS (
    SELECT DISTINCT
        ic.hadm_id,
        TRUE AS received_vasopressors
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` ic
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.inputevents` ie
        ON ic.stay_id = ie.stay_id
    WHERE
        ie.itemid IN (
            221906, -- Norepinephrine
            221653, -- Dopamine
            221289, -- Epinephrine
            222303, -- Vasopressin
            221749  -- Phenylephrine
        )
),
-- Renal Replacement Therapy (RRT) during any ICU stay for the admission
rrt_events AS (
    SELECT DISTINCT
        ic.hadm_id,
        TRUE AS received_rrt
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` ic
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON ic.stay_id = ce.stay_id
    WHERE
        ce.itemid IN (
            225792, -- Dialysis Type
            225323, -- Dialysis Catheter Type
            225807, -- Dialysis Flow Rate
            225977, -- Hemodialysis
            227639, -- Continuous Renal Replacement Therapy (CRRT)
            227640, -- Intermittent Hemodialysis (IHD)
            225313, -- Dialysis Access Site
            224191  -- Peritoneal Dialysis
        )
),
-- Combine all features for analysis
combined_admissions AS (
    SELECT
        ac.subject_id,
        ac.hadm_id,
        ac.hospital_expire_flag,
        ac.los_category,
        ac.comorbidity_burden,
        ac.has_icu_stay,
        COALESCE(mv.received_mv, FALSE) AS received_mv,
        COALESCE(va.received_vasopressors, FALSE) AS received_vasopressors,
        COALESCE(rr.received_rrt, FALSE) AS received_rrt
    FROM
        admission_characteristics ac
    LEFT JOIN
        mv_events mv
        ON ac.hadm_id = mv.hadm_id
    LEFT JOIN
        vaso_events va
        ON ac.hadm_id = va.hadm_id
    LEFT JOIN
        rrt_events rr
        ON ac.hadm_id = rr.hadm_id
),
-- 4. & 5. Aggregate and report
aggregated_results AS (
    SELECT
        has_icu_stay,
        los_category,
        comorbidity_burden,
        COUNT(DISTINCT hadm_id) AS total_admissions,
        SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS in_hospital_deaths,
        SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(DISTINCT hadm_id)) AS mortality_rate,
        SAFE_DIVIDE(SUM(CASE WHEN received_mv THEN 1 ELSE 0 END), COUNT(DISTINCT hadm_id)) AS mv_prevalence,
        SAFE_DIVIDE(SUM(CASE WHEN received_vasopressors THEN 1 ELSE 0 END), COUNT(DISTINCT hadm_id)) AS vaso_prevalence,
        SAFE_DIVIDE(SUM(CASE WHEN received_rrt THEN 1 ELSE 0 END), COUNT(DISTINCT hadm_id)) AS rrt_prevalence
    FROM
        combined_admissions
    GROUP BY
        has_icu_stay,
        los_category,
        comorbidity_burden
),
-- Calculate absolute and relative differences in mortality rates
final_report AS (
    SELECT
        ar.has_icu_stay,
        ar.los_category,
        ar.comorbidity_burden,
        ar.total_admissions,
        ar.in_hospital_deaths,
        ar.mortality_rate,
        ar.mv_prevalence,
        ar.vaso_prevalence,
        ar.rrt_prevalence,
        -- Calculate absolute difference: (ICU mortality) - (No ICU mortality)
        CASE
            WHEN ar.has_icu_stay THEN
                ar.mortality_rate - LAG(ar.mortality_rate) OVER (PARTITION BY ar.los_category, ar.comorbidity_burden ORDER BY ar.has_icu_stay DESC)
            ELSE NULL -- This value is for 'No ICU' group, used as baseline
        END AS mortality_rate_absolute_diff_vs_no_icu,
        -- Calculate relative difference: (Absolute diff) / (No ICU mortality)
        CASE
            WHEN ar.has_icu_stay THEN
                SAFE_DIVIDE(
                    ar.mortality_rate - LAG(ar.mortality_rate) OVER (PARTITION BY ar.los_category, ar.comorbidity_burden ORDER BY ar.has_icu_stay DESC),
                    LAG(ar.mortality_rate) OVER (PARTITION BY ar.los_category, ar.comorbidity_burden ORDER BY ar.has_icu_stay DESC)
                )
            ELSE NULL
        END AS mortality_rate_relative_diff_vs_no_icu
    FROM
        aggregated_results ar
)
-- Final selection with formatted results
SELECT
    has_icu_stay AS "Had ICU Stay",
    los_category AS "LOS Category",
    comorbidity_burden AS "Comorbidity Burden",
    total_admissions AS "Total Admissions",
    in_hospital_deaths AS "In-Hospital Deaths",
    ROUND(mortality_rate * 100, 2) AS "Mortality Rate (%)",
    ROUND(mv_prevalence * 100, 2) AS "MV Prevalence (%)",
    ROUND(vaso_prevalence * 100, 2) AS "Vasopressor Prevalence (%)",
    ROUND(rrt_prevalence * 100, 2) AS "RRT Prevalence (%)",
    CASE
        WHEN has_icu_stay THEN ROUND(mortality_rate_absolute_diff_vs_no_icu * 100, 2) ELSE NULL
    END AS "Absolute Mortality Diff (ICU - No ICU) (%)",
    CASE
        WHEN has_icu_stay THEN ROUND(mortality_rate_relative_diff_vs_no_icu * 100, 2) ELSE NULL
    END AS "Relative Mortality Diff (ICU - No ICU) (%)"
FROM
    final_report
ORDER BY
    "Had ICU Stay" DESC, -- Show ICU patients first
    "LOS Category",
    CASE "Comorbidity Burden" WHEN 'Low' THEN 1 WHEN 'Medium' THEN 2 WHEN 'High' THEN 3 END;