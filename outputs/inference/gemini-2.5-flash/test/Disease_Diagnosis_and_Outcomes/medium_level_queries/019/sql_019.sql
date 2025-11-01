WITH TargetAdmissions AS (
    -- Step 1: Identify the target patient population
    -- Males aged 53-63 with a diagnosis of Heart Failure (HF)
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.discharge_location,
        ad.hospital_expire_flag,
        -- Calculate Length of Stay in full days. LOS of 0 or less will be effectively excluded from LOS groups 1-3, 4-7, >=8.
        DATETIME_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pa
        ON ad.subject_id = pa.subject_id
    WHERE
        pa.gender = 'M'
        AND pa.anchor_age BETWEEN 53 AND 63
        -- Check for Heart Failure diagnosis using ICD codes
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag_hf
            WHERE
                diag_hf.subject_id = ad.subject_id
                AND diag_hf.hadm_id = ad.hadm_id
                AND (
                    (diag_hf.icd_version = 9 AND STARTS_WITH(diag_hf.icd_code, '428')) OR
                    (diag_hf.icd_version = 10 AND STARTS_WITH(diag_hf.icd_code, 'I50'))
                )
        )
),
CharlsonComorbidityFlags AS (
    -- Step 2: For each admission in TargetAdmissions, identify Charlson comorbidities based on ICD codes
    -- This CTE flags the presence of each comorbidity per admission.
    SELECT
        ta.subject_id,
        ta.hadm_id,
        -- Myocardial Infarction - Score 1
        MAX(CASE WHEN (diag.icd_version = 9 AND (STARTS_WITH(diag.icd_code, '410') OR STARTS_WITH(diag.icd_code, '412'))) OR (diag.icd_version = 10 AND (STARTS_WITH(diag.icd_code, 'I21') OR STARTS_WITH(diag.icd_code, 'I22') OR diag.icd_code = 'I252')) THEN 1 ELSE 0 END) AS mi,
        -- Congestive Heart Failure (already used as exclusion criteria, but included for completeness in score) - Score 1
        MAX(CASE WHEN (diag.icd_version = 9 AND STARTS_WITH(diag.icd_code, '428')) OR (diag.icd_version = 10 AND STARTS_WITH(diag.icd_code, 'I50')) THEN 1 ELSE 0 END) AS chf,
        -- Peripheral Vascular Disease - Score 1
        MAX(CASE WHEN (diag.icd_version = 9 AND (STARTS_WITH(diag.icd_code, '4402') OR STARTS_WITH(diag.icd_code, '441') OR STARTS_WITH(diag.icd_code, '443') OR STARTS_WITH(diag.icd_code, '4471') OR STARTS_WITH(diag.icd_code, '7854') OR STARTS_WITH(diag.icd_code, '0930') OR STARTS_WITH(diag.icd_code, '4373'))) OR (diag.icd_version = 10 AND (STARTS_WITH(diag.icd_code, 'I70') OR STARTS_WITH(diag.icd_code, 'I71') OR STARTS_WITH(diag.icd_code, 'I738') OR STARTS_WITH(diag.icd_code, 'I739') OR STARTS_WITH(diag.icd_code, 'I771') OR STARTS_WITH(diag.icd_code, 'I790') OR STARTS_WITH(diag.icd_code, 'I792') OR STARTS_WITH(diag.icd_code, 'K551') OR STARTS_WITH(diag.icd_code, 'K552') OR STARTS_WITH(diag.icd_code, 'Z958') OR STARTS_WITH(diag.icd_code, 'Z959'))) THEN 1 ELSE 0 END) AS pvd,
        -- Cerebrovascular Disease - Score 1
        MAX(CASE WHEN (diag.icd_version = 9 AND (diag.icd_code = '36234' OR SUBSTR(diag.icd_code,1,3) BETWEEN '430' AND '438' )) OR (diag.icd_version = 10 AND (STARTS_WITH(diag.icd_code, 'G45') OR STARTS_WITH(diag.icd_code, 'G46') OR SUBSTR(diag.icd_code,1,3) BETWEEN 'I60' AND 'I69' )) THEN 1 ELSE 0 END) AS cvd,
        -- Dementia - Score 1
        MAX(CASE WHEN (diag.icd_version = 9 AND (STARTS_WITH(diag.icd_code, '290') OR diag.icd_code = '2941' OR diag.icd_code = '3310')) OR (diag.icd_version = 10 AND (SUBSTR(diag.icd_code,1,3) BETWEEN 'F00' AND 'F03' OR STARTS_WITH(diag.icd_code, 'G30') OR STARTS_WITH(diag.icd_code, 'G311'))) THEN 1 ELSE 0 END) AS dementia,
        -- Chronic Pulmonary Disease - Score 1
        MAX(CASE WHEN (diag.icd_version = 9 AND (SUBSTR(diag.icd_code,1,3) BETWEEN '490' AND '496' )) OR (diag.icd_version = 10 AND (SUBSTR(diag.icd_code,1,3) BETWEEN 'J40' AND 'J47' )) THEN 1 ELSE 0 END) AS copd,
        -- Connective Tissue Disease/Rheumatic Disease - Score 1
        MAX(CASE WHEN (diag.icd_version = 9 AND (SUBSTR(diag.icd_code,1,4) BETWEEN '7100' AND '7104' OR SUBSTR(diag.icd_code,1,4) BETWEEN '7140' AND '7142' OR diag.icd_code = '7148' OR diag.icd_code = '7200' OR diag.icd_code = '7285')) OR (diag.icd_version = 10 AND (SUBSTR(diag.icd_code,1,3) BETWEEN 'M05' AND 'M09' OR SUBSTR(diag.icd_code,1,3) BETWEEN 'M30' AND 'M36' OR STARTS_WITH(diag.icd_code, 'M45') OR STARTS_WITH(diag.icd_code, 'M46'))) THEN 1 ELSE 0 END) AS ctd,
        -- Peptic Ulcer Disease - Score 1
        MAX(CASE WHEN (diag.icd_version = 9 AND (SUBSTR(diag.icd_code,1,3) BETWEEN '531' AND '534' )) OR (diag.icd_version = 10 AND (SUBSTR(diag.icd_code,1,3) BETWEEN 'K25' AND 'K28' )) THEN 1 ELSE 0 END) AS pud,
        -- Diabetes without Complications - Score 1
        MAX(CASE WHEN (diag.icd_version = 9 AND (SUBSTR(diag.icd_code,1,4) BETWEEN '2500' AND '2503' OR diag.icd_code = '2507')) OR (diag.icd_version = 10 AND (SUBSTR(diag.icd_code,1,4) BETWEEN 'E100' AND 'E106' OR SUBSTR(diag.icd_code,1,4) BETWEEN 'E108' AND 'E109' OR SUBSTR(diag.icd_code,1,4) BETWEEN 'E110' AND 'E116' OR SUBSTR(diag.icd_code,1,4) BETWEEN 'E118' AND 'E119' OR SUBSTR(diag.icd_code,1,4) BETWEEN 'E130' AND 'E136' OR SUBSTR(diag.icd_code,1,4) BETWEEN 'E138' AND 'E139'))) THEN 1 ELSE 0 END) AS dm_no_comp,
        -- Diabetes with Complications - Score 2
        MAX(CASE WHEN (diag.icd_version = 9 AND (SUBSTR(diag.icd_code,1,4) BETWEEN '2504' AND '2506' OR SUBSTR(diag.icd_code,1,4) BETWEEN '2508' AND '2509')) OR (diag.icd_version = 10 AND (diag.icd_code = 'E107' OR diag.icd_code = 'E117' OR diag.icd_code = 'E137'))) THEN 1 ELSE 0 END) AS dm_comp,
        -- Hemiplegia or Paraplegia - Score 2
        MAX(CASE WHEN (diag.icd_version = 9 AND (diag.icd_code = '3341' OR STARTS_WITH(diag.icd_code, '342') OR STARTS_WITH(diag.icd_code, '343') OR STARTS_WITH(diag.icd_code, '344'))) OR (diag.icd_version = 10 AND (STARTS_WITH(diag.icd_code, 'G041') OR STARTS_WITH(diag.icd_code, 'G114') OR SUBSTR(diag.icd_code,1,3) BETWEEN 'G80' AND 'G83' ))) THEN 1 ELSE 0 END) AS hemiplegia,
        -- Renal Disease - Score 2
        MAX(CASE WHEN (diag.icd_version = 9 AND (SUBSTR(diag.icd_code, 1, 4) IN ('4030', '4031', '4039') AND SUBSTR(diag.icd_code, 5, 1) = '1') OR (SUBSTR(diag.icd_code, 1, 4) IN ('4040', '4041', '4049') AND SUBSTR(diag.icd_code, 5, 1) IN ('2', '3')) OR STARTS_WITH(diag.icd_code, '585') OR STARTS_WITH(diag.icd_code, '586') OR STARTS_WITH(diag.icd_code, '5880')) OR (diag.icd_version = 10 AND (STARTS_WITH(diag.icd_code, 'I120') OR STARTS_WITH(diag.icd_code, 'I131') OR STARTS_WITH(diag.icd_code, 'I132') OR SUBSTR(diag.icd_code,1,3) BETWEEN 'N03' AND 'N07' OR STARTS_WITH(diag.icd_code, 'N18') OR STARTS_WITH(diag.icd_code, 'N19') OR STARTS_WITH(diag.icd_code, 'Z940') OR STARTS_WITH(diag.icd_code, 'Z992'))) THEN 1 ELSE 0 END) AS renal,
        -- Any Malignancy (excl. metastatic and skin cancer) - Score 2
        MAX(CASE WHEN (diag.icd_version = 9 AND (CAST(REGEXP_EXTRACT(diag.icd_code, r'^(\d+)') AS BIGNUMERIC) BETWEEN 140 AND 208) AND NOT (STARTS_WITH(diag.icd_code, '173') OR STARTS_WITH(diag.icd_code, '196') OR STARTS_WITH(diag.icd_code, '197') OR STARTS_WITH(diag.icd_code, '198') OR STARTS_WITH(diag.icd_code, '199'))) OR (diag.icd_version = 10 AND ( (SUBSTR(diag.icd_code, 1, 1) = 'C' AND NOT (STARTS_WITH(diag.icd_code, 'C44') OR SUBSTR(diag.icd_code,1,3) BETWEEN 'C77' AND 'C80')) OR STARTS_WITH(diag.icd_code, 'D0') )) THEN 1 ELSE 0 END) AS cancer,
        -- Moderate to Severe Liver Disease - Score 3
        MAX(CASE WHEN (diag.icd_version = 9 AND (STARTS_WITH(diag.icd_code, '4560') OR STARTS_WITH(diag.icd_code, '4561') OR STARTS_WITH(diag.icd_code, '4562') OR STARTS_WITH(diag.icd_code, '5722') OR STARTS_WITH(diag.icd_code, '5723') OR STARTS_WITH(diag.icd_code, '5724') OR STARTS_WITH(diag.icd_code, '5728') OR STARTS_WITH(diag.icd_code, '5735') OR STARTS_WITH(diag.icd_code, '5738') OR STARTS_WITH(diag.icd_code, '5739'))) OR (diag.icd_version = 10 AND (STARTS_WITH(diag.icd_code, 'I850') OR STARTS_WITH(diag.icd_code, 'I859') OR STARTS_WITH(diag.icd_code, 'I864') OR STARTS_WITH(diag.icd_code, 'I982') OR STARTS_WITH(diag.icd_code, 'K704') OR STARTS_WITH(diag.icd_code, 'K711') OR STARTS_WITH(diag.icd_code, 'K720') OR STARTS_WITH(diag.icd_code, 'K721') OR STARTS_WITH(diag.icd_code, 'K729') OR STARTS_WITH(diag.icd_code, 'K765') OR STARTS_WITH(diag.icd_code, 'K766') OR STARTS_WITH(diag.icd_code, 'K767') OR STARTS_WITH(diag.icd_code, 'K768') OR STARTS_WITH(diag.icd_code, 'K769'))) THEN 1 ELSE 0 END) AS sev_liver,
        -- Metastatic Solid Tumor - Score 6
        MAX(CASE WHEN (diag.icd_version = 9 AND (STARTS_WITH(diag.icd_code, '196') OR STARTS_WITH(diag.icd_code, '197') OR STARTS_WITH(diag.icd_code, '198') OR STARTS_WITH(diag.icd_code, '199'))) OR (diag.icd_version = 10 AND (SUBSTR(diag.icd_code,1,3) BETWEEN 'C77' AND 'C80' ))) THEN 1 ELSE 0 END) AS met_solid_tumor,
        -- HIV/AIDS - Score 6
        MAX(CASE WHEN (diag.icd_version = 9 AND (STARTS_WITH(diag.icd_code, '042') OR STARTS_WITH(diag.icd_code, '043') OR STARTS_WITH(diag.icd_code, '044'))) OR (diag.icd_version = 10 AND (SUBSTR(diag.icd_code,1,3) BETWEEN 'B20' AND 'B24' ))) THEN 1 ELSE 0 END) AS hiv_aids,
        -- Mild Liver Disease (temporary flag for score calculation, handled with sev_liver)
        MAX(CASE WHEN (diag.icd_version = 9 AND (STARTS_WITH(diag.icd_code, '5710') OR STARTS_WITH(diag.icd_code, '5711') OR STARTS_WITH(diag.icd_code, '5712') OR STARTS_WITH(diag.icd_code, '5713') OR STARTS_WITH(diag.icd_code, '5714') OR STARTS_WITH(diag.icd_code, '5715') OR STARTS_WITH(diag.icd_code, '5716') OR STARTS_WITH(diag.icd_code, '5733') OR STARTS_WITH(diag.icd_code, '5734') OR STARTS_WITH(diag.icd_code, '5738') OR STARTS_WITH(diag.icd_code, '5739') OR STARTS_WITH(diag.icd_code, '570') OR STARTS_WITH(diag.icd_code, '0707'))) OR (diag.icd_version = 10 AND (SUBSTR(diag.icd_code,1,4) IN ('K700','K701','K702','K703','K709') OR SUBSTR(diag.icd_code,1,4) IN ('K713','K718','K719') OR STARTS_WITH(diag.icd_code, 'K73') OR STARTS_WITH(diag.icd_code, 'K74') OR STARTS_WITH(diag.icd_code, 'K760') OR SUBSTR(diag.icd_code,1,4) BETWEEN 'K762' AND 'K764' OR SUBSTR(diag.icd_code,1,4) BETWEEN 'K768' AND 'K769' OR STARTS_WITH(diag.icd_code, 'B18') OR STARTS_WITH(diag.icd_code, 'Z944'))) THEN 1 ELSE 0 END) AS mild_liver_temp
    FROM
        TargetAdmissions AS ta
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
        ON ta.subject_id = diag.subject_id AND ta.hadm_id = diag.hadm_id
    GROUP BY
        ta.subject_id, ta.hadm_id
),
AdmissionsWithCharlson AS (
    -- Step 3: Calculate the total Charlson score for each admission
    -- This combines the flags into a final score, applying priority rules where needed.
    SELECT
        ta.subject_id,
        ta.hadm_id,
        ta.los_days,
        ta.hospital_expire_flag,
        ta.discharge_location,
        (
            cc.mi * 1 + cc.chf * 1 + cc.pvd * 1 + cc.cvd * 1 + cc.dementia * 1 + cc.copd * 1 + cc.ctd * 1 + cc.pud * 1 +
            -- Diabetes: DM with complications (2) or without (1)
            (CASE WHEN cc.dm_comp = 1 THEN 2 ELSE cc.dm_no_comp * 1 END) +
            cc.hemiplegia * 2 + cc.renal * 2 +
            -- Cancer: Metastatic cancer (6) takes precedence over Any Malignancy (2)
            (CASE WHEN cc.met_solid_tumor = 1 THEN 6 ELSE cc.cancer * 2 END) +
            -- Liver Disease: Severe liver disease (3) takes precedence over Mild liver disease (1)
            (CASE WHEN cc.sev_liver = 1 THEN 3 ELSE cc.mild_liver_temp * 1 END) +
            cc.hiv_aids * 6
        ) AS charlson_score
    FROM
        TargetAdmissions AS ta
    INNER JOIN
        CharlsonComorbidityFlags AS cc
        ON ta.subject_id = cc.subject_id AND ta.hadm_id = cc.hadm_id
    WHERE
        ta.los_days >= 1 -- Only consider admissions with LOS of at least 1 day for reporting and grouping
),
LOSCharlsonGrouped AS (
    -- Step 4: Group LOS and Charlson scores into specified categories
    SELECT
        awc.subject_id,
        awc.hadm_id,
        awc.los_days,
        awc.hospital_expire_flag,
        awc.discharge_location,
        CASE
            WHEN awc.los_days BETWEEN 1 AND 3 THEN '1-3 days'
            WHEN awc.los_days BETWEEN 4 AND 7 THEN '4-7 days'
            WHEN awc.los_days >= 8 THEN '>=8 days'
            ELSE 'Unknown LOS Group' -- Should not happen with WHERE clause, but good for robustness
        END AS los_group,
        awc.charlson_score,
        CASE
            WHEN awc.charlson_score <= 3 THEN '<=3'
            WHEN awc.charlson_score BETWEEN 4 AND 5 THEN '4-5'
            WHEN awc.charlson_score > 5 THEN '>5'
            ELSE 'Unknown Charlson Group' -- If charlson_score is NULL or outside expected range
        END AS charlson_group
    FROM
        AdmissionsWithCharlson AS awc
    WHERE
        awc.charlson_score IS NOT NULL -- Exclude admissions where Charlson score could not be calculated (should always be non-NULL from custom calc)
),
CohortOverallStats AS (
    -- Step 5: Calculate overall average LOS for the entire target cohort
    SELECT
        AVG(los_days) AS overall_avg_los
    FROM
        LOSCharlsonGrouped
    WHERE
        los_group != 'Unknown LOS Group'
        AND charlson_group != 'Unknown Charlson Group' -- Ensure only valid groups contribute to overall stats
),
FinalReport AS (
    -- Step 6: Aggregate mortality, average LOS, and discharge counts by LOS and Charlson groups
    SELECT
        lcg.los_group,
        lcg.charlson_group,
        COUNT(DISTINCT lcg.hadm_id) AS admissions_in_group,
        -- In-hospital mortality percentage
        ROUND(CAST(SUM(lcg.hospital_expire_flag) AS BIGNUMERIC) * 100.0 / COUNT(DISTINCT lcg.hadm_id), 2) AS in_hospital_mortality_percent,
        -- Average Length of Stay for the group
        ROUND(AVG(lcg.los_days), 2) AS average_los_days,
        -- Discharge destination counts for each group
        SUM(CASE WHEN lcg.discharge_location IN ('Home', 'Home Health Care') THEN 1 ELSE 0 END) AS home_group_count,
        SUM(CASE WHEN lcg.discharge_location = 'Rehabilitation' THEN 1 ELSE 0 END) AS rehab_group_count, -- Corrected 'Rehab' to 'Rehabilitation'
        SUM(CASE WHEN lcg.discharge_location = 'Skilled Nursing Facility' THEN 1 ELSE 0 END) AS snf_group_count,
        SUM(CASE WHEN lcg.discharge_location = 'Hospice' THEN 1 ELSE 0 END) AS hospice_group_count
    FROM
        LOSCharlsonGrouped AS lcg
    WHERE
        lcg.los_group != 'Unknown LOS Group' -- Ensure only specified LOS groups are reported
        AND lcg.charlson_group != 'Unknown Charlson Group' -- Ensure only specified Charlson groups are reported
    GROUP BY
        lcg.los_group,
        lcg.charlson_group
)
-- Step 7: Combine grouped data with overall cohort statistics and calculate final metrics
SELECT
    fr.los_group,
    fr.charlson_group,
    fr.admissions_in_group,
    fr.in_hospital_mortality_percent,
    fr.average_los_days,
    -- Absolute LOS difference
    ROUND(fr.average_los_days - cos.overall_avg_los, 2) AS absolute_los_difference,
    -- Relative LOS difference
    ROUND((fr.average_los_days - cos.overall_avg_los) * 100.0 / cos.overall_avg_los, 2) AS relative_los_difference_percent,
    -- Discharge percentages for the group
    ROUND(fr.home_group_count * 100.0 / fr.admissions_in_group, 2) AS discharge_home_percent,
    ROUND(fr.rehab_group_count * 100.0 / fr.admissions_in_group, 2) AS discharge_rehab_percent,
    ROUND(fr.snf_group_count * 100.0 / fr.admissions_in_group, 2) AS discharge_snf_percent,
    ROUND(fr.hospice_group_count * 100.0 / fr.admissions_in_group, 2) AS discharge_hospice_percent
FROM
    FinalReport AS fr
CROSS JOIN
    CohortOverallStats AS cos -- CROSS JOIN to include overall stats in every detailed row
ORDER BY
    -- Order by LOS groups for logical presentation
    CASE fr.los_group
        WHEN '1-3 days' THEN 1
        WHEN '4-7 days' THEN 2
        WHEN '>=8 days' THEN 3
        ELSE 99 -- Fallback for any unexpected groups
    END,
    -- Then order by Charlson groups
    CASE fr.charlson_group
        WHEN '<=3' THEN 1
        WHEN '4-5' THEN 2
        WHEN '>5' THEN 3
        ELSE 99 -- Fallback for any unexpected groups
    END;