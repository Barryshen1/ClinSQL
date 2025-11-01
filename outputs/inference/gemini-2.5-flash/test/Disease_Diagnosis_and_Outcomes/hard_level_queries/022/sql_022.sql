WITH patients_admissions AS (
    -- Base CTE to get patient demographics and admission details, and calculate age at admission
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.deathtime,
        adm.hospital_expire_flag,
        pat.gender,
        -- Calculate age at admission based on anchor_age and year difference
        (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) AS age_at_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
            ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'F'
        AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 40 AND 50
),
aki_cohort AS (
    -- Filter admissions for AKI diagnosis within the specified patient demographic
    SELECT DISTINCT
        pa.subject_id,
        pa.hadm_id,
        pa.admittime,
        pa.dischtime,
        pa.deathtime,
        pa.hospital_expire_flag
    FROM
        patients_admissions AS pa
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
            ON pa.hadm_id = diag.hadm_id
    WHERE
        -- Acute Kidney Injury (AKI) ICD codes: N17 for ICD-10, 584 for ICD-9
        (diag.icd_version = 10 AND diag.icd_code LIKE 'N17%')
        OR (diag.icd_version = 9 AND diag.icd_code LIKE '584%')
),
comorbidities_ards AS (
    -- Calculate number of comorbidities and ARDS presence for each AKI admission
    SELECT
        ac.hadm_id,
        COUNT(DISTINCT diag.icd_code) AS num_comorbidities, -- Count all distinct diagnoses as 'comorbidities'
        MAX(CASE
            -- ARDS ICD codes: J80 for ICD-10, 51882 for ICD-9
            WHEN (diag.icd_version = 10 AND diag.icd_code = 'J80') OR (diag.icd_version = 9 AND diag.icd_code = '51882') THEN 1
            ELSE 0
        END) AS is_ards_present
    FROM
        aki_cohort AS ac
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
            ON ac.hadm_id = diag.hadm_id
    GROUP BY
        ac.hadm_id
),
admission_analysis AS (
    -- Combine all data and calculate risk score, LOS, and 30-day post-discharge mortality flag
    SELECT
        ac.subject_id,
        ac.hadm_id,
        ac.admittime,
        ac.dischtime,
        ac.deathtime,
        ac.hospital_expire_flag,
        ca.num_comorbidities,
        ca.is_ards_present,
        -- Composite risk score calculation
        (5 * ca.num_comorbidities) + (50 * ca.is_ards_present) AS risk_score,
        -- Length of stay in days
        DATE_DIFF(ac.dischtime, ac.admittime, DAY) AS los_days,
        -- Flag for 30-day post-discharge mortality
        CASE
            WHEN ac.deathtime IS NOT NULL          -- Patient has a recorded deathtime
            AND ac.deathtime > ac.dischtime         -- Deathtime is after discharge time
            AND DATE_DIFF(ac.deathtime, ac.dischtime, DAY) <= 30 THEN 1 -- Within 30 days post-discharge
            ELSE 0
        END AS mort_30d_post_discharge
    FROM
        aki_cohort AS ac
    INNER JOIN
        comorbidities_ards AS ca
            ON ac.hadm_id = ca.hadm_id
),
quintile_data AS (
    -- Assign risk quintiles based on the calculated risk_score
    SELECT
        *,
        NTILE(5) OVER (ORDER BY risk_score ASC) AS risk_quintile
    FROM
        admission_analysis
)
-- Final aggregation to report metrics per quintile
SELECT
    risk_quintile,
    COUNT(DISTINCT hadm_id) AS N,
    -- Calculate 30-day post-discharge mortality percentage
    SAFE_DIVIDE(SUM(mort_30d_post_discharge), COUNT(hadm_id)) * 100 AS `30_day_post_discharge_mortality_percent`,
    -- Calculate ARDS co-occurrence percentage
    SAFE_DIVIDE(SUM(is_ards_present), COUNT(hadm_id)) * 100 AS `ARDS_co_occurrence_percent`,
    -- Calculate median Length of Stay for survivors (hospital_expire_flag = 0)
    -- APPROX_QUANTILES is used for efficiency, [OFFSET(50)] gets the median
    APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 0 THEN los_days ELSE NULL END, 100)[OFFSET(50)] AS `median_survivor_LOS_days`
FROM
    quintile_data
GROUP BY
    risk_quintile
ORDER BY
    risk_quintile;