WITH BaseAdmissions AS (
    -- Step 1: Base admission cohort with age, gender, LOS
    SELECT
        ad.subject_id,
        ad.hadm_id,
        p.gender,
        (EXTRACT(YEAR FROM ad.admittime) - p.anchor_year + p.anchor_age) AS age_at_admission,
        ad.admittime,
        ad.dischtime,
        DATE_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days,
        ad.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON ad.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND (EXTRACT(YEAR FROM ad.admittime) - p.anchor_year + p.anchor_age) BETWEEN 51 AND 61
        AND ad.dischtime IS NOT NULL -- Ensure discharge time exists for LOS calculation
        AND DATE_DIFF(ad.dischtime, ad.admittime, DAY) >= 0 -- Ensure valid LOS
),
StemiNstemi AS (
    -- Step 2: Identify STEMI and NSTEMI diagnoses for each admission
    SELECT
        d.hadm_id,
        MAX(CASE
            WHEN (d.icd_version = 9 AND d.icd_code IN ('41001', '41011', '41021', '41031', '41041', '41051', '41061', '41081', '41091')) OR
                 (d.icd_version = 10 AND (d.icd_code LIKE 'I210%' OR d.icd_code LIKE 'I211%' OR d.icd_code LIKE 'I212%' OR d.icd_code LIKE 'I213%' OR d.icd_code LIKE 'I240%'))
            THEN 1 ELSE 0
        END) AS has_stemi,
        MAX(CASE
            WHEN (d.icd_version = 9 AND d.icd_code = '41071') OR
                 (d.icd_version = 10 AND (d.icd_code LIKE 'I214%' OR d.icd_code LIKE 'I20%')) -- Added I20 for NSTEMI
            THEN 1 ELSE 0
        END) AS has_nstemi
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    GROUP BY
        d.hadm_id
),
ComorbiditiesRaw AS (
    -- Step 3: Identify common comorbidities for each admission (including CKD and Diabetes)
    SELECT
        d.hadm_id,
        MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code LIKE '585%') OR (d.icd_version = 10 AND d.icd_code LIKE 'N18%') THEN 1 ELSE 0 END) AS has_ckd,
        MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code LIKE '250%') OR (d.icd_version = 10 AND (d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E13%')) THEN 1 ELSE 0 END) AS has_diabetes,
        MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code LIKE '428%') OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%') THEN 1 ELSE 0 END) AS has_chf,
        MAX(CASE WHEN (d.icd_version = 9 AND (d.icd_code LIKE '490%' OR d.icd_code LIKE '491%' OR d.icd_code LIKE '492%' OR d.icd_code LIKE '496%')) OR (d.icd_version = 10 AND (d.icd_code LIKE 'J41%' OR d.icd_code LIKE 'J42%' OR d.icd_code LIKE 'J43%' OR d.icd_code LIKE 'J44%' OR d.icd_code LIKE 'J47%')) THEN 1 ELSE 0 END) AS has_copd, -- Added I490 and J47 for completeness
        MAX(CASE WHEN (d.icd_version = 9 AND (d.icd_code LIKE '433%' OR d.icd_code LIKE '434%' OR d.icd_code LIKE '436%' OR d.icd_code LIKE '437%')) OR (d.icd_version = 10 AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%' OR d.icd_code LIKE 'I63%' OR d.icd_code LIKE 'I64%' OR d.icd_code LIKE 'I65%' OR d.icd_code LIKE 'I66%' OR d.icd_code LIKE 'I67%' OR d.icd_code LIKE 'G45%' OR d.icd_code LIKE 'G46%')) THEN 1 ELSE 0 END) AS has_cerebrovascular, -- Added G45/G46 for completeness
        MAX(CASE WHEN (d.icd_version = 9 AND (d.icd_code LIKE '196%' OR d.icd_code LIKE '197%' OR d.icd_code LIKE '198%' OR d.icd_code LIKE '199%' OR d.icd_code LIKE 'V10%')) OR (d.icd_version = 10 AND (d.icd_code LIKE 'C77%' OR d.icd_code LIKE 'C78%' OR d.icd_code LIKE 'C79%' OR d.icd_code LIKE 'C80%' OR d.icd_code LIKE 'Z85%')) THEN 1 ELSE 0 END) AS has_metastatic_cancer -- Added V10/Z85 for history of malignancy
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    GROUP BY
        d.hadm_id
),
CohortWithStemiNstemi AS (
    -- Step 4: Combine base admissions with STEMI/NSTEMI classification
    SELECT
        ba.*,
        CASE
            WHEN sn.has_stemi = 1 AND sn.has_nstemi = 0 THEN 'STEMI Only'
            WHEN sn.has_nstemi = 1 AND sn.has_stemi = 0 THEN 'NSTEMI Only'
            -- The WHERE clause filters out "Both or Neither", so these are the only two groups
        END AS admission_group
    FROM
        BaseAdmissions AS ba
    INNER JOIN
        StemiNstemi AS sn
        ON ba.hadm_id = sn.hadm_id
    WHERE
        (sn.has_stemi = 1 AND sn.has_nstemi = 0) OR (sn.has_nstemi = 1 AND sn.has_stemi = 0)
),
FinalCohort AS (
    -- Step 5: Final cohort combining all information and deriving groups
    SELECT
        csn.*,
        COALESCE(cr.has_ckd, 0) AS has_ckd,
        COALESCE(cr.has_diabetes, 0) AS has_diabetes,
        COALESCE(cr.has_chf, 0) AS has_chf,
        COALESCE(cr.has_copd, 0) AS has_copd,
        COALESCE(cr.has_cerebrovascular, 0) AS has_cerebrovascular,
        COALESCE(cr.has_metastatic_cancer, 0) AS has_metastatic_cancer,
        (
            COALESCE(cr.has_ckd, 0) +
            COALESCE(cr.has_diabetes, 0) +
            COALESCE(cr.has_chf, 0) +
            COALESCE(cr.has_copd, 0) +
            COALESCE(cr.has_cerebrovascular, 0) +
            COALESCE(cr.has_metastatic_cancer, 0)
        ) AS total_comorbidities,
        CASE
            WHEN csn.los_days BETWEEN 1 AND 2 THEN '1-2 days'
            WHEN csn.los_days BETWEEN 3 AND 5 THEN '3-5 days'
            WHEN csn.los_days BETWEEN 6 AND 9 THEN '6-9 days'
            WHEN csn.los_days >= 10 THEN '>=10 days'
            ELSE 'Unknown LOS' -- Should ideally not be reached with valid LOS filter
        END AS los_group,
        CASE
            WHEN (
                COALESCE(cr.has_ckd, 0) +
                COALESCE(cr.has_diabetes, 0) +
                COALESCE(cr.has_chf, 0) +
                COALESCE(cr.has_copd, 0) +
                COALESCE(cr.has_cerebrovascular, 0) +
                COALESCE(cr.has_metastatic_cancer, 0)
            ) BETWEEN 0 AND 1 THEN '0-1 Comorbidities'
            WHEN (
                COALESCE(cr.has_ckd, 0) +
                COALESCE(cr.has_diabetes, 0) +
                COALESCE(cr.has_chf, 0) +
                COALESCE(cr.has_copd, 0) +
                COALESCE(cr.has_cerebrovascular, 0) +
                COALESCE(cr.has_metastatic_cancer, 0) -- Removed the erroneous '2' from here
            ) = 2 THEN '2 Comorbidities'
            WHEN (
                COALESCE(cr.has_ckd, 0) +
                COALESCE(cr.has_diabetes, 0) +
                COALESCE(cr.has_chf, 0) +
                COALESCE(cr.has_copd, 0) +
                COALESCE(cr.has_cerebrovascular, 0) +
                COALESCE(cr.has_metastatic_cancer, 0)
            ) >= 3 THEN '>=3 Comorbidities'
            ELSE 'Unknown Comorbidity Group'
        END AS comorbidity_group
    FROM
        CohortWithStemiNstemi AS csn
    LEFT JOIN
        ComorbiditiesRaw AS cr
        ON csn.hadm_id = cr.hadm_id
)
-- Step 6: Final aggregation to answer the question
SELECT
    fc.admission_group,
    fc.los_group,
    fc.comorbidity_group,
    COUNT(DISTINCT fc.hadm_id) AS N_admissions,
    ROUND(AVG(fc.hospital_expire_flag) * 100, 2) AS in_hospital_mortality_percent,
    ROUND(AVG(fc.has_ckd) * 100, 2) AS ckd_prevalence_percent,
    ROUND(AVG(fc.has_diabetes) * 100, 2) AS diabetes_prevalence_percent
FROM
    FinalCohort AS fc
GROUP BY
    fc.admission_group,
    fc.los_group,
    fc.comorbidity_group
ORDER BY
    fc.admission_group,
    fc.los_group,
    fc.comorbidity_group;