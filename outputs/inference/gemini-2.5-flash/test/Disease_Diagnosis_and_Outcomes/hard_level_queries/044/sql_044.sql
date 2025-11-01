WITH cohort_base AS (
    SELECT
        pa.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.deathtime,
        ad.hospital_expire_flag,
        DATE_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days,
        -- Calculate 30-day mortality flag
        CASE
            WHEN ad.deathtime IS NOT NULL AND DATE_DIFF(ad.deathtime, ad.admittime, DAY) <= 30 THEN 1
            ELSE 0
        END AS thirty_day_mortality_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` pa
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON pa.subject_id = ad.subject_id
    WHERE
        pa.gender = 'F'
        AND pa.anchor_age BETWEEN 59 AND 69
),
-- Step 2: Identify admissions with Cardiac Arrest
cardiac_arrest_admissions AS (
    SELECT DISTINCT
        hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        -- ICD-9 codes for cardiac arrest
        (icd_version = 9 AND icd_code = '4275') -- Cardiac arrest
        -- ICD-10 codes for cardiac arrest
        OR (icd_version = 10 AND (icd_code = 'I462' OR icd_code = 'I468' OR icd_code = 'I469'))
),
-- Step 3: Identify Cardiovascular Complications (illustrative ICD codes)
cardiovascular_complications AS (
    SELECT DISTINCT
        hadm_id,
        1 AS has_cardiovascular_complication
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (icd_version = 9 AND (
            icd_code LIKE '410%' OR -- Acute myocardial infarction
            icd_code LIKE '428%' OR -- Heart failure
            icd_code = '78551' OR   -- Cardiogenic shock
            (icd_code LIKE '427%' AND icd_code != '4275') -- Dysrhythmias, excluding cardiac arrest itself
        ))
    OR
        (icd_version = 10 AND (
            icd_code LIKE 'I21%' OR -- ST elevation (STEMI) and non-ST elevation (NSTEMI) myocardial infarction
            icd_code LIKE 'I50%' OR -- Heart failure
            icd_code = 'R570' OR    -- Cardiogenic shock
            icd_code LIKE 'I47%' OR -- Paroxysmal tachycardia
            icd_code LIKE 'I48%' OR -- Atrial fibrillation and flutter
            icd_code LIKE 'I49%'    -- Other cardiac arrhythmias (excluding I46 codes for cardiac arrest)
        ))
),
-- Step 4: Identify Neurologic Complications (illustrative ICD codes)
neurologic_complications AS (
    SELECT DISTINCT
        hadm_id,
        1 AS has_neurologic_complication
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (icd_version = 9 AND (
            icd_code = '3481' OR    -- Anoxic brain damage
            icd_code LIKE '7800%' OR -- Coma
            icd_code LIKE '345%' OR -- Epilepsy and recurrent convulsive disorders
            icd_code = '431' OR     -- Intracerebral hemorrhage
            icd_code LIKE '434%'    -- Occlusion of cerebral arteries
        ))
    OR
        (icd_version = 10 AND (
            icd_code = 'G931' OR    -- Anoxic brain damage, not elsewhere classified
            icd_code LIKE 'R402%' OR -- Coma, unspecified
            icd_code LIKE 'G40%' OR -- Epilepsy and recurrent convulsive disorders
            icd_code LIKE 'I60%' OR -- Nontraumatic subarachnoid hemorrhage
            icd_code LIKE 'I61%' OR -- Nontraumatic intracerebral hemorrhage
            icd_code LIKE 'I63%'    -- Cerebral infarction
        ))
),
-- Step 5: Final Cardiac Arrest Cohort with Hypothetical Risk Score and Complication Flags
final_cardiac_arrest_cohort AS (
    SELECT
        cb.subject_id,
        cb.hadm_id,
        cb.admittime,
        cb.dischtime,
        cb.deathtime,
        cb.hospital_expire_flag,
        cb.los_days,
        cb.thirty_day_mortality_flag,
        -- Assign a hypothetical composite risk score (using ROW_NUMBER over RAND() for demonstration)
        -- In a real scenario, this would be a calculated score based on patient data.
        ROW_NUMBER() OVER (ORDER BY RAND()) AS composite_risk_score,
        -- Add complication flags
        IFNULL(cc.has_cardiovascular_complication, 0) AS has_cardiovascular_complication,
        IFNULL(nc.has_neurologic_complication, 0) AS has_neurologic_complication
    FROM
        cohort_base cb
    INNER JOIN
        cardiac_arrest_admissions caa
        ON cb.hadm_id = caa.hadm_id
    LEFT JOIN
        cardiovascular_complications cc
        ON cb.hadm_id = cc.hadm_id
    LEFT JOIN
        neurologic_complications nc
        ON cb.hadm_id = nc.hadm_id
),
-- Step 6: Stratify Cohort into Quartiles by Hypothetical Risk Score
cardiac_arrest_quartiles AS (
    SELECT
        *,
        NTILE(4) OVER (ORDER BY composite_risk_score) AS risk_quartile
    FROM
        final_cardiac_arrest_cohort
)
-- Step 7: Calculate metrics for each risk quartile (first part of UNION ALL)
SELECT
    CONCAT('Quartile ', CAST(risk_quartile AS STRING)) AS Quartile_Category,
    COUNT(DISTINCT hadm_id) AS Total_Admissions,
    SAFE_DIVIDE(SUM(thirty_day_mortality_flag), COUNT(DISTINCT hadm_id)) AS Thirty_Day_Mortality_Rate,
    SAFE_DIVIDE(SUM(has_cardiovascular_complication), COUNT(DISTINCT hadm_id)) AS Cardiovascular_Complication_Rate,
    SAFE_DIVIDE(SUM(has_neurologic_complication), COUNT(DISTINCT hadm_id)) AS Neurologic_Complication_Rate,
    APPROX_QUANTILES(
        CASE WHEN thirty_day_mortality_flag = 0 THEN los_days ELSE NULL END,
        2
    )[OFFSET(1)] AS Median_Survivor_LOS_Days -- Median LOS for survivors only
FROM
    cardiac_arrest_quartiles
GROUP BY
    risk_quartile

UNION ALL

-- Step 8: Calculate Baseline 30-day mortality for all Female 59-69 (second part of UNION ALL)
SELECT
    'Baseline (All Female 59-69)' AS Quartile_Category,
    COUNT(DISTINCT hadm_id) AS Total_Admissions,
    SAFE_DIVIDE(SUM(thirty_day_mortality_flag), COUNT(DISTINCT hadm_id)) AS Thirty_Day_Mortality_Rate,
    CAST(NULL AS FLOAT64) AS Cardiovascular_Complication_Rate,   -- Placeholder for alignment
    CAST(NULL AS FLOAT64) AS Neurologic_Complication_Rate,       -- Placeholder
    CAST(NULL AS FLOAT64) AS Median_Survivor_LOS_Days            -- Placeholder
FROM
    cohort_base -- Reusing the initial cohort_base CTE for baseline calculation

ORDER BY
    CASE
        WHEN Quartile_Category = 'Baseline (All Female 59-69)' THEN 0 -- Sort Baseline first
        WHEN Quartile_Category LIKE 'Quartile %' THEN 1 -- Sort Quartiles second
        ELSE 2 -- Fallback for any other improbable category
    END,
    -- Numerically sort quartiles (e.g., 'Quartile 1' before 'Quartile 10')
    CASE
        WHEN Quartile_Category LIKE 'Quartile %' THEN CAST(SUBSTR(Quartile_Category, STRPOS(Quartile_Category, ' ') + 1) AS INT64)
        ELSE NULL -- For baseline, there's no quartile number to sort by
    END;