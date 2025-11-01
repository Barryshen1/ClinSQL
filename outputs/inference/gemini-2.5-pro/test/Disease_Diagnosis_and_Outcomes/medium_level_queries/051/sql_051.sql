with a diagnosis indicating postoperative complications.
-- It then stratifies them by ICU status, LOS, and Charlson Comorbidity Index (CCI),
-- reporting mortality, median LOS, and prevalence of CKD and diabetes for each group.
-- The Charlson score is calculated manually from ICD codes as per the Quan et al. definition.

WITH
-- CTE to define Charlson comorbidity components based on ICD codes from the Quan et al. paper
Cci_Components AS (
    SELECT
        hadm_id,
        MAX(CASE -- Myocardial Infarction
            WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('410', '412') THEN 1
            WHEN icd_version = 10 AND (SUBSTR(icd_code, 1, 3) IN ('I21', 'I22') OR SUBSTR(icd_code, 1, 4) = 'I252') THEN 1
            ELSE 0 END) AS mi,
        MAX(CASE -- Congestive Heart Failure
            WHEN icd_version = 9 AND (SUBSTR(icd_code, 1, 5) IN ('39891', '40201', '40211', '40291', '40401', '40403', '40411', '40413', '40491', '40493') OR SUBSTR(icd_code, 1, 4) IN ('4254', '4255', '4257', '4258', '4259') OR SUBSTR(icd_code, 1, 3) = '428') THEN 1
            WHEN icd_version = 10 AND (icd_code IN ('I099', 'I110', 'I130', 'I132', 'I255', 'P290') OR SUBSTR(icd_code, 1, 3) IN ('I42', 'I43', 'I50')) THEN 1
            ELSE 0 END) AS chf,
        MAX(CASE -- Peripheral Vascular Disease
            WHEN icd_version = 9 AND (icd_code IN ('0930', '4373', '4471', '5571', '5579', 'V434') OR SUBSTR(icd_code, 1, 3) IN ('440', '441') OR SUBSTR(icd_code, 1, 4) IN ('4431', '4432', '4438', '4439')) THEN 1
            WHEN icd_version = 10 AND (icd_code IN ('I731', 'I738', 'I739', 'I771', 'I790', 'I792', 'K551', 'K558', 'K559', 'Z958', 'Z959') OR SUBSTR(icd_code, 1, 3) IN ('I70', 'I71')) THEN 1
            ELSE 0 END) AS pvd,
        MAX(CASE -- Cerebrovascular Disease
            WHEN icd_version = 9 AND (icd_code = '36234' OR SUBSTR(icd_code, 1, 3) BETWEEN '430' AND '438') THEN 1
            WHEN icd_version = 10 AND (SUBSTR(icd_code, 1, 3) IN ('G45', 'G46') OR SUBSTR(icd_code, 1, 3) BETWEEN 'I60' AND 'I69' OR SUBSTR(icd_code, 1, 4) = 'H340') THEN 1
            ELSE 0 END) AS cvd,
        MAX(CASE -- Dementia
            WHEN icd_version = 9 AND (SUBSTR(icd_code, 1, 3) = '290' OR SUBSTR(icd_code, 1, 4) = '2941' OR icd_code = '3312') THEN 1
            WHEN icd_version = 10 AND (icd_code = 'F051' OR SUBSTR(icd_code, 1, 3) IN ('F00', 'F01', 'F02', 'F03', 'G30') OR SUBSTR(icd_code, 1, 4) = 'G311') THEN 1
            ELSE 0 END) AS dementia,
        MAX(CASE -- Chronic Pulmonary Disease
            WHEN icd_version = 9 AND (SUBSTR(icd_code, 1, 3) BETWEEN '490' AND '496' OR SUBSTR(icd_code, 1, 3) BETWEEN '500' AND '505' OR icd_code = '5064') THEN 1
            WHEN icd_version = 10 AND (icd_code IN ('J684', 'J961', 'J982', 'J983') OR SUBSTR(icd_code, 1, 3) BETWEEN 'J40' AND 'J47') THEN 1
            ELSE 0 END) AS cpd,
        MAX(CASE -- Rheumatic Disease
            WHEN icd_version = 9 AND (icd_code = '725' OR SUBSTR(icd_code, 1, 4) IN ('7100', '7101', '7102', '7103', '7104', '7140', '7141', '7142') OR SUBSTR(icd_code, 1, 5) = '71481') THEN 1
            WHEN icd_version = 10 AND (icd_code = 'M315' OR SUBSTR(icd_code, 1, 3) IN ('M05', 'M06') OR SUBSTR(icd_code, 1, 3) BETWEEN 'M32' AND 'M36') THEN 1
            ELSE 0 END) AS rheumatic,
        MAX(CASE -- Peptic Ulcer Disease
            WHEN icd_version = 9 AND (SUBSTR(icd_code, 1, 3) BETWEEN '531' AND '534') THEN 1
            WHEN icd_version = 10 AND (SUBSTR(icd_code, 1, 3) BETWEEN 'K25' AND 'K28') THEN 1
            ELSE 0 END) AS pud,
        MAX(CASE -- Mild Liver Disease
            WHEN icd_version = 9 AND (icd_code IN ('07022', '07023', '07032', '07033', '07044', '07054', '0706', '0709', '5733', '5734', '5738', '5739', 'V427') OR SUBSTR(icd_code, 1, 3) = '571') THEN 1
            WHEN icd_version = 10 AND (icd_code IN ('K700', 'K701', 'K702', 'K703', 'K709', 'K713', 'K714', 'K715', 'K717', 'K760', 'K762', 'K763', 'K764', 'K768', 'K769', 'Z944') OR SUBSTR(icd_code, 1, 3) IN ('B18', 'K73', 'K74')) THEN 1
            ELSE 0 END) AS mld,
        MAX(CASE -- Diabetes without complication
            WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 4) IN ('2500', '2501', '2502', '2503') THEN 1
            WHEN icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('E10', 'E11', 'E12', 'E13', 'E14') AND (LENGTH(icd_code) < 5 OR SUBSTR(icd_code, 5, 1) IN ('0', '1', '6', '8')) THEN 1
            ELSE 0 END) AS diab_uncomp,
        MAX(CASE -- Diabetes with complication
            WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 4) IN ('2504', '2505', '2506', '2507', '2508', '2509') THEN 1
            WHEN icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('E10', 'E11', 'E12', 'E13', 'E14') AND LENGTH(icd_code) >= 5 AND SUBSTR(icd_code, 5, 1) IN ('2', '3', '4', '5', '7', '9') THEN 1
            ELSE 0 END) AS diab_comp,
        MAX(CASE -- Hemiplegia or Paraplegia
            WHEN icd_version = 9 AND (icd_code = '3341' OR SUBSTR(icd_code, 1, 3) IN ('342', '343') OR SUBSTR(icd_code, 1, 4) IN ('3440', '3441', '3442', '3443', '3444', '3445', '3446', '3449')) THEN 1
            WHEN icd_version = 10 AND (icd_code IN ('G041', 'G114', 'G801', 'G802', 'G839') OR SUBSTR(icd_code, 1, 3) IN ('G81', 'G82') OR SUBSTR(icd_code, 1, 4) IN ('G830', 'G831', 'G832', 'G833', 'G834')) THEN 1
            ELSE 0 END) AS hemi,
        MAX(CASE -- Renal Disease (CKD)
            WHEN icd_version = 9 AND (icd_code IN ('V420', 'V451') OR SUBSTR(icd_code, 1, 3) IN ('582', '585', '586') OR SUBSTR(icd_code, 1, 3) = 'V56' OR SUBSTR(icd_code, 1, 4) IN ('40301', '40311', '40391', '40402', '40403', '40412', '40413', '40492', '40493') OR SUBSTR(icd_code, 1, 4) BETWEEN '5830' AND '5837' OR icd_code = '5880') THEN 1
            WHEN icd_version = 10 AND (icd_code IN ('I120', 'I131', 'N19', 'N250', 'Z992', 'Z490', 'Z491', 'Z492') OR SUBSTR(icd_code, 1, 3) = 'N18' OR SUBSTR(icd_code, 1, 4) IN ('N032', 'N033', 'N034', 'N035', 'N036', 'N037', 'N052', 'N053', 'N054', 'N055', 'N056', 'N057')) THEN 1
            ELSE 0 END) AS ckd,
        MAX(CASE -- Malignancy
            WHEN icd_version = 9 AND (SUBSTR(icd_code, 1, 3) BETWEEN '140' AND '172' OR SUBSTR(icd_code, 1, 3) BETWEEN '174' AND '195' OR SUBSTR(icd_code, 1, 3) BETWEEN '200' AND '208' OR icd_code = '2386') THEN 1
            WHEN icd_version = 10 AND (SUBSTR(icd_code, 1, 3) BETWEEN 'C00' AND 'C76' OR SUBSTR(icd_code, 1, 3) BETWEEN 'C81' AND 'C96') THEN 1
            ELSE 0 END) AS cancer,
        MAX(CASE -- Moderate or Severe Liver Disease
            WHEN icd_version = 9 AND (icd_code IN ('4560', '4561', '5722', '5723', '5724', '5728') OR SUBSTR(icd_code, 1, 4) = '4562') THEN 1
            WHEN icd_version = 10 AND (icd_code IN ('I850', 'I859', 'I864', 'I982', 'K704', 'K711', 'K721', 'K729', 'K765', 'K766', 'K767')) THEN 1
            ELSE 0 END) AS sld,
        MAX(CASE -- Metastatic Solid Tumor
            WHEN icd_version = 9 AND (SUBSTR(icd_code, 1, 3) BETWEEN '196' AND '199') THEN 1
            WHEN icd_version = 10 AND (SUBSTR(icd_code, 1, 3) BETWEEN 'C77' AND 'C80') THEN 1
            ELSE 0 END) AS mets,
        MAX(CASE -- AIDS/HIV
            WHEN icd_version = 9 AND (SUBSTR(icd_code, 1, 3) BETWEEN '042' AND '044') THEN 1
            WHEN icd_version = 10 AND (icd_code = 'B24' OR SUBSTR(icd_code, 1, 3) IN ('B20', 'B21', 'B22')) THEN 1
            ELSE 0 END) AS aids
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY hadm_id
),
-- CTE to calculate the final Charlson score from components, handling overlaps and weights
Cci_Scores AS (
    SELECT
        hadm_id,
        (
            mi * 1 + chf * 1 + pvd * 1 + cvd * 1 + dementia * 1 + cpd * 1 + rheumatic * 1 + pud * 1 +
            CASE WHEN sld = 1 THEN 3 WHEN mld = 1 THEN 1 ELSE 0 END +
            CASE WHEN diab_comp = 1 THEN 2 WHEN diab_uncomp = 1 THEN 1 ELSE 0 END +
            hemi * 2 +
            ckd * 2 +
            GREATEST(cancer * 2, mets * 6, aids * 6)
        ) AS charlson_score,
        GREATEST(diab_uncomp, diab_comp) AS has_diabetes,
        ckd AS has_ckd
    FROM Cci_Components
),
-- CTE for the base cohort of admissions meeting age, gender, and complication criteria
Base_Admissions AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.hospital_expire_flag,
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'M'
        AND ((EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) + pat.anchor_age) BETWEEN 51 AND 61
        AND adm.dischtime IS NOT NULL
        -- Filter for admissions with postoperative complications
        AND adm.hadm_id IN (
            SELECT DISTINCT hadm_id
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
            WHERE
                (icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('996', '997', '998'))
                OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) BETWEEN 'T80' AND 'T88')
        )
),
-- CTE to join all data and create stratification categories
Final_Data AS (
    SELECT
        ba.hospital_expire_flag,
        ba.los,
        cs.has_diabetes,
        cs.has_ckd,
        -- Stratification: ICU vs Non-ICU
        CASE WHEN icu.hadm_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS icu_category,
        -- Stratification: LOS category
        CASE
            WHEN ba.los BETWEEN 1 AND 2 THEN '1-2 days'
            WHEN ba.los BETWEEN 3 AND 5 THEN '3-5 days'
            WHEN ba.los BETWEEN 6 AND 9 THEN '6-9 days'
            WHEN ba.los >= 10 THEN '>=10 days'
            ELSE NULL
        END AS los_category,
        -- Stratification: Charlson score category
        CASE
            WHEN cs.charlson_score <= 1 THEN '0-1'
            WHEN cs.charlson_score = 2 THEN '2'
            WHEN cs.charlson_score >= 3 THEN '>=3'
            ELSE NULL
        END AS cci_category
    FROM Base_Admissions AS ba
    INNER JOIN Cci_Scores AS cs
        ON ba.hadm_id = cs.hadm_id
    LEFT JOIN (SELECT DISTINCT hadm_id FROM `physionet-data.mimiciv_3_1_icu.icustays`) AS icu
        ON ba.hadm_id = icu.hadm_id
)
-- Final aggregation and reporting
SELECT
    icu_category,
    los_category,
    cci_category,
    COUNT(*) AS number_of_admissions,
    ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_pct,
    APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los,
    ROUND(AVG(has_ckd) * 100, 2) AS ckd_prevalence_pct,
    ROUND(AVG(has_diabetes) * 100, 2) AS diabetes_prevalence_pct
FROM Final_Data
WHERE
    los_category IS NOT NULL
    AND cci_category IS NOT NULL
GROUP BY
    icu_category,
    los_category,
    cci_category
ORDER BY
    icu_category DESC,
    -- Custom sort for LOS category to ensure logical order
    CASE los_category
        WHEN '1-2 days' THEN 1
        WHEN '3-5 days' THEN 2
        WHEN '6-9 days' THEN 3
        WHEN '>=10 days' THEN 4
    END,
    -- Custom sort for CCI category
    CASE cci_category
        WHEN '0-1' THEN 1
        WHEN '2' THEN 2
        WHEN '>=3' THEN 3
    END;