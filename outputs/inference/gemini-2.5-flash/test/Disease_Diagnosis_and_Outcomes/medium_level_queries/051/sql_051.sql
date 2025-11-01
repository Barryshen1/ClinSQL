WITH charlson_map AS (
    -- Defines a comprehensive mapping of ICD codes to Charlson Comorbidity Index categories and their weights.
    -- This CTE is crucial for calculating the Charlson score. A complete, validated mapping
    -- is extensive; this provides a representative subset based on common ICD patterns.
    -- For conditions like 'Diabetes', multiple entries allow for higher weights (e.g., complicated diabetes)
    -- to take precedence through the MAX(weight) logic in subsequent CTEs.
    -- ICD-10 (icd_version_code = 10) patterns:
    SELECT 'MI' AS charlson_category, 1 AS weight, 10 AS icd_version_code, ['I21%', 'I22%', 'I25.2%'] AS icd_code_patterns UNION ALL
    SELECT 'CHF', 1 AS weight, 10 AS icd_version_code, ['I50%'] AS icd_code_patterns UNION ALL
    SELECT 'PVD', 1 AS weight, 10 AS icd_version_code, ['I70%', 'I71%', 'I73.1%', 'I73.8%', 'I73.9%', 'I77.1%', 'I79.2%', 'K55.0%', 'Z95.81', 'Z95.82', 'Z95.9%'] AS icd_code_patterns UNION ALL
    SELECT 'CVD', 1 AS weight, 10 AS icd_version_code, ['I60%', 'I61%', 'I62%', 'I63%', 'I64%', 'I65%', 'I66%', 'I67%', 'I68%', 'I69%', 'G45%', 'G46%'] AS icd_code_patterns UNION ALL
    SELECT 'Dementia', 1 AS weight, 10 AS icd_version_code, ['F00%', 'F01%', 'F02%', 'F03%', 'G30%', 'G31.1%'] AS icd_code_patterns UNION ALL
    SELECT 'COPD', 1 AS weight, 10 AS icd_version_code, ['J40%', 'J41%', 'J42%', 'J43%', 'J44%', 'J47%'] AS icd_code_patterns UNION ALL
    SELECT 'Rheumatic', 1 AS weight, 10 AS icd_version_code, ['M05%', 'M06%', 'M07%', 'M08%', 'M09%', 'M10%', 'M11%', 'M30%', 'M31.3%', 'M31.5%', 'M32%', 'M33%', 'M34%', 'M35.1%', 'M35.3%', 'M35.9%', 'M45%'] AS icd_code_patterns UNION ALL
    SELECT 'PUD', 1 AS weight, 10 AS icd_version_code, ['K25%', 'K26%', 'K27%', 'K28%'] AS icd_code_patterns UNION ALL
    SELECT 'MildLiver', 1 AS weight, 10 AS icd_version_code, ['B18%', 'K70%', 'K71%', 'K73%', 'K74%', 'K76.0%', 'K76.2%', 'K76.3%', 'K76.4%', 'K76.8%', 'K76.9%', 'Z94.4%'] AS icd_code_patterns UNION ALL
    -- Diabetes with chronic complications (higher weight: 2)
    SELECT 'Diabetes', 2 AS weight, 10 AS icd_version_code, ['E10.1%', 'E10.2%', 'E10.3%', 'E10.4%', 'E10.5%', 'E10.6%', 'E10.7%', 'E10.8%', 'E10.9%', 'E11.1%', 'E11.2%', 'E11.3%', 'E11.4%', 'E11.5%', 'E11.6%', 'E11.7%', 'E11.8%', 'E11.9%', 'E12.1%', 'E12.2%', 'E12.3%', 'E12.4%', 'E12.5%', 'E12.6%', 'E12.7%', 'E12.8%', 'E12.9%', 'E13.1%', 'E13.2%', 'E13.3%', 'E13.4%', 'E13.5%', 'E13.6%', 'E13.7%', 'E13.8%', 'E13.9%', 'E14.1%', 'E14.2%', 'E14.3%', 'E14.4%', 'E14.5%', 'E14.6%', 'E14.7%', 'E14.8%', 'E14.9%'] AS icd_code_patterns UNION ALL
    -- Diabetes uncomplicated (lower weight: 1, will be overridden by complicated if present)
    SELECT 'Diabetes', 1 AS weight, 10 AS icd_version_code, ['E10%', 'E11%', 'E12%', 'E13%', 'E14%'] AS icd_code_patterns UNION ALL
    SELECT 'Hemiplegia', 2 AS weight, 10 AS icd_version_code, ['G81%', 'G83.1%', 'G83.2%', 'G83.3%'] AS icd_code_patterns UNION ALL
    SELECT 'Renal', 2 AS weight, 10 AS icd_version_code, ['N18%', 'N19%', 'I12.0%', 'I13.1%', 'I13.2%', 'Z94.0%'] AS icd_code_patterns UNION ALL
    SELECT 'Malignancy', 2 AS weight, 10 AS icd_version_code, ['C00%', 'C01%', 'C02%', 'C03%', 'C04%', 'C05%', 'C06%', 'C07%', 'C08%', 'C09%', 'C10%', 'C11%', 'C12%', 'C13%', 'C14%', 'C15%', 'C16%', 'C17%', 'C18%', 'C19%', 'C20%', 'C21%', 'C22%', 'C23%', 'C24%', 'C25%', 'C26%', 'C30%', 'C31%', 'C32%', 'C33%', 'C34%', 'C37%', 'C38%', 'C39%', 'C40%', 'C41%', 'C43%', 'C44%', 'C45%', 'C46%', 'C47%', 'C48%', 'C4A%', 'C4B%', 'C49%', 'C50%', 'C51%', 'C52%', 'C53%', 'C54%', 'C55%', 'C56%', 'C57%', 'C58%', 'C60%', 'C61%', 'C62%', 'C63%', 'C64%', 'C65%', 'C66%', 'C67%', 'C68%', 'C69%', 'C70%', 'C71%', 'C72%', 'C73%', 'C74%', 'C75%', 'C76%', 'C80%', 'D00%', 'D01%', 'D02%', 'D03%', 'D04%', 'D05%', 'D06%', 'D07%', 'D09%', 'D3A%', 'C81%', 'C82%', 'C83%', 'C84%', 'C85%', 'C86%', 'C88%', 'C90%', 'C91%', 'C92%', 'C93%', 'C94%', 'C95%', 'C96%', 'D45%', 'D46%', 'D47%'] AS icd_code_patterns UNION ALL
    SELECT 'SevLiver', 3 AS weight, 10 AS icd_version_code, ['I85%', 'I86.4%', 'I98.2%', 'K72%', 'K76.5%', 'K76.6%', 'K76.7%'] AS icd_code_patterns UNION ALL
    SELECT 'Metastatic', 6 AS weight, 10 AS icd_version_code, ['C77%', 'C78%', 'C79%', 'C7B%'] AS icd_code_patterns UNION ALL
    SELECT 'AIDS', 6 AS weight, 10 AS icd_version_code, ['B20%', 'B21%', 'B22%', 'B23%', 'B24%'] AS icd_code_patterns UNION ALL
    -- ICD-9 (icd_version_code = 9) patterns:
    SELECT 'MI', 1, 9, ['410%', '412%'] UNION ALL
    SELECT 'CHF', 1, 9, ['428%'] UNION ALL
    SELECT 'PVD', 1, 9, ['440%', '441%', '443%', '447.1%', '557.1%', '557.9%', 'V43.4%'] UNION ALL
    SELECT 'CVD', 1, 9, ['43%', '362.3%'] UNION ALL
    SELECT 'Dementia', 1, 9, ['290%', '294.1%', '331.0%', '331.1%'] UNION ALL
    SELECT 'COPD', 1, 9, ['490%', '491%', '492%', '493%', '494%', '496%'] UNION ALL
    SELECT 'Rheumatic', 1, 9, ['710%', '714.0%', '714.2%', '714.3%', '720%'] UNION ALL
    SELECT 'PUD', 1, 9, ['531%', '532%', '533%', '534%'] UNION ALL
    SELECT 'MildLiver', 1, 9, ['070%', '571%', '573.3%', '573.4%', '573.8%', '573.9%', 'V42.7%'] UNION ALL
    -- Diabetes with chronic complications (higher weight: 2)
    SELECT 'Diabetes', 2, 9, ['250.4%', '250.5%', '250.6%', '250.7%', '250.8%', '250.9%'] UNION ALL
    -- Diabetes uncomplicated (lower weight: 1, will be overridden by complicated if present)
    SELECT 'Diabetes', 1, 9, ['250%'] UNION ALL
    SELECT 'Hemiplegia', 2, 9, ['342%', '344.0%', '344.1%', '344.2%'] UNION ALL
    SELECT 'Renal', 2, 9, ['403.01%', '403.11%', '403.91%', '404.02%', '404.03%', '404.12%', '404.13%', '404.92%', '404.93%', '585%', '586%', 'V42.0%', 'V45.1%'] UNION ALL
    SELECT 'Malignancy', 2, 9, ['140%', '141%', '142%', '143%', '144%', '145%', '146%', '147%', '148%', '149%', '150%', '151%', '152%', '153%', '154%', '155%', '156%', '157%', '158%', '159%', '160%', '161%', '162%', '163%', '164%', '165%', '166%', '167%', '168%', '169%', '170%', '171%', '172%', '173%', '174%', '175%', '176%', '179%', '180%', '181%', '182%', '183%', '184%', '185%', '186%', '187%', '188%', '189%', '190%', '191%', '192%', '193%', '194%', '195%', '196%', '197%', '198%', '199%', '200%', '201%', '202%', '203%', '204%', '205%', '206%', '207%', '208%'] UNION ALL
    SELECT 'SevLiver', 3, 9, ['456.0%', '456.1%', '456.2%', '572.2%', '572.3%', '572.4%', '572.8%'] UNION ALL
    SELECT 'Metastatic', 6, 9, ['196%', '197%', '198%', '199%'] UNION ALL
    SELECT 'AIDS', 6, 9, ['042%', '043%', '044%']
),
admissions_with_cohort_filters AS (
    -- Step 1: Identify the cohort of interest - male patients aged 51-61 with postoperative complications.
    SELECT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        -- Calculate hospital length of stay in days.
        TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 51 AND 61
        AND EXISTS ( -- Ensure the admission has a postoperative complication diagnosis.
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_comp
            WHERE di_comp.hadm_id = a.hadm_id
            AND (
                -- ICD-10 codes for postoperative complications (T80-T88)
                (di_comp.icd_version = 10 AND di_comp.icd_code LIKE 'T8[0-8]%')
                OR
                -- ICD-9 codes for postoperative complications (996-999)
                (di_comp.icd_version = 9 AND di_comp.icd_code BETWEEN '996' AND '999')
            )
        )
),
hadm_charlson_category_weights AS (
    -- Step 2: Determine the maximum Charlson weight for each comorbidity category
    -- present in an admission, using the defined charlson_map.
    SELECT
        di.hadm_id,
        cm.charlson_category,
        MAX(cm.weight) AS weight_for_category
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    INNER JOIN
        charlson_map cm ON di.icd_version = cm.icd_version_code
    CROSS JOIN
        UNNEST(cm.icd_code_patterns) AS pattern -- Explode array of patterns to check each one
    WHERE
        di.icd_code LIKE pattern
    GROUP BY
        di.hadm_id,
        cm.charlson_category
),
hadm_charlson_agg AS (
    -- Step 3: Aggregate the category weights to get a total Charlson score per admission.
    -- Also, flag presence of CKD and Diabetes for prevalence calculation.
    SELECT
        hadm_id,
        SUM(weight_for_category) AS charlson_score,
        MAX(CASE WHEN charlson_category = 'Renal' THEN 1 ELSE 0 END) AS has_ckd, -- 1 if Renal category present
        MAX(CASE WHEN charlson_category = 'Diabetes' THEN 1 ELSE 0 END) AS has_diabetes -- 1 if Diabetes category present
    FROM
        hadm_charlson_category_weights
    GROUP BY
        hadm_id
),
final_cohort_data AS (
    -- Step 4: Combine all patient and admission characteristics.
    SELECT
        awcf.subject_id,
        awcf.hadm_id,
        awcf.hospital_expire_flag,
        awcf.los_days,
        -- Determine if the admission included an ICU stay.
        CASE
            WHEN EXISTS (SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` icu WHERE icu.hadm_id = awcf.hadm_id) THEN 'ICU'
            ELSE 'Non-ICU'
        END AS icu_status,
        -- Categorize hospital length of stay.
        CASE
            WHEN awcf.los_days BETWEEN 1 AND 2 THEN '1-2 days'
            WHEN awcf.los_days BETWEEN 3 AND 5 THEN '3-5 days'
            WHEN awcf.los_days BETWEEN 6 AND 9 THEN '6-9 days'
            WHEN awcf.los_days >= 10 THEN '>=10 days'
            ELSE 'Unknown' -- Handle potential null/zero LOS
        END AS los_category,
        -- Incorporate Charlson score and flags, defaulting to 0 if no comorbidities found.
        COALESCE(hca.charlson_score, 0) AS charlson_score,
        COALESCE(hca.has_ckd, 0) AS has_ckd,
        COALESCE(hca.has_diabetes, 0) AS has_diabetes
    FROM
        admissions_with_cohort_filters awcf
    LEFT JOIN
        hadm_charlson_agg hca
        ON awcf.hadm_id = hca.hadm_id
),
grouped_summary AS (
    -- Step 5: Prepare data for final grouping, defining Charlson categories explicitly.
    SELECT
        fcd.icu_status,
        fcd.los_category,
        -- Categorize Charlson Comorbidity Index score.
        CASE
            WHEN fcd.charlson_score BETWEEN 0 AND 1 THEN '0-1'
            WHEN fcd.charlson_score = 2 THEN '2'
            WHEN fcd.charlson_score >= 3 THEN '>=3'
            ELSE 'Unknown' -- Handle unexpected scores
        END AS charlson_category,
        fcd.hadm_id,
        fcd.hospital_expire_flag,
        fcd.los_days,
        fcd.has_ckd,
        fcd.has_diabetes
    FROM
        final_cohort_data fcd
    WHERE
        fcd.los_category != 'Unknown' -- Exclude admissions where LOS could not be categorized
        AND (CASE WHEN fcd.charlson_score BETWEEN 0 AND 1 THEN '0-1' WHEN fcd.charlson_score = 2 THEN '2' WHEN fcd.charlson_score >= 3 THEN '>=3' ELSE 'Unknown' END) != 'Unknown'
)
-- Step 6: Final aggregation to compute mortality, median LOS, and prevalence for each stratum.
SELECT
    gs.icu_status,
    gs.los_category,
    gs.charlson_category,
    COUNT(gs.hadm_id) AS total_admissions,
    SAFE_DIVIDE(SUM(gs.hospital_expire_flag), COUNT(gs.hadm_id)) * 100 AS mortality_percentage,
    -- Replaced PERCENTILE_CONT with APPROX_QUANTILES for BigQuery compatibility.
    APPROX_QUANTILES(gs.los_days, 2)[OFFSET(1)] AS median_los_days,
    SAFE_DIVIDE(SUM(gs.has_ckd), COUNT(gs.hadm_id)) * 100 AS ckd_prevalence_percentage,
    SAFE_DIVIDE(SUM(gs.has_diabetes), COUNT(gs.hadm_id)) * 100 AS diabetes_prevalence_percentage
FROM
    grouped_summary gs
GROUP BY
    gs.icu_status,
    gs.los_category,
    gs.charlson_category
ORDER BY
    gs.icu_status,
    -- Custom ordering for LOS categories
    CASE gs.los_category
        WHEN '1-2 days' THEN 1
        WHEN '3-5 days' THEN 2
        WHEN '6-9 days' THEN 3
        WHEN '>=10 days' THEN 4
        ELSE 5 END,
    -- Custom ordering for Charlson categories
    CASE gs.charlson_category
        WHEN '0-1' THEN 1
        WHEN '2' THEN 2
        WHEN '>=3' THEN 3
        ELSE 4 END;