WITH cohort_initial AS (
    -- 1. Define the initial cohort: Males aged 48-58 with a pneumonia diagnosis
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days,
        p.gender,
        (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) AS age_at_admission -- Corrected age calculation
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON adm.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 48 AND 58
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            WHERE di.subject_id = adm.subject_id
              AND di.hadm_id = adm.hadm_id
              AND (
                    (di.icd_version = 9 AND di.icd_code BETWEEN '480' AND '486') OR -- ICD-9 codes for pneumonia
                    (di.icd_version = 10 AND di.icd_code BETWEEN 'J12' AND 'J18') -- ICD-10 codes for pneumonia
                  )
        )
),
med_complexity AS (
    -- 2. Calculate medication complexity (distinct drugs) within the first 24 hours of admission
    SELECT
        ci.hadm_id,
        COUNT(DISTINCT p.drug) AS distinct_meds_24hr
    FROM
        cohort_initial ci
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        ON ci.subject_id = p.subject_id AND ci.hadm_id = p.hadm_id
    WHERE
        p.starttime BETWEEN ci.admittime AND DATETIME_ADD(ci.admittime, INTERVAL 24 HOUR)
    GROUP BY
        ci.hadm_id
),
serotonergic_meds_keywords AS (
    -- Define a list of keywords for common serotonergic medications
    SELECT * FROM UNNEST([
        'citalopram', 'sertraline', 'fluoxetine', 'paroxetine', 'escitalopram', -- SSRIs
        'venlafaxine', 'duloxetine', -- SNRIs
        'amitriptyline', 'nortriptyline', 'imipramine', 'desipramine', -- TCAs
        'mirtazapine', 'trazodone', 'buspirone', 'tramadol', 'ondansetron', -- Others
        'linezolid', 'methylene blue', 'fentanyl' -- Specific risk agents
    ]) AS drug_keyword
),
hadm_serotonergic_meds AS (
    -- 3. Identify admissions with serotonergic-interaction risk (any serotonergic med during stay)
    SELECT DISTINCT
        p.hadm_id,
        TRUE AS has_serotonergic_meds
    FROM
        `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    INNER JOIN
        serotonergic_meds_keywords smk
        ON LOWER(p.drug) LIKE '%' || smk.drug_keyword || '%'
),
icu_patients_flag AS (
    -- 4. Identify admissions with an ICU stay
    SELECT DISTINCT
        icu.hadm_id,
        TRUE AS is_icu_patient
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` icu
),
final_cohort_data AS (
    -- 5. Combine all relevant information for the cohort
    SELECT
        ci.subject_id,
        ci.hadm_id,
        ci.los_days,
        ci.hospital_expire_flag,
        COALESCE(mc.distinct_meds_24hr, 0) AS distinct_meds_24hr,
        COALESCE(hsm.has_serotonergic_meds, FALSE) AS has_serotonergic_meds,
        COALESCE(ipf.is_icu_patient, FALSE) AS is_icu_patient
    FROM
        cohort_initial ci
    LEFT JOIN
        med_complexity mc
        ON ci.hadm_id = mc.hadm_id
    LEFT JOIN
        hadm_serotonergic_meds hsm
        ON ci.hadm_id = hsm.hadm_id
    LEFT JOIN
        icu_patients_flag ipf
        ON ci.hadm_id = ipf.hadm_id
),
stats_serotonergic AS (
    -- 7. Calculate LOS and mortality statistics for the Serotonergic Risk Group
    SELECT
        AVG(fcd.los_days) AS mean_los_days,
        APPROX_QUANTILES(fcd.los_days, 4)[OFFSET(3)] AS p75_los_days, -- 75th percentile for LOS
        SUM(CASE WHEN fcd.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(fcd.hadm_id) AS overall_mortality_rate
    FROM
        final_cohort_data fcd
    WHERE
        fcd.has_serotonergic_meds = TRUE
),
stats_serotonergic_topq_los AS (
    -- Mortality rate among top quartile of LOS for Serotonergic Risk Group
    SELECT
        SUM(CASE WHEN fcd.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(fcd.hadm_id) AS mortality_rate_in_top_q_los
    FROM
        final_cohort_data fcd, stats_serotonergic ss
    WHERE
        fcd.has_serotonergic_meds = TRUE
        AND fcd.los_days >= ss.p75_los_days
),
stats_icu AS (
    -- 7. Calculate LOS and mortality statistics for the ICU Patient Group
    SELECT
        AVG(fcd.los_days) AS mean_los_days,
        APPROX_QUANTILES(fcd.los_days, 4)[OFFSET(3)] AS p75_los_days, -- 75th percentile for LOS
        SUM(CASE WHEN fcd.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(fcd.hadm_id) AS overall_mortality_rate
    FROM
        final_cohort_data fcd
    WHERE
        fcd.is_icu_patient = TRUE
),
stats_icu_topq_los AS (
    -- Mortality rate among top quartile of LOS for ICU Patient Group
    SELECT
        SUM(CASE WHEN fcd.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(fcd.hadm_id) AS mortality_rate_in_top_q_los
    FROM
        final_cohort_data fcd, stats_icu si
    WHERE
        fcd.is_icu_patient = TRUE
        AND fcd.los_days >= si.p75_los_days
)
-- 8. Final UNION ALL to present the results
SELECT
    'Medication Complexity Distribution' AS result_category,
    'Overall Cohort' AS comparison_group,
    NULL AS metric_sub_group,
    CAST(AVG(fcd.distinct_meds_24hr) AS BIGNUMERIC) AS mean_distinct_meds_24hr,
    CAST(APPROX_QUANTILES(fcd.distinct_meds_24hr, 4)[OFFSET(1)] AS BIGNUMERIC) AS p25_distinct_meds_24hr,
    CAST(APPROX_QUANTILES(fcd.distinct_meds_24hr, 4)[OFFSET(2)] AS BIGNUMERIC) AS p50_distinct_meds_24hr,
    CAST(APPROX_QUANTILES(fcd.distinct_meds_24hr, 4)[OFFSET(3)] AS BIGNUMERIC) AS p75_distinct_meds_24hr,
    NULL AS mean_los_days,
    NULL AS p75_los_days,
    NULL AS overall_mortality_rate,
    NULL AS mortality_rate_in_top_q_los
FROM
    final_cohort_data fcd
UNION ALL
SELECT
    'Overall LOS and Mortality' AS result_category,
    'Serotonergic Risk Group' AS comparison_group,
    'Overall' AS metric_sub_group,
    NULL, NULL, NULL, NULL,
    CAST(ss.mean_los_days AS BIGNUMERIC) AS mean_los_days,
    CAST(ss.p75_los_days AS BIGNUMERIC) AS p75_los_days,
    CAST(ss.overall_mortality_rate AS BIGNUMERIC) AS overall_mortality_rate,
    CAST(sstql.mortality_rate_in_top_q_los AS BIGNUMERIC) AS mortality_rate_in_top_q_los
FROM
    stats_serotonergic ss, stats_serotonergic_topq_los sstql
UNION ALL
SELECT
    'Overall LOS and Mortality' AS result_category,
    'ICU Patient Group' AS comparison_group,
    'Overall' AS metric_sub_group,
    NULL, NULL, NULL, NULL,
    CAST(si.mean_los_days AS BIGNUMERIC) AS mean_los_days,
    CAST(si.p75_los_days AS BIGNUMERIC) AS p75_los_days,
    CAST(si.overall_mortality_rate AS BIGNUMERIC) AS overall_mortality_rate,
    CAST(sitql.mortality_rate_in_top_q_los AS BIGNUMERIC) AS mortality_rate_in_top_q_los
FROM
    stats_icu si, stats_icu_topq_los sitql;