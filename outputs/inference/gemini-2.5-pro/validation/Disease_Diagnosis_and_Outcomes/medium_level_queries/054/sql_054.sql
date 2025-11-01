WITH
charlson_codes AS (
    -- This CTE maps ICD codes to Charlson comorbidities and weights.
    -- This is a representative subset based on the Quan et al. adaptation.
    -- ICD-9
    SELECT 'MI' as comorbidity, '9' as icd_version, '410' as icd_code, 1 as weight UNION ALL
    SELECT 'MI', '9', '412', 1 UNION ALL
    SELECT 'CHF', '9', '428', 1 UNION ALL
    SELECT 'PVD', '9', '4439', 1 UNION ALL
    SELECT 'CEVD', '9', '430', 1 UNION ALL
    SELECT 'Dementia', '9', '290', 1 UNION ALL
    SELECT 'Pulmonary', '9', '490', 1 UNION ALL
    SELECT 'Connective', '9', '7100', 1 UNION ALL
    SELECT 'Ulcer', '9', '531', 1 UNION ALL
    SELECT 'LiverMild', '9', '5712', 1 UNION ALL
    SELECT 'Diabetes', '9', '2500', 1 UNION ALL
    SELECT 'DiabetesComp', '9', '2504', 2 UNION ALL
    SELECT 'Paraplegia', '9', '3441', 2 UNION ALL
    SELECT 'Renal', '9', '585', 2 UNION ALL
    SELECT 'Cancer', '9', '140', 2 UNION ALL
    SELECT 'LiverSevere', '9', '5722', 3 UNION ALL
    SELECT 'CancerMets', '9', '196', 6 UNION ALL
    SELECT 'Aids', '9', '042', 6 UNION ALL
    -- ICD-10
    SELECT 'MI', '10', 'I21', 1 UNION ALL
    SELECT 'MI', '10', 'I22', 1 UNION ALL
    SELECT 'CHF', '10', 'I50', 1 UNION ALL
    SELECT 'PVD', '10', 'I70', 1 UNION ALL
    SELECT 'CEVD', '10', 'I60', 1 UNION ALL
    SELECT 'Dementia', '10', 'F00', 1 UNION ALL
    SELECT 'Pulmonary', '10', 'J40', 1 UNION ALL
    SELECT 'Connective', '10', 'M30', 1 UNION ALL
    SELECT 'Ulcer', '10', 'K25', 1 UNION ALL
    SELECT 'LiverMild', '10', 'K700', 1 UNION ALL
    SELECT 'Diabetes', '10', 'E10', 1 UNION ALL
    SELECT 'DiabetesComp', '10', 'E102', 2 UNION ALL
    SELECT 'Paraplegia', '10', 'G81', 2 UNION ALL
    SELECT 'Renal', '10', 'N18', 2 UNION ALL
    SELECT 'Cancer', '10', 'C00', 2 UNION ALL
    SELECT 'LiverSevere', '10', 'K720', 3 UNION ALL
    SELECT 'CancerMets', '10', 'C77', 6 UNION ALL
    SELECT 'Aids', '10', 'B20', 6
),
charlson_scores AS (
    -- Calculate Charlson score for each patient based on their entire diagnosis history.
    SELECT subject_id, SUM(weight) AS charlson_score
    FROM (
        SELECT dx.subject_id, cc.comorbidity, MAX(cc.weight) AS weight
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        JOIN charlson_codes AS cc
            ON dx.icd_version = CAST(cc.icd_version AS INT64)
            AND STARTS_WITH(dx.icd_code, cc.icd_code)
        GROUP BY dx.subject_id, cc.comorbidity
    )
    GROUP BY subject_id
),
main_cohort_hadm_ids AS (
    -- Define the primary cohort: 44-year-old males with postoperative complications.
    SELECT DISTINCT cb.hadm_id, cb.subject_id
    FROM (
        SELECT p.subject_id, a.hadm_id, (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) AS age_at_admission
        FROM `physionet-data.mimiciv_3_1_hosp.patients` p
        JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
        WHERE p.gender = 'M'
    ) cb
    -- Must have a surgical service during the admission
    JOIN (SELECT DISTINCT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.services` WHERE curr_service LIKE '%SURG%') surg ON cb.hadm_id = surg.hadm_id
    -- Must have a postoperative complication diagnosis
    JOIN (
        SELECT DISTINCT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` WHERE
        (icd_version = 9 AND SUBSTR(icd_code, 1, 3) BETWEEN '996' AND '999') OR
        (icd_version = 10 AND (
            SUBSTR(icd_code, 1, 3) BETWEEN 'T80' AND 'T88' OR
            SUBSTR(icd_code, 1, 3) IN ('Y83', 'Y84') OR
            SUBSTR(icd_code, 1, 3) = 'K91'))
    ) comp ON cb.hadm_id = comp.hadm_id
    WHERE cb.age_at_admission = 44
),
interventions AS (
    -- Identify ICU interventions and aggregate them to the hospital admission level.
    SELECT
        icu.hadm_id,
        MAX(CASE WHEN mv.stay_id IS NOT NULL THEN 1 ELSE 0 END) AS had_mech_vent,
        MAX(CASE WHEN vs.stay_id IS NOT NULL THEN 1 ELSE 0 END) AS had_vasopressor,
        MAX(CASE WHEN rt.stay_id IS NOT NULL THEN 1 ELSE 0 END) AS had_rrt
    FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
    LEFT JOIN (SELECT DISTINCT stay_id FROM `physionet-data.mimiciv_3_1_icu.procedureevents` WHERE itemid IN (225792, 225468)) mv ON icu.stay_id = mv.stay_id
    LEFT JOIN (SELECT DISTINCT stay_id FROM `physionet-data.mimiciv_3_1_icu.inputevents` WHERE itemid IN (221906, 221289, 221749, 222315, 221662)) vs ON icu.stay_id = vs.stay_id
    LEFT JOIN (
        SELECT DISTINCT stay_id FROM `physionet-data.mimiciv_3_1_icu.procedureevents` WHERE itemid IN (225441, 225802, 225803)
        UNION DISTINCT
        SELECT DISTINCT stay_id FROM `physionet-data.mimiciv_3_1_icu.inputevents` WHERE ordercategoryname IN ('Dialysis', 'Continuous Renal Replacement Therapy')
    ) rt ON icu.stay_id = rt.stay_id
    GROUP BY icu.hadm_id
),
final_cohort AS (
    -- Assemble the final dataset with all required flags and measures.
    SELECT
        a.hadm_id,
        a.hospital_expire_flag,
        CASE WHEN icu.stay_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS icu_group,
        DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
        COALESCE(cs.charlson_score, 0) AS charlson_score,
        COALESCE(inter.had_mech_vent, 0) AS had_mech_vent,
        COALESCE(inter.had_vasopressor, 0) AS had_vasopressor,
        COALESCE(inter.had_rrt, 0) AS had_rrt
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN main_cohort_hadm_ids mc ON a.hadm_id = mc.hadm_id
    LEFT JOIN (SELECT hadm_id, MIN(stay_id) as stay_id FROM `physionet-data.mimiciv_3_1_icu.icustays` GROUP BY hadm_id) icu ON a.hadm_id = icu.hadm_id
    LEFT JOIN charlson_scores cs ON mc.subject_id = cs.subject_id
    LEFT JOIN interventions inter ON a.hadm_id = inter.hadm_id
),
binned_cohort AS (
    -- Bin LOS and Charlson score into the specified groups.
    SELECT
        *,
        CASE
            WHEN los_days <= 3 THEN '1. <=3 days'
            WHEN los_days <= 6 THEN '2. 4-6 days'
            WHEN los_days <= 10 THEN '3. 7-10 days'
            ELSE '4. >10 days'
        END AS los_group,
        CASE
            WHEN charlson_score <= 3 THEN '1. <=3'
            WHEN charlson_score <= 5 THEN '2. 4-5'
            ELSE '3. >5'
        END AS charlson_group
    FROM final_cohort
),
grouped_stats AS (
    -- Calculate statistics for each stratum.
    SELECT
        icu_group,
        los_group,
        charlson_group,
        COUNT(hadm_id) AS num_admissions,
        AVG(hospital_expire_flag) * 100 AS mortality_pct,
        AVG(had_mech_vent) * 100 AS mech_vent_pct,
        AVG(had_vasopressor) * 100 AS vasopressor_pct,
        AVG(had_rrt) * 100 AS rrt_pct
    FROM binned_cohort
    GROUP BY icu_group, los_group, charlson_group
)
-- Final report generation with mortality differences.
SELECT
    icu_group,
    charlson_group,
    los_group,
    num_admissions,
    ROUND(mortality_pct, 2) AS mortality_pct,
    ROUND(mortality_pct - FIRST_VALUE(mortality_pct) OVER (PARTITION BY icu_group, charlson_group ORDER BY los_group), 2) AS abs_diff_mortality_vs_le3d,
    ROUND(
        (mortality_pct - FIRST_VALUE(mortality_pct) OVER (PARTITION BY icu_group, charlson_group ORDER BY los_group))
        / NULLIF(FIRST_VALUE(mortality_pct) OVER (PARTITION BY icu_group, charlson_group ORDER BY los_group), 0)
    , 2) AS rel_diff_mortality_vs_le3d,
    ROUND(mech_vent_pct, 2) AS mech_vent_pct,
    ROUND(vasopressor_pct, 2) AS vasopressor_pct,
    ROUND(rrt_pct, 2) AS rrt_pct
FROM grouped_stats
ORDER BY icu_group, charlson_group, los_group;