WITH
-- Step 1: Identify admissions for ischemic or hemorrhagic stroke
icd_codes AS (
    SELECT
        hadm_id,
        icd_version,
        icd_code,
        CASE
            WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('430', '431', '432'))
              OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('I60', 'I61', 'I62')) THEN 'Hemorrhagic'
            WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('433', '434'))
              OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('I63', 'I65', 'I66')) THEN 'Ischemic'
            ELSE NULL
        END AS stroke_type
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (icd_version = 9 AND SUBSTR(icd_code, 1, 3) BETWEEN '430' AND '434')
     OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('I60', 'I61', 'I62', 'I63', 'I65', 'I66'))
),

-- Prioritize hemorrhagic stroke if codes for both types are present in one admission
stroke_admissions AS (
    SELECT
        hadm_id,
        stroke_type
    FROM (
        SELECT
            hadm_id,
            stroke_type,
            ROW_NUMBER() OVER(PARTITION BY hadm_id ORDER BY CASE WHEN stroke_type = 'Hemorrhagic' THEN 1 ELSE 2 END) as rn
        FROM icd_codes
        WHERE stroke_type IS NOT NULL
    )
    WHERE rn = 1
),

-- Step 2: Define the base patient cohort (men, 44-54 years old, with stroke)
base_cohort AS (
    SELECT
        p.subject_id,
        adm.hadm_id,
        sa.stroke_type,
        adm.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON p.subject_id = adm.subject_id
    INNER JOIN stroke_admissions AS sa
        ON adm.hadm_id = sa.hadm_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 44 AND 54
),

-- Step 3: Calculate Charlson Comorbidity Index for each admission
charlson AS (
    WITH comorbid_conditions AS (
        SELECT
            hadm_id,
            MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('410', '412')) OR (icd_version = 10 AND (SUBSTR(icd_code, 1, 3) IN ('I21', 'I22') OR SUBSTR(icd_code, 1, 4) = 'I252')) THEN 1 ELSE 0 END) AS mi,
            MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '428') OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'I50') THEN 1 ELSE 0 END) AS chf,
            MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('440', '441', '443')) OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('I70', 'I71', 'I73')) THEN 1 ELSE 0 END) AS pvd,
            -- cevd (Cerebrovascular disease) is excluded from the sum as it's the index condition for this cohort.
            MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) BETWEEN '430' AND '438') OR (icd_version = 10 AND (SUBSTR(icd_code, 1, 3) BETWEEN 'I60' AND 'I69' OR SUBSTR(icd_code, 1, 3) IN ('G45','G46'))) THEN 1 ELSE 0 END) AS cevd,
            MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '290') OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('F01','F02','F03','G30')) THEN 1 ELSE 0 END) AS dementia,
            MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) BETWEEN '490' AND '508') OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) BETWEEN 'J40' AND 'J47') THEN 1 ELSE 0 END) AS cpd,
            MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('710', '714', '725')) OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('M05', 'M06', 'M32', 'M34')) THEN 1 ELSE 0 END) AS rheumd,
            MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) BETWEEN '531' AND '534') OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('K25','K26','K27','K28')) THEN 1 ELSE 0 END) AS pud,
            MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '571') OR (icd_version = 10 AND SUBSTR(icd_code, 1, 4) IN ('B18', 'K73', 'K74')) THEN 1 ELSE 0 END) AS mld,
            MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 4) IN ('2500','2501','2502','2503')) OR (icd_version = 10 AND SUBSTR(icd_code, 1, 4) IN ('E109','E119','E129','E139','E149')) THEN 1 ELSE 0 END) AS diab,
            MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 4) IN ('2504','2505','2506','2507')) OR (icd_version = 10 AND SUBSTR(icd_code, 1, 4) IN ('E102','E115','E122','E132','E142')) THEN 2 ELSE 0 END) AS diab_comp,
            MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '342') OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'G81') THEN 2 ELSE 0 END) AS hemi,
            MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '585') OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'N18') THEN 2 ELSE 0 END) AS rend,
            MAX(CASE WHEN (icd_version = 9 AND (SUBSTR(icd_code, 1, 3) BETWEEN '140' AND '172' OR SUBSTR(icd_code, 1, 3) BETWEEN '174' AND '195' OR SUBSTR(icd_code, 1, 3) BETWEEN '200' AND '208')) OR (icd_version = 10 AND (SUBSTR(icd_code, 1, 3) BETWEEN 'C00' AND 'C76' OR SUBSTR(icd_code, 1, 3) BETWEEN 'C81' AND 'C96')) THEN 2 ELSE 0 END) AS mal,
            MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 4) IN ('5722','5723','5724')) OR (icd_version = 10 AND SUBSTR(icd_code, 1, 4) IN ('K721','K729')) THEN 3 ELSE 0 END) AS sld,
            MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('196','197','198')) OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('C77','C78','C79','C80')) THEN 6 ELSE 0 END) AS mets,
            MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '042') OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('B20','B21','B22','B24')) THEN 6 ELSE 0 END) AS aids
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        GROUP BY hadm_id
    )
    SELECT
        hadm_id,
        -- Refined: Removed 'cevd' from the sum as it's the index diagnosis
        mi + chf + pvd + dementia + cpd + rheumd + pud + mld + GREATEST(diab, diab_comp) + hemi + rend + mal + sld + mets + aids AS charlson_score
    FROM comorbid_conditions
),

-- Step 4: Identify ICU stays with specific interventions
mech_vent_stays AS (
    SELECT DISTINCT stay_id FROM `physionet-data.mimiciv_3_1_icu.procedureevents` WHERE itemid IN (225468, 224385, 224487)
),
vaso_stays AS (
    SELECT DISTINCT stay_id FROM `physionet-data.mimiciv_3_1_icu.inputevents` WHERE itemid IN (221906, 221289, 221749, 221662, 222315, 221653) AND statusdescription != 'Rewritten'
),
rrt_stays AS (
    SELECT DISTINCT stay_id FROM `physionet-data.mimiciv_3_1_icu.procedureevents` WHERE itemid IN (225802, 225803, 225805, 224144, 225441)
),

-- Step 5: Assemble the final cohort with all flags and grouping variables
final_cohort AS (
    SELECT
        bc.stroke_type,
        icu.los,
        CASE WHEN icu.los <= 5 THEN '≤5 days' ELSE '>5 days' END AS los_group,
        CASE
            WHEN COALESCE(cs.charlson_score, 0) = 0 THEN 'low'
            WHEN COALESCE(cs.charlson_score, 0) BETWEEN 1 AND 2 THEN 'med'
            ELSE 'high'
        END AS comorbidity_level,
        bc.hospital_expire_flag,
        CASE WHEN mv.stay_id IS NOT NULL THEN 1 ELSE 0 END AS has_mech_vent,
        CASE WHEN vs.stay_id IS NOT NULL THEN 1 ELSE 0 END AS has_vasopressors,
        CASE WHEN rs.stay_id IS NOT NULL THEN 1 ELSE 0 END AS has_rrt
    FROM base_cohort AS bc
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
        ON bc.hadm_id = icu.hadm_id
    LEFT JOIN charlson AS cs
        ON bc.hadm_id = cs.hadm_id
    LEFT JOIN mech_vent_stays AS mv
        ON icu.stay_id = mv.stay_id
    LEFT JOIN vaso_stays AS vs
        ON icu.stay_id = vs.stay_id
    LEFT JOIN rrt_stays AS rs
        ON icu.stay_id = rs.stay_id
)

-- Step 6: Aggregate results and calculate final metrics
SELECT
    stroke_type,
    los_group,
    comorbidity_level,
    COUNT(*) AS total_icu_stays,
    ROUND(AVG(hospital_expire_flag) * 100, 1) AS mortality_pct,
    APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_icu_los,
    ROUND(AVG(has_mech_vent) * 100, 1) AS mech_vent_pct,
    ROUND(AVG(has_vasopressors) * 100, 1) AS vasopressors_pct,
    ROUND(AVG(has_rrt) * 100, 1) AS rrt_pct
FROM final_cohort
GROUP BY
    stroke_type,
    los_group,
    comorbidity_level
ORDER BY
    stroke_type,
    CASE los_group
        WHEN '≤5 days' THEN 1
        WHEN '>5 days' THEN 2
    END,
    CASE comorbidity_level
        WHEN 'low' THEN 1
        WHEN 'med' THEN 2
        WHEN 'high' THEN 3
    END;