WITH FemaleStrokeAdmissions AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_at_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'F'
        AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 48 AND 58
),
-- Step 2: Filter for admissions with at least one stroke diagnosis
AdmissionsWithStrokeDiagnosis AS (
    SELECT DISTINCT sa.subject_id, sa.hadm_id, sa.admittime, sa.dischtime, sa.hospital_expire_flag, sa.age_at_admission
    FROM FemaleStrokeAdmissions sa
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON sa.subject_id = di.subject_id AND sa.hadm_id = di.hadm_id
    WHERE
        -- ICD-9 codes for cerebrovascular disease
        (di.icd_version = 9 AND di.icd_code BETWEEN '430' AND '438')
        OR
        -- ICD-10 codes for cerebrovascular diseases
        (di.icd_version = 10 AND di.icd_code BETWEEN 'I60' AND 'I69')
),
-- Step 3: Calculate Comorbidity Burden (count of distinct non-stroke diagnoses)
ComorbidityCounts AS (
    SELECT
        di.hadm_id,
        COUNT(DISTINCT di.icd_code) AS num_comorbid_diagnoses
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    WHERE
        di.hadm_id IN (SELECT hadm_id FROM AdmissionsWithStrokeDiagnosis)
        AND NOT (
            (di.icd_version = 9 AND di.icd_code BETWEEN '430' AND '438')
            OR
            (di.icd_version = 10 AND di.icd_code BETWEEN 'I60' AND 'I69')
        )
    GROUP BY
        di.hadm_id
),
-- Step 4: Combine all stratification factors for the final cohort
FinalCohort AS (
    SELECT
        awsd.subject_id,
        awsd.hadm_id,
        awsd.hospital_expire_flag,
        -- ICU vs Non-ICU status
        CASE
            WHEN icu.stay_id IS NOT NULL THEN 'ICU'
            ELSE 'Non-ICU'
        END AS icu_status,
        -- Length of Stay (LOS) stratification
        CASE
            WHEN DATETIME_DIFF(awsd.dischtime, awsd.admittime, DAY) <= 5 THEN 'LOS <= 5 days'
            ELSE 'LOS > 5 days'
        END AS los_group,
        -- Comorbidity burden stratification
        CASE
            WHEN COALESCE(cc.num_comorbid_diagnoses, 0) <= 3 THEN 'Low Comorbidity (0-3 diag)'
            WHEN COALESCE(cc.num_comorbid_diagnoses, 0) <= 6 THEN 'Medium Comorbidity (4-6 diag)'
            ELSE 'High Comorbidity (>6 diag)'
        END AS comorbidity_burden_group
    FROM
        AdmissionsWithStrokeDiagnosis awsd
    LEFT JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON awsd.subject_id = icu.subject_id AND awsd.hadm_id = icu.hadm_id
    LEFT JOIN
        ComorbidityCounts cc
        ON awsd.hadm_id = cc.hadm_id
)
-- Step 5: Aggregate results and calculate mortality rates with 95% CIs
SELECT
    icu_status,
    los_group,
    comorbidity_burden_group,
    COUNT(hadm_id) AS total_admissions,
    SUM(hospital_expire_flag) AS mortality_count,
    ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(hadm_id), 2) AS mortality_rate_percent,
    -- Calculate 95% Confidence Interval (Normal Approximation)
    -- P = proportion of events, N = total observations
    -- CI = P +/- 1.96 * SQRT(P * (1 - P) / N)
    ROUND(
        (SUM(CAST(hospital_expire_flag AS BIGNUMERIC)) / COUNT(hadm_id)) * 100.0 -
        (1.96 * SQRT(
            (SUM(CAST(hospital_expire_flag AS BIGNUMERIC)) / COUNT(hadm_id)) *
            (1 - (SUM(CAST(hospital_expire_flag AS BIGNUMERIC)) / COUNT(hadm_id))) /
            COUNT(hadm_id)
        )) * 100.0
    , 2) AS ci_lower_bound_percent,
    ROUND(
        (SUM(CAST(hospital_expire_flag AS BIGNUMERIC)) / COUNT(hadm_id)) * 100.0 +
        (1.96 * SQRT(
            (SUM(CAST(hospital_expire_flag AS BIGNUMERIC)) / COUNT(hadm_id)) *
            (1 - (SUM(CAST(hospital_expire_flag AS BIGNUMERIC)) / COUNT(hadm_id))) /
            COUNT(hadm_id)
        )) * 100.0
    , 2) AS ci_upper_bound_percent
FROM
    FinalCohort
GROUP BY
    icu_status,
    los_group,
    comorbidity_burden_group
ORDER BY
    icu_status,
    los_group,
    comorbidity_burden_group;