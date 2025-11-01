WITH charlson_mapping AS (
    -- Myocardial Infarction
    SELECT 'I21' AS icd_prefix, 3 AS score, 10 AS icd_version UNION ALL SELECT '410' AS icd_prefix, 3 AS score, 9 AS icd_version UNION ALL
    -- Congestive Heart Failure
    SELECT 'I50' AS icd_prefix, 5 AS score, 10 AS icd_version UNION ALL SELECT '428' AS icd_prefix, 5 AS score, 9 AS icd_version UNION ALL
    -- Peripheral Vascular Disease
    SELECT 'I70' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'I71' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'I73.1' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'I73.8' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'I73.9' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'I77.1' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'I79.0' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'I79.2' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL
    SELECT '440' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '441' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '443.1' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '443.8' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '443.9' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '447.1' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '557.1' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT 'V43.4' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL
    -- Cerebrovascular Disease
    SELECT 'I60' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'I61' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'I62' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'I63' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'I64' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'I65' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'I66' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'I67' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'I68' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'I69' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL
    SELECT '430' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '431' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '432' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '433' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '434' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '435' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '436' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '437' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '438' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL
    -- Dementia
    SELECT 'F00' AS icd_prefix, 3 AS score, 10 AS icd_version UNION ALL SELECT 'F01' AS icd_prefix, 3 AS score, 10 AS icd_version UNION ALL SELECT 'F02' AS icd_prefix, 3 AS score, 10 AS icd_version UNION ALL SELECT 'F03' AS icd_prefix, 3 AS score, 10 AS icd_version UNION ALL SELECT 'G30' AS icd_prefix, 3 AS score, 10 AS icd_version UNION ALL
    SELECT '290' AS icd_prefix, 3 AS score, 9 AS icd_version UNION ALL SELECT '294.1' AS icd_prefix, 3 AS score, 9 AS icd_version UNION ALL SELECT '331.0' AS icd_prefix, 3 AS score, 9 AS icd_version UNION ALL
    -- Chronic Pulmonary Disease
    SELECT 'J40' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'J41' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'J42' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'J43' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'J44' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'J45' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'J46' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL
    SELECT '490' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '491' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '492' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '493' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '494' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '495' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '496' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL
    -- Connective Tissue Disease
    SELECT 'M05' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'M06' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'M30' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'M31' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'M32' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'M33' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'M34' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'M35' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'M36' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL
    SELECT '710' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '714' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL
    -- Peptic Ulcer Disease
    SELECT 'K25' AS icd_prefix, 1 AS score, 10 AS icd_version UNION ALL SELECT 'K26' AS icd_prefix, 1 AS score, 10 AS icd_version UNION ALL SELECT 'K27' AS icd_prefix, 1 AS score, 10 AS icd_version UNION ALL
    SELECT '531' AS icd_prefix, 1 AS score, 9 AS icd_version UNION ALL SELECT '532' AS icd_prefix, 1 AS score, 9 AS icd_version UNION ALL SELECT '533' AS icd_prefix, 1 AS score, 9 AS icd_version UNION ALL SELECT '534' AS icd_prefix, 1 AS score, 9 AS icd_version UNION ALL
    -- Paralysis
    SELECT 'G81' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'G82' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL
    SELECT '342' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '344' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL
    -- Renal Disease
    SELECT 'N18' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL
    SELECT '585' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL
    -- Diabetes without complications
    SELECT 'E10.9' AS icd_prefix, 1 AS score, 10 AS icd_version UNION ALL SELECT 'E11.9' AS icd_prefix, 1 AS score, 10 AS icd_version UNION ALL SELECT 'E12.9' AS icd_prefix, 1 AS score, 10 AS icd_version UNION ALL SELECT 'E13.9' AS icd_prefix, 1 AS score, 10 AS icd_version UNION ALL SELECT 'E14.9' AS icd_prefix, 1 AS score, 10 AS icd_version UNION ALL
    -- Diabetes with complications (general prefix will catch E10.x, E11.x, etc. where x is not 9)
    SELECT 'E10' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'E11' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'E12' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'E13' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'E14' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL
    SELECT '250.0' AS icd_prefix, 1 AS score, 9 AS icd_version UNION ALL SELECT '250.1' AS icd_prefix, 1 AS score, 9 AS icd_version UNION ALL
    SELECT '250' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL
    -- Malignancy
    SELECT 'C00' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'C1' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'C2' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'C3' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'C4' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'C5' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'C6' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'C7' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'C8' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL SELECT 'C9' AS icd_prefix, 2 AS score, 10 AS icd_version UNION ALL
    SELECT '140' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '141' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '142' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '143' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '144' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '145' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '146' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '147' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '148' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '149' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '150' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '151' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '152' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '153' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '154' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '155' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '156' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '157' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '158' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '159' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '160' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '161' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '162' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '163' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '164' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '165' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '170' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '171' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '172' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '173' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '174' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '175' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '176' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '179' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL SELECT '195' AS icd_prefix, 2 AS score, 9 AS icd_version UNION ALL
    -- Metastatic Cancer
    SELECT 'C77' AS icd_prefix, 6 AS score, 10 AS icd_version UNION ALL SELECT 'C78' AS icd_prefix, 6 AS score, 10 AS icd_version UNION ALL SELECT 'C79' AS icd_prefix, 6 AS score, 10 AS icd_version UNION ALL
    SELECT '196' AS icd_prefix, 6 AS score, 9 AS icd_version UNION ALL SELECT '197' AS icd_prefix, 6 AS score, 9 AS icd_version UNION ALL SELECT '198' AS icd_prefix, 6 AS score, 9 AS icd_version UNION ALL SELECT '199' AS icd_prefix, 6 AS score, 9 AS icd_version UNION ALL
    -- AIDS
    SELECT 'B20' AS icd_prefix, 6 AS score, 10 AS icd_version UNION ALL
    SELECT '042' AS icd_prefix, 6 AS score, 9 AS icd_version UNION ALL
    -- Severe Liver Disease (supersedes mild liver disease if present)
    SELECT 'K74.3' AS icd_prefix, 4 AS score, 10 AS icd_version UNION ALL SELECT 'K74.4' AS icd_prefix, 4 AS score, 10 AS icd_version UNION ALL SELECT 'K74.5' AS icd_prefix, 4 AS score, 10 AS icd_version UNION ALL
    SELECT '572.3' AS icd_prefix, 4 AS score, 9 AS icd_version UNION ALL SELECT '572.4' AS icd_prefix, 4 AS score, 9 AS icd_version UNION ALL
    -- Mild Liver Disease (only applied if severe is not present)
    SELECT 'K70' AS icd_prefix, 1 AS score, 10 AS icd_version UNION ALL SELECT 'K71' AS icd_prefix, 1 AS score, 10 AS icd_version UNION ALL SELECT 'K72' AS icd_prefix, 1 AS score, 10 AS icd_version UNION ALL SELECT 'K73' AS icd_prefix, 1 AS score, 10 AS icd_version UNION ALL SELECT 'K74.0' AS icd_prefix, 1 AS score, 10 AS icd_version UNION ALL SELECT 'K74.1' AS icd_prefix, 1 AS score, 10 AS icd_version UNION ALL SELECT 'K74.2' AS icd_prefix, 1 AS score, 10 AS icd_version UNION ALL SELECT 'K74.6' AS icd_prefix, 1 AS score, 10 AS icd_version UNION ALL SELECT 'K76.0' AS icd_prefix, 1 AS score, 10 AS icd_version /* excluding K76.1, K76.81, K76.89 */ UNION ALL
    SELECT 'K76.2' AS icd_prefix, 1 AS score, 10 AS icd_version UNION ALL SELECT 'K76.3' AS icd_prefix, 1 AS score, 10 AS icd_version UNION ALL SELECT 'K76.4' AS icd_prefix, 1 AS score, 10 AS icd_version UNION ALL SELECT 'K76.5' AS icd_prefix, 1 AS score, 10 AS icd_version UNION ALL SELECT 'K76.6' AS icd_prefix, 1 AS score, 10 AS icd_version UNION ALL SELECT 'K76.7' AS icd_prefix, 1 AS score, 10 AS icd_version UNION ALL SELECT 'K76.8' AS icd_prefix, 1 AS score, 10 AS icd_version UNION ALL SELECT 'K76.9' AS icd_prefix, 1 AS score, 10 AS icd_version UNION ALL
    SELECT '571' AS icd_prefix, 1 AS score, 9 AS icd_version UNION ALL SELECT '572.2' AS icd_prefix, 1 AS score, 9 AS icd_version UNION ALL SELECT '572.8' AS icd_prefix, 1 AS score, 9 AS icd_version UNION ALL SELECT '573.3' AS icd_prefix, 1 AS score, 9 AS icd_version
),
-- CTE to calculate the Charlson Comorbidity Score for each admission
hadm_charlson_score AS (
    SELECT
        di.subject_id,
        di.hadm_id,
        SUM(DISTINCT cm.score) AS charlson_score
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    INNER JOIN charlson_mapping cm
        ON di.icd_version = cm.icd_version
        AND (
            (di.icd_version = 10 AND STARTS_WITH(di.icd_code, cm.icd_prefix)) OR
            (di.icd_version = 9 AND STARTS_WITH(di.icd_code, cm.icd_prefix))
        )
    GROUP BY
        di.subject_id,
        di.hadm_id
),
-- CTE to identify admissions with postoperative complications
post_op_complications AS (
    SELECT DISTINCT
        di.subject_id,
        di.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    WHERE
        (
            di.icd_version = 10 AND
            (STARTS_WITH(di.icd_code, 'T8') OR STARTS_WITH(di.icd_code, 'Y83') OR STARTS_WITH(di.icd_code, 'Y84'))
        ) OR
        (
            di.icd_version = 9 AND
            (STARTS_WITH(di.icd_code, '996') OR STARTS_WITH(di.icd_code, '997') OR STARTS_WITH(di.icd_code, '998') OR STARTS_WITH(di.icd_code, '999'))
        )
),
-- CTE to get ICU stay flags for admissions
icu_stay_flags AS (
    SELECT DISTINCT
        hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
-- Main CTE to filter admissions and calculate derived metrics
filtered_admissions AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) AS age_at_admission,
        p.gender,
        adm.hospital_expire_flag,
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        CASE
            WHEN adm.hospital_expire_flag = 1
            THEN DATETIME_DIFF(adm.deathtime, adm.admittime, DAY)
            ELSE NULL
        END AS time_to_death_days,
        COALESCE(hcs.charlson_score, 0) AS charlson_score,
        CASE
            WHEN isf.hadm_id IS NOT NULL THEN 'ICU'
            ELSE 'Non-ICU'
        END AS icu_status
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON adm.subject_id = p.subject_id
    INNER JOIN post_op_complications poc
        ON adm.hadm_id = poc.hadm_id
    LEFT JOIN hadm_charlson_score hcs
        ON adm.hadm_id = hcs.hadm_id
    LEFT JOIN icu_stay_flags isf
        ON adm.hadm_id = isf.hadm_id
    WHERE
        p.gender = 'M'
        AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 60 AND 70
),
-- CTE to group data and aggregate time-to-death days into a sorted array for median calculation
grouped_data AS (
    SELECT
        icu_status,
        CASE
            WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
            WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
            WHEN los_days >= 8 THEN '>=8 days'
            ELSE 'Unknown/0 days' -- Handle potential 0 or negative LOS if any
        END AS los_group,
        CASE
            WHEN charlson_score <= 3 THEN '<=3'
            WHEN charlson_score BETWEEN 4 AND 5 THEN '4-5'
            WHEN charlson_score > 5 THEN '>5'
            ELSE 'Unknown'
        END AS charlson_group,
        COUNT(DISTINCT hadm_id) AS N_admissions,
        AVG(hospital_expire_flag) AS avg_hospital_expire_flag,
        -- Collect non-NULL time_to_death_days into a sorted array for median calculation
        ARRAY_AGG(time_to_death_days IGNORE NULLS ORDER BY time_to_death_days) AS time_to_death_array
    FROM filtered_admissions
    GROUP BY
        icu_status,
        los_group,
        charlson_group
)
-- Final aggregation to produce the desired report with manual median calculation
SELECT
    icu_status,
    los_group,
    charlson_group,
    N_admissions,
    ROUND(avg_hospital_expire_flag * 100, 2) AS in_hospital_mortality_percent,
    -- Manual median calculation from the sorted array
    ROUND(
        CASE
            WHEN ARRAY_LENGTH(time_to_death_array) = 0 THEN NULL -- No deaths in this group
            WHEN MOD(ARRAY_LENGTH(time_to_death_array), 2) = 1 THEN time_to_death_array[SAFE_OFFSET(DIV(ARRAY_LENGTH(time_to_death_array), 2))]
            ELSE (
                time_to_death_array[SAFE_OFFSET(DIV(ARRAY_LENGTH(time_to_death_array), 2) - 1)] +
                time_to_death_array[SAFE_OFFSET(DIV(ARRAY_LENGTH(time_to_death_array), 2))]
            ) / 2.0
        END,
    2) AS median_time_to_death_days
FROM grouped_data
ORDER BY
    icu_status,
    los_group,
    charlson_group;