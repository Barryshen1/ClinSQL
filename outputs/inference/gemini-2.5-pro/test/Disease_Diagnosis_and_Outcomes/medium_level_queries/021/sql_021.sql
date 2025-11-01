WITH
-- Step 0: Calculate Charlson Comorbidity Index from ICD codes as the derived table is not available
charlson_cte AS (
    WITH Comorbidities AS (
        SELECT
            hadm_id,
            MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('410', '412') OR icd_version = 10 AND (SUBSTR(icd_code, 1, 3) IN ('I21', 'I22') OR SUBSTR(icd_code, 1, 4) = 'I252') THEN 1 ELSE 0 END) AS mi,
            MAX(CASE WHEN icd_version = 9 AND (SUBSTR(icd_code, 1, 5) IN ('39891', '40201', '40211', '40291', '40401', '40403', '40411', '40413', '40491', '40493') OR SUBSTR(icd_code, 1, 3) = '428') OR icd_version = 10 AND (SUBSTR(icd_code, 1, 3) = 'I50' OR SUBSTR(icd_code, 1, 4) IN ('I099', 'I110', 'I130', 'I132')) THEN 1 ELSE 0 END) AS chf,
            MAX(CASE WHEN icd_version = 9 AND (SUBSTR(icd_code, 1, 3) IN ('440', '441') OR SUBSTR(icd_code, 1, 4) IN ('0930', '4373', '4431', '4432', '4438', '4439', '4471', '5571', '5579', 'V434')) OR icd_version = 10 AND (SUBSTR(icd_code, 1, 3) IN ('I70', 'I71') OR SUBSTR(icd_code, 1, 4) IN ('I731', 'I738', 'I739', 'I771', 'I790', 'I792', 'K551', 'K558', 'K559', 'Z958', 'Z959')) THEN 1 ELSE 0 END) AS pvd,
            MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('430', '431', '432', '433', '434', '435', '436', '437', '438') OR icd_version = 10 AND (SUBSTR(icd_code, 1, 3) IN ('G45', 'G46') OR SUBSTR(icd_code, 1, 4) BETWEEN 'I60' AND 'I699' OR SUBSTR(icd_code, 1, 4) = 'H340') THEN 1 ELSE 0 END) AS cevd,
            MAX(CASE WHEN icd_version = 9 AND (SUBSTR(icd_code, 1, 3) = '290' OR SUBSTR(icd_code, 1, 4) IN ('2941', '3312')) OR icd_version = 10 AND (SUBSTR(icd_code, 1, 3) IN ('F00', 'F01', 'F02', 'F03', 'G30') OR SUBSTR(icd_code, 1, 4) = 'G311') THEN 1 ELSE 0 END) AS dementia,
            MAX(CASE WHEN icd_version = 9 AND (SUBSTR(icd_code, 1, 3) BETWEEN '490' AND '505' OR SUBSTR(icd_code, 1, 4) IN ('4168', '4169', '5064', '5081', '5088')) OR icd_version = 10 AND (SUBSTR(icd_code, 1, 3) BETWEEN 'J40' AND 'J47' OR SUBSTR(icd_code, 1, 3) BETWEEN 'J60' AND 'J67' OR SUBSTR(icd_code, 1, 4) IN ('I278', 'I279')) THEN 1 ELSE 0 END) AS cpd,
            MAX(CASE WHEN icd_version = 9 AND (SUBSTR(icd_code, 1, 3) = '725' OR SUBSTR(icd_code, 1, 4) IN ('4465', '7100', '7101', '7102', '7103', '7104', '7140', '7141', '7142', '7148')) OR icd_version = 10 AND (SUBSTR(icd_code, 1, 3) IN ('M05', 'M06', 'M32', 'M33', 'M34') OR SUBSTR(icd_code, 1, 4) IN ('M315', 'M351', 'M353', 'M360')) THEN 1 ELSE 0 END) AS rheumd,
            MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('531', '532', '533', '534') OR icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('K25', 'K26', 'K27', 'K28') THEN 1 ELSE 0 END) AS pud,
            MAX(CASE WHEN icd_version = 9 AND (SUBSTR(icd_code, 1, 3) = '571' OR SUBSTR(icd_code, 1, 4) IN ('0702', '0703', '0704', '0705', '0706', '0709', '5733', '5734', '5738', '5739', 'V427')) OR icd_version = 10 AND (SUBSTR(icd_code, 1, 4) = 'B18' OR SUBSTR(icd_code, 1, 3) IN ('K73', 'K74') OR SUBSTR(icd_code, 1, 4) IN ('K700', 'K701', 'K702', 'K703', 'K709', 'K713', 'K714', 'K715', 'K717', 'K760', 'K762', 'K763', 'K764', 'K768', 'K769', 'Z944')) THEN 1 ELSE 0 END) AS mild_liver,
            MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 4) IN ('2500', '2501', '2502', '2503', '2507') OR icd_version = 10 AND SUBSTR(icd_code, 1, 4) IN ('E100', 'E101', 'E106', 'E108', 'E109', 'E110', 'E111', 'E116', 'E118', 'E119', 'E120', 'E121', 'E126', 'E128', 'E129', 'E130', 'E131', 'E136', 'E138', 'E139', 'E140', 'E141', 'E146', 'E148', 'E149') THEN 1 ELSE 0 END) AS diab_uncomp,
            MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 4) IN ('2504', '2505', '2506', '2508', '2509') OR icd_version = 10 AND SUBSTR(icd_code, 1, 4) IN ('E102', 'E103', 'E104', 'E105', 'E107', 'E112', 'E113', 'E114', 'E115', 'E117', 'E122', 'E123', 'E124', 'E125', 'E127', 'E132', 'E133', 'E134', 'E135', 'E137', 'E142', 'E143', 'E144', 'E145', 'E147') THEN 1 ELSE 0 END) AS diab_comp,
            MAX(CASE WHEN icd_version = 9 AND (SUBSTR(icd_code, 1, 3) = '342' OR SUBSTR(icd_code, 1, 4) IN ('3341', '343', '3440', '3441', '3442', '3443', '3444', '3445', '3446', '3449')) OR icd_version = 10 AND (SUBSTR(icd_code, 1, 3) IN ('G81', 'G82') OR SUBSTR(icd_code, 1, 4) IN ('G041', 'G114', 'G801', 'G802', 'G830', 'G831', 'G832', 'G833', 'G834', 'G839')) THEN 1 ELSE 0 END) AS paraplegia,
            MAX(CASE WHEN icd_version = 9 AND (SUBSTR(icd_code, 1, 3) IN ('582', '583', '585', '586') OR SUBSTR(icd_code, 1, 4) IN ('4030', '4031', '4039', '4040', '4041', '4049', '5880', 'V420', 'V451', 'V56')) OR icd_version = 10 AND (SUBSTR(icd_code, 1, 3) IN ('N18', 'N19') OR SUBSTR(icd_code, 1, 4) IN ('I120', 'I131', 'N032', 'N033', 'N034', 'N035', 'N036', 'N037', 'N052', 'N053', 'N054', 'N055', 'N056', 'N057', 'N250', 'Z490', 'Z491', 'Z492', 'Z992')) THEN 1 ELSE 0 END) AS renal,
            MAX(CASE WHEN icd_version = 9 AND ((SUBSTR(icd_code, 1, 3) BETWEEN '140' AND '172') OR (SUBSTR(icd_code, 1, 4) BETWEEN '1740' AND '1958') OR SUBSTR(icd_code, 1, 3) IN ('200','201','202','203','204','205','206','207','208', '2386')) OR icd_version = 10 AND ((SUBSTR(icd_code, 1, 3) BETWEEN 'C00' AND 'C76') OR (SUBSTR(icd_code, 1, 3) BETWEEN 'C81' AND 'C96')) THEN 1 ELSE 0 END) AS malignancy,
            MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 4) IN ('4560', '4561', '4562', '5722', '5723', '5724', '5728') OR icd_version = 10 AND SUBSTR(icd_code, 1, 4) IN ('I850', 'I859', 'I864', 'I982', 'K704', 'K711', 'K721', 'K729', 'K765', 'K766', 'K767') THEN 1 ELSE 0 END) AS severe_liver,
            MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('196', '197', '198', '199') OR icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('C77', 'C78', 'C79', 'C80') THEN 1 ELSE 0 END) AS mets,
            MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '042' OR icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('B20', 'B21', 'B22', 'B24') THEN 1 ELSE 0 END) AS aids
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        GROUP BY hadm_id
    )
    SELECT
        hadm_id,
        mi + chf + pvd + cevd + dementia + cpd + rheumd + pud
        + (CASE WHEN severe_liver = 1 THEN 3 WHEN mild_liver = 1 THEN 1 ELSE 0 END)
        + (CASE WHEN diab_comp = 1 THEN 2 WHEN diab_uncomp = 1 THEN 1 ELSE 0 END)
        + (paraplegia * 2)
        + (renal * 2)
        + (CASE WHEN aids = 1 THEN 6 WHEN mets = 1 THEN 6 WHEN malignancy = 1 THEN 2 ELSE 0 END)
        AS charlson_comorbidity_index
    FROM Comorbidities
),
-- Step 1: Identify the base cohort of male patients aged 60-70
patient_cohort AS (
    SELECT
        p.subject_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 60 AND 70
),
-- Step 2: Identify hospital admissions associated with a surgical service
surgical_admissions AS (
    SELECT DISTINCT
        hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.services`
    WHERE
        LOWER(curr_service) LIKE '%surg%'
),
-- Step 3: Identify hospital admissions with a complication diagnosis code
complication_admissions AS (
    SELECT DISTINCT
        hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (icd_version = 9 AND (
            SUBSTR(icd_code, 1, 3) = '996' OR
            SUBSTR(icd_code, 1, 3) = '997' OR
            SUBSTR(icd_code, 1, 3) = '998'
        )) OR
        (icd_version = 10 AND SUBSTR(icd_code, 1, 2) = 'T8')
),
-- Step 4: Create a distinct list of admissions with an ICU stay for an efficient join
icu_admissions AS (
    SELECT DISTINCT
        hadm_id
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays`
),
-- Step 5: Combine all data sources and compute base metrics
analysis_base AS (
    SELECT
        adm.hadm_id,
        adm.hospital_expire_flag,
        DATETIME_DIFF(adm.deathtime, adm.admittime, DAY) AS time_to_death_days,
        ch.charlson_comorbidity_index,
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        CASE
            WHEN icu.hadm_id IS NOT NULL THEN 'ICU'
            ELSE 'Non-ICU'
        END AS icu_status
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    -- Filter for the patient cohort of interest
    INNER JOIN patient_cohort AS p ON adm.subject_id = p.subject_id
    -- Filter for admissions that are both surgical and have a complication diagnosis
    INNER JOIN surgical_admissions AS sa ON adm.hadm_id = sa.hadm_id
    INNER JOIN complication_admissions AS ca ON adm.hadm_id = ca.hadm_id
    -- Join to get the Charlson score from our manually-calculated CTE
    INNER JOIN charlson_cte AS ch ON adm.hadm_id = ch.hadm_id
    -- Left Join to determine if the admission included an ICU stay
    LEFT JOIN icu_admissions AS icu ON adm.hadm_id = icu.hadm_id
),
-- Step 6: Create categorical variables for final grouping
categorized_data AS (
    SELECT
        *,
        CASE
            WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
            WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
            WHEN los_days >= 8 THEN '>=8 days'
            ELSE NULL
        END AS los_category,
        CASE
            WHEN charlson_comorbidity_index <= 3 THEN '<=3'
            WHEN charlson_comorbidity_index BETWEEN 4 AND 5 THEN '4-5'
            WHEN charlson_comorbidity_index > 5 THEN '>5'
            ELSE NULL
        END AS charlson_category
    FROM
        analysis_base
)
-- Step 7: Final aggregation and reporting of results
SELECT
    icu_status,
    los_category,
    charlson_category,
    COUNT(*) AS N,
    ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS in_hospital_mortality_percent,
    -- Calculate median time to death only for patients who died
    APPROX_QUANTILES(
        IF(hospital_expire_flag = 1, time_to_death_days, NULL),
        100
    )[OFFSET(50)] AS median_time_to_death_days
FROM
    categorized_data
WHERE
    los_category IS NOT NULL AND charlson_category IS NOT NULL
GROUP BY
    icu_status,
    los_category,
    charlson_category
ORDER BY
    icu_status DESC,
    -- Custom ordering for categories to ensure logical presentation
    CASE los_category
        WHEN '1-3 days' THEN 1
        WHEN '4-7 days' THEN 2
        WHEN '>=8 days' THEN 3
    END,
    CASE charlson_category
        WHEN '<=3' THEN 1
        WHEN '4-5' THEN 2
        WHEN '>5' THEN 3
    END;