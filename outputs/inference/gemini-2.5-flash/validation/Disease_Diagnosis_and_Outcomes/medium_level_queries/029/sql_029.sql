WITH charlson_comorbidities_flags AS (
    -- Identify the presence of each Charlson Comorbidity for each hospital admission using ICD-10 codes
    -- Each flag is 1 if the comorbidity is present, 0 otherwise.
    -- ICD codes are typically stored without periods in MIMIC-IV
    SELECT
        hadm_id,
        -- Myocardial Infarction (1 point)
        MAX(CASE WHEN icd_code LIKE 'I21%' OR icd_code LIKE 'I22%' THEN 1 ELSE 0 END) AS MI_FLAG,
        -- Congestive Heart Failure (1 point)
        MAX(CASE WHEN icd_code LIKE 'I50%' OR icd_code IN ('I099', 'I110', 'I130', 'I132', 'I255') OR (icd_code LIKE 'I42%' AND icd_code NOT LIKE 'I427%') THEN 1 ELSE 0 END) AS CHF_FLAG,
        -- Peripheral Vascular Disease (1 point)
        MAX(CASE WHEN icd_code LIKE 'I70%' OR icd_code LIKE 'I71%' OR icd_code LIKE 'I731%' OR icd_code LIKE 'I738%' OR icd_code LIKE 'I739%' OR icd_code LIKE 'I771%' OR icd_code LIKE 'I774%' OR icd_code LIKE 'I778%' OR icd_code LIKE 'I779%' OR icd_code LIKE 'G45%' OR icd_code LIKE 'K551%' OR icd_code LIKE 'K557%' OR icd_code LIKE 'Z958%' OR icd_code LIKE 'Z959%' THEN 1 ELSE 0 END) AS PVD_FLAG,
        -- Cerebrovascular Disease (1 point)
        MAX(CASE WHEN (icd_code BETWEEN 'I60' AND 'I699') OR icd_code LIKE 'G46%' THEN 1 ELSE 0 END) AS CVD_FLAG, -- I60-I69 covers all subcodes
        -- Dementia (1 point)
        MAX(CASE WHEN (icd_code LIKE 'F00%' OR icd_code LIKE 'F01%' OR icd_code LIKE 'F02%' OR icd_code LIKE 'F03%') OR icd_code LIKE 'G30%' THEN 1 ELSE 0 END) AS DEMENTIA_FLAG,
        -- Chronic Pulmonary Disease (1 point)
        MAX(CASE WHEN (icd_code LIKE 'J4%' AND SUBSTR(icd_code,2,1) BETWEEN '0' AND '7') OR (icd_code LIKE 'J6%' AND SUBSTR(icd_code,2,1) BETWEEN '0' AND '7' AND NOT (icd_code LIKE 'J680%' OR icd_code LIKE 'J681%' OR icd_code LIKE 'J682%' OR icd_code LIKE 'J683%')) OR icd_code IN ('J684', 'J701', 'J703') THEN 1 ELSE 0 END) AS CPD_FLAG,
        -- Rheumatic Disease (1 point)
        MAX(CASE WHEN icd_code LIKE 'M05%' OR icd_code LIKE 'M06%' OR icd_code IN ('M315','M32%','M33%','M34%','M351%', 'M353%', 'M358%', 'M360%') THEN 1 ELSE 0 END) AS RHEUMATIC_FLAG,
        -- Peptic Ulcer Disease (1 point)
        MAX(CASE WHEN icd_code LIKE 'K25%' OR icd_code LIKE 'K26%' OR icd_code LIKE 'K27%' OR icd_code LIKE 'K28%' THEN 1 ELSE 0 END) AS PUD_FLAG,
        -- Mild Liver Disease (1 point)
        MAX(CASE WHEN icd_code LIKE 'B18%' OR (icd_code LIKE 'K70%' AND (SUBSTR(icd_code,4,1) BETWEEN '0' AND '3' OR icd_code LIKE 'K709%')) OR (icd_code LIKE 'K71%' AND (SUBSTR(icd_code,4,1) BETWEEN '3' AND '5' OR icd_code LIKE 'K717%')) OR icd_code LIKE 'K73%' OR icd_code LIKE 'K74%' OR (icd_code LIKE 'K76%' AND (SUBSTR(icd_code,4,1) BETWEEN '0' AND '3' OR icd_code LIKE 'K768%' OR icd_code LIKE 'K769%')) OR icd_code LIKE 'Z944%' THEN 1 ELSE 0 END) AS MILD_LIVER_FLAG,
        -- Diabetes without Complication (1 point)
        MAX(CASE WHEN (icd_code LIKE 'E100%' OR icd_code LIKE 'E101%' OR icd_code LIKE 'E106%' OR icd_code LIKE 'E108%' OR icd_code LIKE 'E109%') OR (icd_code LIKE 'E110%' OR icd_code LIKE 'E111%' OR icd_code LIKE 'E116%' OR icd_code LIKE 'E118%' OR icd_code LIKE 'E119%') OR (icd_code LIKE 'E120%' OR icd_code LIKE 'E121%' OR icd_code LIKE 'E126%' OR icd_code LIKE 'E128%' OR icd_code LIKE 'E129%') OR (icd_code LIKE 'E130%' OR icd_code LIKE 'E131%' OR icd_code LIKE 'E136%' OR icd_code LIKE 'E138%' OR icd_code LIKE 'E139%') OR (icd_code LIKE 'E140%' OR icd_code LIKE 'E141%' OR icd_code LIKE 'E146%' OR icd_code LIKE 'E148%' OR icd_code LIKE 'E149%') THEN 1 ELSE 0 END) AS DM_NO_COMP_FLAG,
        -- Diabetes with Complication (2 points)
        MAX(CASE WHEN (icd_code LIKE 'E102%' OR icd_code LIKE 'E103%' OR icd_code LIKE 'E104%' OR icd_code LIKE 'E105%' OR icd_code LIKE 'E107%') OR (icd_code LIKE 'E112%' OR icd_code LIKE 'E113%' OR icd_code LIKE 'E114%' OR icd_code LIKE 'E115%' OR icd_code LIKE 'E117%') OR (icd_code LIKE 'E122%' OR icd_code LIKE 'E123%' OR icd_code LIKE 'E124%' OR icd_code LIKE 'E125%' OR icd_code LIKE 'E127%') OR (icd_code LIKE 'E132%' OR icd_code LIKE 'E133%' OR icd_code LIKE 'E134%' OR icd_code LIKE 'E135%' OR icd_code LIKE 'E137%') OR (icd_code LIKE 'E142%' OR icd_code LIKE 'E143%' OR icd_code LIKE 'E144%' OR icd_code LIKE 'E145%' OR icd_code LIKE 'E147%') THEN 1 ELSE 0 END) AS DM_COMP_FLAG,
        -- Hemiplegia or Paraplegia (2 points)
        MAX(CASE WHEN icd_code LIKE 'G81%' OR icd_code LIKE 'G82%' OR (icd_code LIKE 'G83%' AND (SUBSTR(icd_code,4,1) BETWEEN '0' AND '4' OR icd_code LIKE 'G839%')) THEN 1 ELSE 0 END) AS HEMIPLEGIA_FLAG,
        -- Renal Disease (2 points)
        MAX(CASE WHEN icd_code LIKE 'N18%' OR icd_code LIKE 'N19%' OR icd_code IN ('I120', 'I131', 'N250') OR (icd_code LIKE 'Z49%' AND (SUBSTR(icd_code,4,1) BETWEEN '0' AND '2')) OR icd_code LIKE 'Z940%' OR icd_code LIKE 'Z992%' THEN 1 ELSE 0 END) AS RENAL_FLAG,
        -- Malignancy flags (These are treated as distinct; priority logic for scoring is in `charlson_scores`)
        -- Metastatic Solid Tumor (6 points)
        MAX(CASE WHEN icd_code LIKE 'C77%' OR icd_code LIKE 'C78%' OR icd_code LIKE 'C79%' THEN 1 ELSE 0 END) AS METASTATIC_FLAG,
        -- Leukemia (2 points for Charlson)
        MAX(CASE WHEN icd_code LIKE 'C91%' OR icd_code LIKE 'C92%' OR icd_code LIKE 'C93%' OR icd_code LIKE 'C94%' OR icd_code LIKE 'C95%' THEN 1 ELSE 0 END) AS LEUKEMIA_FLAG,
        -- Lymphoma (2 points for Charlson)
        MAX(CASE WHEN (icd_code LIKE 'C81%' OR icd_code LIKE 'C82%' OR icd_code LIKE 'C83%' OR icd_code LIKE 'C84%' OR icd_code LIKE 'C85%') OR icd_code LIKE 'C88%' OR icd_code LIKE 'C96%'THEN 1 ELSE 0 END) AS LYMPHOMA_FLAG,
        -- Any Malignancy (2 points for Charlson, excluding specific types and skin C44)
        MAX(CASE WHEN
            (SUBSTR(icd_code, 1, 1) = 'C' AND SUBSTR(icd_code, 2, 2) BETWEEN '00' AND '97') -- Broad C code range
            AND NOT (icd_code LIKE 'C44%') -- Exclude skin non-melanoma
            AND NOT (icd_code LIKE 'C77%' OR icd_code LIKE 'C78%' OR icd_code LIKE 'C79%') -- Exclude metastatic
            AND NOT (icd_code LIKE 'C91%' OR icd_code LIKE 'C92%' OR icd_code LIKE 'C93%' OR icd_code LIKE 'C94%' OR icd_code LIKE 'C95%') -- Exclude leukemia
            AND NOT (
                icd_code LIKE 'C81%' OR icd_code LIKE 'C82%' OR icd_code LIKE 'C83%' OR icd_code LIKE 'C84%' OR icd_code LIKE 'C85%'
                OR icd_code LIKE 'C88%' OR icd_code LIKE 'C96%'
            ) -- Exclude lymphoma
            THEN 1 ELSE 0 END) AS ANY_MALIGNANCY_FLAG,
        -- Moderate/Severe Liver Disease (3 points)
        MAX(CASE WHEN icd_code IN ('I850', 'I859', 'I864', 'I982') OR icd_code LIKE 'K704%' OR icd_code LIKE 'K721%' OR icd_code LIKE 'K729%' OR icd_code LIKE 'K765%' OR icd_code LIKE 'K766%' OR icd_code LIKE 'K767%' THEN 1 ELSE 0 END) AS SEV_LIVER_FLAG,
        -- AIDS / HIV (6 points)
        MAX(CASE WHEN icd_code LIKE 'B20%' OR icd_code LIKE 'B21%' OR icd_code LIKE 'B22%' OR icd_code LIKE 'B23%' OR icd_code LIKE 'B24%' THEN 1 ELSE 0 END) AS AIDS_FLAG
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        icd_version = 10
    GROUP BY
        hadm_id
),
charlson_scores AS (
    -- Calculate the total Charlson Comorbidity Index score for each admission
    -- Malignancy scoring follows a hierarchy: Metastatic > Leukemia/Lymphoma > Any_Malignancy
    SELECT
        hadm_id,
        (
            MI_FLAG * 1 +
            CHF_FLAG * 1 +
            PVD_FLAG * 1 +
            CVD_FLAG * 1 +
            DEMENTIA_FLAG * 1 +
            CPD_FLAG * 1 +
            RHEUMATIC_FLAG * 1 +
            PUD_FLAG * 1 +
            MILD_LIVER_FLAG * 1 +
            DM_NO_COMP_FLAG * 1 +
            DM_COMP_FLAG * 2 +
            HEMIPLEGIA_FLAG * 2 +
            RENAL_FLAG * 2 +
            SEV_LIVER_FLAG * 3 +
            AIDS_FLAG * 6 +
            -- Malignancy logic: apply the highest relevant score
            CASE
                WHEN METASTATIC_FLAG = 1 THEN 6
                WHEN LEUKEMIA_FLAG = 1 THEN 2
                WHEN LYMPHOMA_FLAG = 1 THEN 2
                WHEN ANY_MALIGNANCY_FLAG = 1 THEN 2
                ELSE 0
            END
        ) AS charlson_score
    FROM
        charlson_comorbidities_flags
),
admissions_cohort AS (
    -- Select female patients aged 57-67 and their admission details
    SELECT
        pa.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag,
        DATETIME_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pa
        ON ad.subject_id = pa.subject_id
    WHERE
        pa.gender = 'F'
        AND pa.anchor_age BETWEEN 57 AND 67
        AND ad.dischtime IS NOT NULL -- Ensure discharge time exists for LOS calculation
),
sepsis_diagnoses AS (
    -- Identify the presence of septic shock or general sepsis codes for each admission
    SELECT
        di.hadm_id,
        MAX(CASE WHEN di.icd_code LIKE 'R6521%' THEN 1 ELSE 0 END) AS has_septic_shock,
        MAX(CASE WHEN di.icd_code LIKE 'A40%' OR di.icd_code LIKE 'A41%' OR di.icd_code LIKE 'R6520%' THEN 1 ELSE 0 END) AS has_sepsis
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    WHERE
        di.icd_version = 10
    GROUP BY
        di.hadm_id
),
admissions_with_sepsis_status AS (
    -- Classify each relevant admission into 'Septic Shock' or 'Sepsis (no shock)'
    -- Septic Shock takes precedence if both types of codes are present.
    SELECT
        ac.subject_id,
        ac.hadm_id,
        ac.admittime,
        ac.dischtime,
        ac.hospital_expire_flag,
        ac.los_days,
        CASE
            WHEN sd.has_septic_shock = 1 THEN 'Septic Shock'
            WHEN sd.has_sepsis = 1 THEN 'Sepsis (no shock)'
            ELSE NULL -- Exclude admissions with no relevant sepsis codes
        END AS sepsis_type
    FROM
        admissions_cohort AS ac
    JOIN
        sepsis_diagnoses AS sd
        ON ac.hadm_id = sd.hadm_id
    WHERE
        (sd.has_septic_shock = 1 OR sd.has_sepsis = 1) -- Only include patients classified with either type of sepsis
),
final_cohort_data AS (
    -- Combine all patient, admission, sepsis, and Charlson data, and apply final categorizations
    SELECT
        aws.subject_id,
        aws.hadm_id,
        aws.sepsis_type,
        aws.hospital_expire_flag,
        CASE
            WHEN aws.los_days <= 7 THEN 'LOS <= 7 days'
            ELSE 'LOS > 7 days'
        END AS los_category,
        COALESCE(cs.charlson_score, 0) AS charlson_score, -- Assign 0 if no Charlson codes found
        CASE
            WHEN COALESCE(cs.charlson_score, 0) <= 3 THEN 'Charlson <= 3'
            WHEN COALESCE(cs.charlson_score, 0) BETWEEN 4 AND 5 THEN 'Charlson 4-5'
            ELSE 'Charlson > 5'
        END AS charlson_category
    FROM
        admissions_with_sepsis_status AS aws
    LEFT JOIN
        charlson_scores AS cs
        ON aws.hadm_id = cs.hadm_id
),
grouped_results AS (
    -- Aggregate results by sepsis type, LOS category, and Charlson category
    SELECT
        fcd.sepsis_type,
        fcd.los_category,
        fcd.charlson_category,
        COUNT(fcd.hadm_id) AS total_admissions,
        SUM(fcd.hospital_expire_flag) AS mortality_count,
        ROUND(SUM(fcd.hospital_expire_flag) * 100.0 / COUNT(fcd.hadm_id), 2) AS mortality_percentage
    FROM
        final_cohort_data AS fcd
    GROUP BY
        fcd.sepsis_type,
        fcd.los_category,
        fcd.charlson_category
)
-- Final selection and calculation of differences
SELECT
    gr_sepsis.los_category,
    gr_sepsis.charlson_category,
    gr_sepsis.total_admissions AS total_admissions_sepsis_no_shock,
    gr_sepsis.mortality_count AS mortality_count_sepsis_no_shock,
    gr_sepsis.mortality_percentage AS mortality_pct_sepsis_no_shock,
    gr_shock.total_admissions AS total_admissions_septic_shock,
    gr_shock.mortality_count AS mortality_count_septic_shock,
    gr_shock.mortality_percentage AS mortality_pct_septic_shock,
    -- Absolute Difference: Septic Shock mortality % - Sepsis (no shock) mortality %
    ROUND(gr_shock.mortality_percentage - gr_sepsis.mortality_percentage, 2) AS absolute_difference_pct_points,
    -- Relative Difference: ((Septic Shock mortality %) - (Sepsis (no shock) mortality %)) / (Sepsis (no shock) mortality %) * 100
    CASE
        WHEN gr_sepsis.mortality_percentage IS NULL OR gr_sepsis.mortality_percentage = 0 THEN NULL -- Cannot calculate relative difference if baseline is zero or null
        ELSE ROUND((gr_shock.mortality_percentage - gr_sepsis.mortality_percentage) / gr_sepsis.mortality_percentage * 100, 2)
    END AS relative_difference_pct
FROM
    grouped_results AS gr_sepsis
JOIN
    grouped_results AS gr_shock
    ON gr_sepsis.los_category = gr_shock.los_category
    AND gr_sepsis.charlson_category = gr_shock.charlson_category
WHERE
    gr_sepsis.sepsis_type = 'Sepsis (no shock)'
    AND gr_shock.sepsis_type = 'Septic Shock'
ORDER BY
    gr_sepsis.los_category,
    gr_sepsis.charlson_category;