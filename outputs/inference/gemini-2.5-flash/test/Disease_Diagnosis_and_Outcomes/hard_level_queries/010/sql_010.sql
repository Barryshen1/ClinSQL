WITH dka_icd AS (
    SELECT DISTINCT icd_code, icd_version
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE
       long_title LIKE '%diabetic ketoacidosis%'
),
-- Step 2: Define specific complication ICD codes (example sets - expand this list as clinically appropriate)
cardiovascular_icd AS (
    SELECT DISTINCT icd_code, icd_version
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE
        (icd_version = 10 AND (
               icd_code LIKE 'I21%' OR icd_code LIKE 'I22%' OR icd_code LIKE 'I23%' -- Myocardial Infarction
            OR icd_code LIKE 'I50%' -- Heart failure
            OR icd_code LIKE 'I60%' OR icd_code LIKE 'I61%' OR icd_code LIKE 'I63%' OR icd_code LIKE 'I64%' -- Stroke (Ischemic, Hemorrhagic, Unspecified)
            OR icd_code LIKE 'I48%' -- Atrial fibrillation and flutter
        ))
        OR (icd_version = 9 AND (
               icd_code LIKE '410%' OR icd_code LIKE '411%' OR icd_code LIKE '412%' -- Myocardial Infarction
            OR icd_code LIKE '428%' -- Heart failure
            OR icd_code LIKE '430%' OR icd_code LIKE '431%' OR icd_code LIKE '434%' OR icd_code LIKE '436%' -- Stroke
        ))
),
neurologic_icd AS (
    SELECT DISTINCT icd_code, icd_version
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE
        (icd_version = 10 AND (
               icd_code LIKE 'G40%' OR icd_code LIKE 'G41%' -- Seizure/Epilepsy
            OR icd_code LIKE 'G93.4%' -- Encephalopathy
            OR icd_code LIKE 'I60%' OR icd_code LIKE 'I61%' OR icd_code LIKE 'I63%' OR icd_code LIKE 'I64%' -- Stroke (overlap with CV)
            OR icd_code LIKE 'R40.2%' -- Coma
            OR icd_code LIKE 'S06%' -- Intracranial injury
        ))
        OR (icd_version = 9 AND (
               icd_code LIKE '345%' -- Epilepsy
            OR icd_code LIKE '348.3%' -- Encephalopathy
            OR icd_code LIKE '430%' OR icd_code LIKE '431%' OR icd_code LIKE '434%' OR icd_code LIKE '436%' -- Stroke
            OR icd_code LIKE '780.0%' -- Coma
            OR icd_code LIKE '85%' -- Intracranial injury
        ))
),
-- Step 3: Base cohort of male inpatients aged 39-49
base_cohort AS (
    SELECT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.deathtime,
        a.hospital_expire_flag,
        p.gender,
        p.anchor_age,
        p.dod
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 39 AND 49
),
-- Step 4: Identify DKA admissions, 30-day mortality, LOS, and complications for each admission
admission_flags AS (
    SELECT
        bc.subject_id,
        bc.hadm_id,
        bc.admittime,
        bc.dischtime,
        bc.anchor_age,
        -- DKA Flag: 1 if this admission has any DKA diagnosis
        MAX(CASE WHEN dka.icd_code IS NOT NULL THEN 1 ELSE 0 END) AS is_dka,
        -- 30-day mortality flag: 1 if patient died within 30 days of admission
        CASE
            WHEN (bc.deathtime IS NOT NULL AND DATE_DIFF(DATE(bc.deathtime), DATE(bc.admittime), DAY) <= 30)
                 OR (bc.dod IS NOT NULL AND DATE_DIFF(DATE(bc.dod), DATE(bc.admittime), DAY) <= 30 AND bc.hospital_expire_flag = 0)
                THEN 1
            ELSE 0
        END AS thirty_day_mortality,
        -- Length of Stay for survivors: NULL if patient died within 30 days
        CASE
            WHEN (bc.deathtime IS NULL OR DATE_DIFF(DATE(bc.deathtime), DATE(bc.admittime), DAY) > 30)
                 AND (bc.dod IS NULL OR DATE_DIFF(DATE(bc.dod), DATE(bc.admittime), DAY) > 30 OR bc.hospital_expire_flag = 1)
                THEN DATE_DIFF(DATE(bc.dischtime), DATE(bc.admittime), DAY)
            ELSE NULL -- This admission resulted in 30-day mortality, so LOS is not counted for survivor group
        END AS los_survivor_days,
        -- Cardiovascular complication flag
        MAX(CASE WHEN cvc.icd_code IS NOT NULL THEN 1 ELSE 0 END) AS has_cv_complication,
        -- Neurologic complication flag
        MAX(CASE WHEN nc.icd_code IS NOT NULL THEN 1 ELSE 0 END) AS has_neuro_complication
    FROM
        base_cohort bc
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_dka
        ON bc.hadm_id = di_dka.hadm_id
    LEFT JOIN
        dka_icd dka
        ON di_dka.icd_code = dka.icd_code AND di_dka.icd_version = dka.icd_version
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_cvc
        ON bc.hadm_id = di_cvc.hadm_id
    LEFT JOIN
        cardiovascular_icd cvc
        ON di_cvc.icd_code = cvc.icd_code AND di_cvc.icd_version = cvc.icd_version
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_nc
        ON bc.hadm_id = di_nc.hadm_id
    LEFT JOIN
        neurologic_icd nc
        ON di_nc.icd_code = nc.icd_code AND di_nc.icd_version = nc.icd_version
    GROUP BY
        bc.subject_id, bc.hadm_id, bc.admittime, bc.dischtime, bc.deathtime, bc.dod, bc.hospital_expire_flag, bc.anchor_age
),
-- Step 5: Get DRG Severity Score for each admission (highest if multiple DRGs exist)
drg_severity_scores AS (
    SELECT
        drg.hadm_id,
        MAX(drg.drg_severity) AS drg_severity_score
    FROM
        `physionet-data.mimiciv_3_1_hosp.drgcodes` drg
    GROUP BY
        drg.hadm_id
),
-- Step 6: Consolidate all information and calculate percentile ranks for DRG severity
final_cohort_data AS (
    SELECT
        ad.hadm_id,
        ad.is_dka,
        ad.thirty_day_mortality,
        ad.los_survivor_days,
        ad.has_cv_complication,
        ad.has_neuro_complication,
        drs.drg_severity_score,
        -- Calculate the percentile rank for each admission's DRG severity score
        -- within the entire eligible cohort (all males 39-49 with a DRG severity score).
        -- Higher severity means higher rank.
        PERCENT_RANK() OVER (ORDER BY drs.drg_severity_score ASC) AS drg_severity_percent_rank
    FROM
        admission_flags ad
    LEFT JOIN
        drg_severity_scores drs
        ON ad.hadm_id = drs.hadm_id
    WHERE drs.drg_severity_score IS NOT NULL -- Only include admissions with a DRG severity score for this calculation
)
-- Step 7: Final aggregation for DKA group and All Males group
SELECT
    'DKA Group (Male 39-49)' AS cohort,
    COUNT(DISTINCT hadm_id) AS num_admissions,
    SAFE_DIVIDE(SUM(thirty_day_mortality), COUNT(DISTINCT hadm_id)) * 100 AS mean_30_day_mortality_percent,
    AVG(drg_severity_score) AS mean_drg_severity_score, -- Mean Risk Score (DRG Severity)
    SAFE_DIVIDE(SUM(has_cv_complication), COUNT(DISTINCT hadm_id)) * 100 AS cv_complication_rate_percent,
    SAFE_DIVIDE(SUM(has_neuro_complication), COUNT(DISTINCT hadm_id)) * 100 AS neuro_complication_rate_percent,
    AVG(los_survivor_days) AS mean_survivor_los_days,
    AVG(drg_severity_percent_rank) * 100 AS mean_drg_severity_percentile_rank -- Mean Percentile Rank for DRG Severity
FROM
    final_cohort_data
WHERE
    is_dka = 1
GROUP BY
    cohort

UNION ALL

SELECT
    'All Males (39-49)' AS cohort,
    COUNT(DISTINCT hadm_id) AS num_admissions,
    SAFE_DIVIDE(SUM(thirty_day_mortality), COUNT(DISTINCT hadm_id)) * 100 AS mean_30_day_mortality_percent,
    AVG(drg_severity_score) AS mean_drg_severity_score, -- Mean Risk Score (DRG Severity)
    SAFE_DIVIDE(SUM(has_cv_complication), COUNT(DISTINCT hadm_id)) * 100 AS cv_complication_rate_percent,
    SAFE_DIVIDE(SUM(has_neuro_complication), COUNT(DISTINCT hadm_id)) * 100 AS neuro_complication_rate_percent,
    AVG(los_survivor_days) AS mean_survivor_los_days,
    AVG(drg_severity_percent_rank) * 100 AS mean_drg_severity_percentile_rank -- Mean Percentile Rank for DRG Severity
FROM
    final_cohort_data
GROUP BY
    cohort
ORDER BY cohort;