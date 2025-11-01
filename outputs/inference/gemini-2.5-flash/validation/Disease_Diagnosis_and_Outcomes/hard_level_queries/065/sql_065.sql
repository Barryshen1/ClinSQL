WITH AdmissionsFiltered AS (
    -- Base admissions for target cohort with demographic filters
    SELECT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        a.deathtime,
        p.dod -- Include dod for 90-day mortality calculation
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON a.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 71 AND 81
),
DVT_Admissions AS (
    -- Identify admissions with DVT diagnoses
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (
               icd_code LIKE 'I82.4%' -- ICD-10 DVT lower extremity
            OR icd_code LIKE 'I82.5%' -- ICD-10 DVT other deep veins of lower extremity
            OR icd_code LIKE '453.4%' -- ICD-9 DVT lower extremity
            OR icd_code LIKE '453.8%' -- ICD-9 DVT other specified sites
        )
),
DRG_Severity_MS_HADM AS (
    -- Get the maximum MS-DRG severity for each admission
    SELECT
        hadm_id,
        MAX(CAST(drg_severity AS INT64)) AS drg_severity_int
    FROM `physionet-data.mimiciv_3_1_hosp.drgcodes`
    WHERE drg_type = 'MS' -- Focusing on Medicare Severity DRG for consistency
    GROUP BY hadm_id
),
TargetCohort_Base AS (
    -- Combine filters for the specific target cohort
    SELECT
        af.hadm_id,
        ds.drg_severity_int AS drg_severity,
        DATE_DIFF(af.dischtime, af.admittime, DAY) AS los_days,
        (af.dod IS NOT NULL AND DATE_DIFF(DATE(af.dod), DATE(af.admittime), DAY) <= 90) AS died_within_90_days,
        af.hospital_expire_flag,
        af.deathtime
    FROM
        AdmissionsFiltered AS af
    INNER JOIN
        DVT_Admissions AS dvt
        ON af.hadm_id = dvt.hadm_id
    INNER JOIN
        DRG_Severity_MS_HADM AS ds
        ON af.hadm_id = ds.hadm_id
    WHERE
        ds.drg_severity_int IS NOT NULL AND ds.drg_severity_int >= 3 -- "High comorbidity" proxy (MS-DRG Severity of 3 or 4)
),
GeneralAdmissionsFiltered AS (
    -- Base admissions for general inpatient cohort
    SELECT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        a.deathtime,
        a.admission_type,
        p.dod
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON a.subject_id = p.subject_id
    WHERE
        a.admission_type != 'ELECTIVE' -- Exclude planned admissions
),
GeneralDRG_Severity_MS_HADM AS (
    -- Get the maximum MS-DRG severity for each general admission
    SELECT
        hadm_id,
        MAX(CAST(drg_severity AS INT64)) AS drg_severity_int
    FROM `physionet-data.mimiciv_3_1_hosp.drgcodes`
    WHERE drg_type = 'MS'
    GROUP BY hadm_id
),
GeneralInpatients_Base AS (
    -- Combine filters for the general inpatient cohort
    SELECT
        gaf.hadm_id,
        gds.drg_severity_int AS drg_severity,
        DATE_DIFF(gaf.dischtime, gaf.admittime, DAY) AS los_days,
        (gaf.dod IS NOT NULL AND DATE_DIFF(DATE(gaf.dod), DATE(gaf.admittime), DAY) <= 90) AS died_within_90_days,
        gaf.hospital_expire_flag,
        gaf.deathtime
    FROM
        GeneralAdmissionsFiltered AS gaf
    INNER JOIN
        GeneralDRG_Severity_MS_HADM AS gds
        ON gaf.hadm_id = gds.hadm_id
    WHERE
        gds.drg_severity_int IS NOT NULL AND gds.drg_severity_int > 0 -- Valid severity for general comparison
),
TargetCohort_Metrics AS (
    -- Calculate aggregated metrics for the Target Cohort
    SELECT
        COUNT(tb.hadm_id) AS cohort_size,
        -- Risk Score percentiles for the entire cohort
        APPROX_QUANTILES(tb.drg_severity, 100)[OFFSET(50)] AS median_risk_score,
        APPROX_QUANTILES(tb.drg_severity, 100)[OFFSET(25)] AS q1_risk_score,
        APPROX_QUANTILES(tb.drg_severity, 100)[OFFSET(75)] AS q3_risk_score,
        -- Mortality rate over the entire cohort
        SUM(CASE WHEN tb.died_within_90_days THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(tb.hadm_id), 0) AS mortality_90_day_rate,
        -- Major complication rate (DRG severity 4) over the entire cohort
        SUM(CASE WHEN tb.drg_severity = 4 THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(tb.hadm_id), 0) AS major_complication_rate,
        -- Median LOS only for survivors
        APPROX_QUANTILES(CASE WHEN tb.hospital_expire_flag = 0 AND tb.deathtime IS NULL THEN tb.los_days ELSE NULL END, 100)[OFFSET(50)] AS median_survivor_los
    FROM
        TargetCohort_Base AS tb
),
GeneralCohort_Metrics AS (
    -- Calculate aggregated metrics for the General Inpatients Cohort
    SELECT
        COUNT(gb.hadm_id) AS cohort_size,
        -- Mortality rate over the entire cohort
        SUM(CASE WHEN gb.died_within_90_days THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(gb.hadm_id), 0) AS mortality_90_day_rate,
        -- Major complication rate (DRG severity 4) over the entire cohort
        SUM(CASE WHEN gb.drg_severity = 4 THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(gb.hadm_id), 0) AS major_complication_rate,
        -- Median LOS only for survivors
        APPROX_QUANTILES(CASE WHEN gb.hospital_expire_flag = 0 AND gb.deathtime IS NULL THEN gb.los_days ELSE NULL END, 100)[OFFSET(50)] AS median_survivor_los
    FROM
        GeneralInpatients_Base AS gb
)
SELECT
    -- Target Cohort Metrics
    tcm.cohort_size AS target_cohort_sample_size,
    tcm.median_risk_score AS target_median_risk_score,
    ROUND(tcm.q1_risk_score, 2) AS target_q1_risk_score,
    ROUND(tcm.q3_risk_score, 2) AS target_q3_risk_score,
    ROUND((tcm.q3_risk_score - tcm.q1_risk_score), 2) AS target_iqr_risk_score,
    ROUND(tcm.mortality_90_day_rate, 2) AS target_90_day_mortality_rate_percent,
    ROUND(tcm.major_complication_rate, 2) AS target_major_complication_rate_percent,
    ROUND(tcm.median_survivor_los, 2) AS target_median_survivor_los_days,

    -- General Inpatients Metrics (for comparison)
    gcm.cohort_size AS general_cohort_sample_size,
    ROUND(gcm.mortality_90_day_rate, 2) AS general_90_day_mortality_rate_percent,
    ROUND(gcm.major_complication_rate, 2) AS general_major_complication_rate_percent,
    ROUND(gcm.median_survivor_los, 2) AS general_median_survivor_los_days,

    -- Specific Man's Risk Percentile (assuming his risk score is the cohort's median)
    tcm.median_risk_score AS specific_man_estimated_risk_score, -- Directly from TargetCohort_Metrics
    ROUND(
        (SELECT COUNT(hadm_id) FROM TargetCohort_Base WHERE drg_severity <= tcm.median_risk_score) * 100.0
        / NULLIF(tcm.cohort_size, 0) -- Use NULLIF to prevent division by zero
    , 2) AS specific_man_risk_percentile_within_cohort
FROM
    TargetCohort_Metrics AS tcm,
    GeneralCohort_Metrics AS gcm;