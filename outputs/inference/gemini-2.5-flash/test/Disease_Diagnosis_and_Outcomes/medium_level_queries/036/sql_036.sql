WITH CohortHF AS (
    -- CTE 1: Identify the main cohort: females aged 39-49 with a heart failure diagnosis (ICD-10 I50%)
    SELECT DISTINCT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_hf
        ON adm.hadm_id = di_hf.hadm_id
    WHERE
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 39 AND 49
        AND di_hf.icd_version = 10
        AND di_hf.icd_code LIKE 'I50%' -- ICD-10 for Heart Failure
),
CohortWithComorbidities AS (
    -- CTE 2: Calculate LOS category and identify presence of CKD and Diabetes for each admission in the cohort
    SELECT
        coh.subject_id,
        coh.hadm_id,
        coh.hospital_expire_flag,
        DATETIME_DIFF(coh.dischtime, coh.admittime, DAY) AS los_days,
        CASE
            WHEN DATETIME_DIFF(coh.dischtime, coh.admittime, DAY) <= 5 THEN 'Low LOS (<=5 days)'
            ELSE 'High LOS (>5 days)'
        END AS los_category,
        -- Check for presence of CKD (ICD-10 N18%)
        -- We join `diagnoses_icd` again to CohortHF to check for *any* CKD/Diabetes diagnosis for the admission
        MAX(CASE WHEN di.icd_version = 10 AND di.icd_code LIKE 'N18%' THEN 1 ELSE 0 END) AS has_ckd,
        -- Check for presence of Diabetes (ICD-10 E10%, E11%, E13%)
        MAX(CASE WHEN di.icd_version = 10 AND (di.icd_code LIKE 'E10%' OR di.icd_code LIKE 'E11%' OR di.icd_code LIKE 'E13%') THEN 1 ELSE 0 END) AS has_diabetes
    FROM
        CohortHF AS coh
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di -- Corrected dataset reference
        ON coh.hadm_id = di.hadm_id
    GROUP BY
        coh.subject_id,
        coh.hadm_id,
        coh.hospital_expire_flag,
        coh.admittime,
        coh.dischtime
),
CohortWithComorbidityTertiles AS (
    -- CTE 3: Calculate comorbidity score and assign tertile (Low/Med/High based on 0, 1, or 2 comorbidities)
    SELECT
        *,
        (has_ckd + has_diabetes) AS comorbidity_score,
        CASE
            WHEN (has_ckd + has_diabetes) = 0 THEN 'Low'
            WHEN (has_ckd + has_diabetes) = 1 THEN 'Medium'
            WHEN (has_ckd + has_diabetes) = 2 THEN 'High'
            ELSE 'Unknown' -- Should not be reached with current comorbidity definitions
        END AS comorbidity_tertile
    FROM
        CohortWithComorbidities
)
-- Final aggregation to report in-hospital mortality, N, and prevalence by LOS and comorbidity tertiles
SELECT
    los_category,
    comorbidity_tertile,
    COUNT(DISTINCT subject_id || '_' || hadm_id) AS N_admissions, -- Count unique admissions
    SUM(hospital_expire_flag) AS N_mortality,
    ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_percent,
    ROUND(AVG(has_ckd) * 100, 2) AS ckd_prevalence_percent,
    ROUND(AVG(has_diabetes) * 100, 2) AS diabetes_prevalence_percent
FROM
    CohortWithComorbidityTertiles
GROUP BY
    los_category,
    comorbidity_tertile
ORDER BY
    los_category,
    CASE comorbidity_tertile
        WHEN 'Low' THEN 1
        WHEN 'Medium' THEN 2
        WHEN 'High' THEN 3
        ELSE 4 -- For 'Unknown' if it ever occurs
    END;