WITH cohort_admissions AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        pat.dod,
        -- Calculate age at admission by adjusting anchor_age based on anchor_year and admittime year
        pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_at_admission,
        -- Calculate hospital length of stay in days
        TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'F'
        -- Filter for female patients aged 70-80
        AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 70 AND 80
        AND adm.dischtime IS NOT NULL
        AND adm.hadm_id IN (
            -- Identify admissions with primary diagnosis related to lower GI bleeding (seq_num = 1)
            SELECT DISTINCT hadm_id
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
            WHERE
                seq_num = 1 -- Primary diagnosis
                AND (
                    -- Common ICD-9 codes for LGIB
                    (icd_version = 9 AND icd_code IN ('5781', '5789', '56211', '5693')) 
                    OR
                    -- Common ICD-10 codes for LGIB
                    (icd_version = 10 AND icd_code IN ('K922', 'K5732', 'K5733', 'K625')) 
                )
        )
),
complication_flags AS (
    SELECT
        ca.subject_id,
        ca.hadm_id,
        ca.admittime,
        ca.dischtime,
        ca.dod,
        ca.los_days,
        -- Flag for Sepsis diagnosis
        MAX(CASE WHEN d_sepsis.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS sepsis_flag,
        -- Flag for AKI diagnosis
        MAX(CASE WHEN d_aki.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS aki_flag,
        -- Flag for Mechanical Ventilation procedure
        MAX(CASE WHEN p_mv.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS mech_vent_flag,
        -- Flag for presence of an ICU Stay
        MAX(CASE WHEN icu.stay_id IS NOT NULL THEN 1 ELSE 0 END) AS icu_stay_flag
    FROM
        cohort_admissions AS ca
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d_sepsis
        ON ca.hadm_id = d_sepsis.hadm_id
        AND (
            (d_sepsis.icd_version = 9 AND d_sepsis.icd_code IN ('99592', '78552'))
            OR
            (d_sepsis.icd_version = 10 AND d_sepsis.icd_code IN ('R6520', 'R6521'))
        )
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d_aki
        ON ca.hadm_id = d_aki.hadm_id
        AND (
            (d_aki.icd_version = 9 AND d_aki.icd_code IN ('5845', '5849'))
            OR
            (d_aki.icd_version = 10 AND d_aki.icd_code IN ('N170', 'N179'))
        )
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p_mv
        ON ca.hadm_id = p_mv.hadm_id
        AND (
            (p_mv.icd_version = 9 AND p_mv.icd_code IN ('9671', '9672'))
            OR
            (p_mv.icd_version = 10 AND p_mv.icd_code IN ('5A195', '5A194'))
        )
    LEFT JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` AS icu
        ON ca.hadm_id = icu.hadm_id
    GROUP BY
        ca.subject_id, ca.hadm_id, ca.admittime, ca.dischtime, ca.dod, ca.los_days
),
adms_with_scores AS (
    SELECT
        cf.subject_id,
        cf.hadm_id,
        cf.admittime,
        cf.dischtime,
        cf.dod,
        cf.los_days,
        -- Composite risk score is the sum of complication flags
        (cf.sepsis_flag + cf.aki_flag + cf.mech_vent_flag + cf.icu_stay_flag) AS composite_risk_score,
        -- Flag mortality within 90 days from admission
        CASE
            WHEN cf.dod IS NOT NULL AND DATE_DIFF(cf.dod, cf.admittime, DAY) <= 90 THEN 1
            ELSE 0
        END AS is_90_day_mort,
        -- Flag if any major complication occurred
        CASE
            WHEN (cf.sepsis_flag + cf.aki_flag + cf.mech_vent_flag + cf.icu_stay_flag) > 0 THEN 1
            ELSE 0
        END AS has_major_complication
    FROM
        complication_flags AS cf
),
adms_with_quintiles AS (
    SELECT
        aws.*,
        -- Assign each admission to a risk quintile based on the composite score
        NTILE(5) OVER (ORDER BY aws.composite_risk_score) AS risk_quintile
    FROM
        adms_with_scores AS aws
)
-- Final aggregation to report metrics per quintile
SELECT
    t.risk_quintile,
    COUNT(DISTINCT t.hadm_id) AS N_admissions, -- N
    -- 90-day mortality rate
    ROUND(SUM(t.is_90_day_mort) * 100.0 / COUNT(t.hadm_id), 2) AS mortality_rate_90_day,
    -- Major complication rate
    ROUND(SUM(t.has_major_complication) * 100.0 / COUNT(t.hadm_id), 2) AS major_complication_rate,
    -- Median LOS among 90-day survivors; NULLs are ignored by PERCENTILE_CONT
    ROUND(PERCENTILE_CONT(IF(t.is_90_day_mort = 0, t.los_days, NULL), 0.5) OVER (PARTITION BY t.risk_quintile), 2) AS median_los_90_day_survivors
FROM
    adms_with_quintiles AS t
GROUP BY
    t.risk_quintile
ORDER BY
    t.risk_quintile;