WITH
-- CTE to define the base cohort: males, 44-54 years old, with a diagnosis of Heart Failure
cohort AS (
    SELECT DISTINCT adm.subject_id, adm.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        ON adm.hadm_id = dx.hadm_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 44 AND 54
        AND (
            -- Heart Failure ICD codes
            (dx.icd_version = 9 AND dx.icd_code LIKE '428%') OR
            (dx.icd_version = 10 AND dx.icd_code LIKE 'I50%')
        )
),

-- CTE to calculate the Charlson Comorbidity Index for each hospital admission
charlson AS (
    WITH charlson_components AS (
        SELECT
            hadm_id,
            MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('410', '412') THEN 1 WHEN icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('I21', 'I22') THEN 1 ELSE 0 END) AS myocardial_infarction,
            MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '428' THEN 1 WHEN icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'I50' THEN 1 ELSE 0 END) AS congestive_heart_failure,
            MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('440', '441', '443') THEN 1 WHEN icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('I70', 'I71', 'I73') THEN 1 ELSE 0 END) AS peripheral_vascular_disease,
            MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) BETWEEN '430' AND '438' THEN 1 WHEN icd_version = 10 AND SUBSTR(icd_code, 1, 3) BETWEEN 'I60' AND 'I69' THEN 1 ELSE 0 END) AS cerebrovascular_disease,
            MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '290' THEN 1 WHEN icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('F00', 'F01', 'F02', 'F03', 'G30') THEN 1 ELSE 0 END) AS dementia,
            MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) BETWEEN '490' AND '508' THEN 1 WHEN icd_version = 10 AND SUBSTR(icd_code, 1, 3) BETWEEN 'J40' AND 'J47' THEN 1 ELSE 0 END) AS chronic_pulmonary_disease,
            MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('710', '714', '725') THEN 1 WHEN icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('M05', 'M06', 'M32', 'M33', 'M34') THEN 1 ELSE 0 END) AS rheumatologic_disease,
            MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('531', '532', '533', '534') THEN 1 WHEN icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('K25', 'K26', 'K27', 'K28') THEN 1 ELSE 0 END) AS peptic_ulcer_disease,
            MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '571' THEN 1 WHEN icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('K70', 'K73', 'K74') THEN 1 ELSE 0 END) AS mild_liver_disease,
            MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 4) IN ('2500', '2501', '2502', '2503') THEN 1 WHEN icd_version = 10 AND SUBSTR(icd_code, 1, 4) IN ('E100', 'E101', 'E109', 'E110', 'E111', 'E119', 'E120', 'E121', 'E129', 'E130', 'E131', 'E139', 'E140', 'E141', 'E149') THEN 1 ELSE 0 END) AS diabetes_without_cc,
            MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 4) IN ('2504', '2505', '2506', '2507') THEN 1 WHEN icd_version = 10 AND SUBSTR(icd_code, 1, 4) IN ('E102', 'E103', 'E104', 'E105', 'E107', 'E112', 'E113', 'E114', 'E115', 'E117', 'E122', 'E123', 'E124', 'E125', 'E127', 'E132', 'E133', 'E134', 'E135', 'E137', 'E142', 'E143', 'E144', 'E145', 'E147') THEN 1 ELSE 0 END) AS diabetes_with_cc,
            MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('334', '342', '343', '344') THEN 1 WHEN icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('G81', 'G82') THEN 1 ELSE 0 END) AS hemiplegia_or_paraplegia,
            MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('403', '404', '582', '583', '585', '586') THEN 1 WHEN icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('I12', 'I13', 'N18') THEN 1 ELSE 0 END) AS renal_disease,
            MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) BETWEEN '140' AND '172' OR SUBSTR(icd_code, 1, 4) BETWEEN '1740' AND '1958' OR SUBSTR(icd_code, 1, 3) BETWEEN '200' AND '208' THEN 1 WHEN icd_version = 10 AND SUBSTR(icd_code, 1, 3) BETWEEN 'C00' AND 'C97' THEN 1 ELSE 0 END) AS any_malignancy,
            MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('456', '572') THEN 1 WHEN icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('I85', 'I86', 'I98', 'K70', 'K71', 'K72', 'K76') THEN 1 ELSE 0 END) AS severe_liver_disease,
            MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('196', '197', '198', '199') THEN 1 WHEN icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('C77', 'C78', 'C79', 'C80') THEN 1 ELSE 0 END) AS metastatic_solid_tumor,
            MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '042' THEN 1 WHEN icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('B20', 'B21', 'B22', 'B24') THEN 1 ELSE 0 END) AS aids
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        GROUP BY hadm_id
    )
    SELECT
        hadm_id,
        (myocardial_infarction + congestive_heart_failure + peripheral_vascular_disease + cerebrovascular_disease + dementia + chronic_pulmonary_disease + rheumatologic_disease + peptic_ulcer_disease + mild_liver_disease + diabetes_without_cc + 2*diabetes_with_cc + 2*hemiplegia_or_paraplegia + 2*renal_disease + 2*any_malignancy + 3*severe_liver_disease + 6*metastatic_solid_tumor + 6*aids) AS charlson_score
    FROM charlson_components
),

-- CTE to flag interventions for each admission
interventions AS (
    SELECT
        c.hadm_id,
        MAX(CASE WHEN pe.itemid IN (225792, 225794) THEN 1 ELSE 0 END) AS mech_vent_flag,
        MAX(CASE WHEN ie.itemid IN (221906, 221289, 221749, 222315, 221662, 221653) THEN 1 ELSE 0 END) AS vasopressor_flag,
        MAX(CASE WHEN pe.itemid IN (225802, 225803, 225805, 225809) THEN 1 ELSE 0 END) AS rrt_flag
    FROM cohort AS c
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu ON c.hadm_id = icu.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe ON icu.stay_id = pe.stay_id
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.inputevents` AS ie ON icu.stay_id = ie.stay_id
    GROUP BY c.hadm_id
),

-- Staging CTE to combine cohort with all flags and grouping categories
stg_admissions AS (
    SELECT
        c.hadm_id,
        adm.hospital_expire_flag,
        -- Stratification groups
        CASE WHEN icu.hadm_id IS NOT NULL THEN 'ICU' ELSE 'No ICU' END AS icu_group,
        CASE WHEN DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) <= 7 THEN '≤7 days' ELSE '>7 days' END AS los_group,
        CASE
            WHEN COALESCE(ch.charlson_score, 0) <= 1 THEN '0-1'
            WHEN COALESCE(ch.charlson_score, 0) = 2 THEN '2'
            ELSE '≥3'
        END AS charlson_group,
        -- Intervention flags
        COALESCE(inter.mech_vent_flag, 0) AS mech_vent_flag,
        COALESCE(inter.vasopressor_flag, 0) AS vasopressor_flag,
        COALESCE(inter.rrt_flag, 0) AS rrt_flag
    FROM cohort AS c
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON c.hadm_id = adm.hadm_id
    LEFT JOIN (SELECT DISTINCT hadm_id FROM `physionet-data.mimiciv_3_1_icu.icustays`) AS icu
        ON c.hadm_id = icu.hadm_id
    LEFT JOIN charlson AS ch
        ON c.hadm_id = ch.hadm_id
    LEFT JOIN interventions AS inter
        ON c.hadm_id = inter.hadm_id
)

-- Final aggregation and calculation of metrics
SELECT
    icu_group,
    los_group,
    charlson_group,
    COUNT(*) AS n_patients,
    -- In-hospital mortality with 95% CI (Wilson score interval)
    AVG(hospital_expire_flag) * 100 AS mortality_rate_percent,
    (
        (AVG(hospital_expire_flag) + (1.96*1.96 / (2.0*COUNT(*))))
        - 1.96 * SQRT((AVG(hospital_expire_flag)*(1-AVG(hospital_expire_flag))/COUNT(*)) + (1.96*1.96 / (4.0*COUNT(*)*COUNT(*))))
    ) / (1 + (1.96*1.96 / COUNT(*))) * 100 AS mortality_ci95_lower,
    (
        (AVG(hospital_expire_flag) + (1.96*1.96 / (2.0*COUNT(*))))
        + 1.96 * SQRT((AVG(hospital_expire_flag)*(1-AVG(hospital_expire_flag))/COUNT(*)) + (1.96*1.96 / (4.0*COUNT(*)*COUNT(*))))
    ) / (1 + (1.96*1.96 / COUNT(*))) * 100 AS mortality_ci95_upper,
    -- Prevalence of interventions
    AVG(mech_vent_flag) * 100 AS mech_vent_prevalence_percent,
    AVG(vasopressor_flag) * 100 AS vasopressor_prevalence_percent,
    AVG(rrt_flag) * 100 AS rrt_prevalence_percent
FROM stg_admissions
WHERE los_group IS NOT NULL AND charlson_group IS NOT NULL -- Exclude admissions with missing data needed for grouping
GROUP BY icu_group, los_group, charlson_group
ORDER BY icu_group, los_group, charlson_group;