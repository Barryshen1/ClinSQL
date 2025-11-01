WITH Cohort AS (
    SELECT DISTINCT
        ad.subject_id,
        ad.hadm_id,
        -- Calculate age at admission by adjusting anchor_age with anchor_year and admittime year
        (p.anchor_age + EXTRACT(YEAR FROM ad.admittime) - p.anchor_year) AS age_at_admission,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ad.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND (p.anchor_age + EXTRACT(YEAR FROM ad.admittime) - p.anchor_year) BETWEEN 44 AND 54
        -- Filter for Heart Failure diagnosis using ICD codes (ICD-9: 428%, ICD-10: I50%)
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            WHERE
                di.subject_id = ad.subject_id AND di.hadm_id = ad.hadm_id
                AND (
                    (di.icd_version = 9 AND di.icd_code LIKE '428%') OR
                    (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
                )
        )
),
-- CTE to identify the presence of each Charlson comorbidity for each admission
CharlsonComorbidities AS (
    SELECT
        di.hadm_id,
        -- Myocardial Infarction (1 point)
        MAX(CASE WHEN (di.icd_version = 9 AND (LEFT(di.icd_code,3) IN ('410', '412')))
                   OR (di.icd_version = 10 AND (LEFT(di.icd_code,3) IN ('I21', 'I22') OR di.icd_code = 'I252')) THEN 1 ELSE 0 END) AS mi,
        -- Congestive Heart Failure (1 point) - already filtered for cohort, but included for charlson score
        MAX(CASE WHEN (di.icd_version = 9 AND di.icd_code LIKE '428%')
                   OR (di.icd_version = 10 AND di.icd_code LIKE 'I50%') THEN 1 ELSE 0 END) AS chf,
        -- Peripheral Vascular Disease (1 point)
        MAX(CASE WHEN (di.icd_version = 9 AND (LEFT(di.icd_code,3) IN ('440', '441', '443') OR di.icd_code = '7854' OR di.icd_code = 'V434' OR di.icd_code = '4471'))
                   OR (di.icd_version = 10 AND (LEFT(di.icd_code,3) IN ('I70', 'I71', 'I73') OR LEFT(di.icd_code,4) IN ('I771', 'I790', 'I792') OR LEFT(di.icd_code,5) IN ('Z9581', 'Z9582') OR LEFT(di.icd_code,3) = 'K55')) THEN 1 ELSE 0 END) AS pvd,
        -- Cerebrovascular Disease (1 point)
        MAX(CASE WHEN (di.icd_version = 9 AND (LEFT(di.icd_code,3) BETWEEN '430' AND '438' AND di.icd_code != '4373'))
                   OR (di.icd_version = 10 AND (LEFT(di.icd_code,3) IN ('G45', 'G46') OR LEFT(di.icd_code,3) BETWEEN 'I60' AND 'I69')) THEN 1 ELSE 0 END) AS cvd,
        -- Dementia (1 point)
        MAX(CASE WHEN (di.icd_version = 9 AND (LEFT(di.icd_code,3) = '290' OR di.icd_code = '2941' OR LEFT(di.icd_code,3) = '331'))
                   OR (di.icd_version = 10 AND (LEFT(di.icd_code,3) BETWEEN 'F00' AND 'F03' OR LEFT(di.icd_code,3) = 'G30' OR di.icd_code = 'G311' OR di.icd_code = 'G3183')) THEN 1 ELSE 0 END) AS dementia,
        -- Chronic Pulmonary Disease (1 point)
        MAX(CASE WHEN (di.icd_version = 9 AND (LEFT(di.icd_code,3) BETWEEN '490' AND '505' OR di.icd_code = '5064'))
                   OR (di.icd_version = 10 AND (LEFT(di.icd_code,3) BETWEEN 'J41' AND 'J47' OR LEFT(di.icd_code,3) = 'J67')) THEN 1 ELSE 0 END) AS copd,
        -- Connective Tissue Disease/Rheumatic Disease (1 point)
        MAX(CASE WHEN (di.icd_version = 9 AND (LEFT(di.icd_code,3) IN ('710', '714', '725')))
                   OR (di.icd_version = 10 AND (LEFT(di.icd_code,3) BETWEEN 'M05' AND 'M06' OR LEFT(di.icd_code,3) = 'M08' OR LEFT(di.icd_code,4) = 'M131' OR LEFT(di.icd_code,4) = 'M315' OR LEFT(di.icd_code,4) = 'M316' OR LEFT(di.icd_code,3) = 'M32' OR LEFT(di.icd_code,3) = 'M33' OR LEFT(di.icd_code,3) = 'M34' OR LEFT(di.icd_code,4) = 'M351' OR LEFT(di.icd_code,4) = 'M352' OR LEFT(di.icd_code,4) = 'L940' OR LEFT(di.icd_code,4) = 'L941' OR LEFT(di.icd_code,4) = 'G737')) THEN 1 ELSE 0 END) AS conn_tissue,
        -- Peptic Ulcer Disease (1 point)
        MAX(CASE WHEN (di.icd_version = 9 AND LEFT(di.icd_code,3) BETWEEN '531' AND '534')
                   OR (di.icd_version = 10 AND LEFT(di.icd_code,3) BETWEEN 'K25' AND 'K28') THEN 1 ELSE 0 END) AS pud,
        -- Mild Liver Disease (1 point)
        MAX(CASE WHEN (di.icd_version = 9 AND (LEFT(di.icd_code,3) = '571' OR di.icd_code IN ('5723', '5733', '5734', '5738', '5739', '5761', 'V427')))
                   OR (di.icd_version = 10 AND (LEFT(di.icd_code,3) IN ('B18', 'K70') OR di.icd_code IN ('K713', 'K714', 'K715') OR LEFT(di.icd_code,3) = 'K73' OR di.icd_code IN ('K740', 'K741', 'K742', 'K746') OR LEFT(di.icd_code,3) = 'K76' OR di.icd_code = 'Z944')) THEN 1 ELSE 0 END) AS mild_liver,
        -- Diabetes with chronic complication (2 points)
        MAX(CASE WHEN (di.icd_version = 9 AND (LEFT(di.icd_code,4) LIKE '2504' OR LEFT(di.icd_code,4) LIKE '2505' OR LEFT(di.icd_code,4) LIKE '2506' OR LEFT(di.icd_code,4) LIKE '2507'))
                   OR (di.icd_version = 10 AND (LEFT(di.icd_code,3) IN ('E10', 'E11', 'E13') AND NOT (di.icd_code LIKE 'E109%' OR di.icd_code LIKE 'E119%' OR di.icd_code LIKE 'E139%'))) THEN 1 ELSE 0 END) AS dm_complication,
        -- Diabetes without chronic complication (1 point)
        MAX(CASE WHEN (di.icd_version = 9 AND (LEFT(di.icd_code,4) LIKE '2500' OR LEFT(di.icd_code,4) LIKE '2501' OR LEFT(di.icd_code,4) LIKE '2508' OR LEFT(di.icd_code,4) LIKE '2509'))
                   OR (di.icd_version = 10 AND (di.icd_code LIKE 'E109%' OR di.icd_code LIKE 'E119%' OR di.icd_code LIKE 'E139%')) THEN 1 ELSE 0 END) AS dm_no_complication,
        -- Hemiplegia or Paraplegia (2 points)
        MAX(CASE WHEN (di.icd_version = 9 AND (LEFT(di.icd_code,3) = '342' OR LEFT(di.icd_code,3) = '344'))
                   OR (di.icd_version = 10 AND (LEFT(di.icd_code,3) IN ('G81', 'G82'))) THEN 1 ELSE 0 END) AS hemiplegia,
        -- Renal Disease (2 points)
        MAX(CASE WHEN (di.icd_version = 9 AND (di.icd_code LIKE '40301' OR di.icd_code LIKE '40311' OR di.icd_code LIKE '40391' OR di.icd_code LIKE '40402' OR di.icd_code LIKE '40403' OR di.icd_code LIKE '40412' OR di.icd_code LIKE '40413' OR di.icd_code LIKE '40492' OR di.icd_code LIKE '40493' OR LEFT(di.icd_code,3) IN ('582', '583', '585') OR di.icd_code = '586' OR di.icd_code LIKE '5880%' OR di.icd_code IN ('V420', 'V451') OR LEFT(di.icd_code,3) = 'V56'))
                   OR (di.icd_version = 10 AND (LEFT(di.icd_code,3) BETWEEN 'N00' AND 'N07' OR LEFT(di.icd_code,3) BETWEEN 'N17' AND 'N19' OR di.icd_code = 'N250' OR di.icd_code IN ('I120', 'I131', 'I132') OR LEFT(di.icd_code,3) = 'Z49' OR di.icd_code = 'Z940' OR di.icd_code = 'Z992')) THEN 1 ELSE 0 END) AS renal,
        -- Any malignancy (2 points) - excludes skin
        MAX(CASE WHEN (di.icd_version = 9 AND ((LEFT(di.icd_code,3) BETWEEN '196' AND '199' AND NOT LEFT(di.icd_code,3) = '198') OR LEFT(di.icd_code,3) BETWEEN '200' AND '208'))
                   OR (di.icd_version = 10 AND ((LEFT(di.icd_code,3) BETWEEN 'C00' AND 'C26' OR LEFT(di.icd_code,3) BETWEEN 'C30' AND 'C34' OR LEFT(di.icd_code,3) BETWEEN 'C37' AND 'C41' OR LEFT(di.icd_code,3) = 'C43' OR LEFT(di.icd_code,3) BETWEEN 'C45' AND 'C58' OR LEFT(di.icd_code,3) BETWEEN 'C60' AND 'C76' OR LEFT(di.icd_code,3) BETWEEN 'C81' AND 'C96') AND NOT LEFT(di.icd_code,3) = 'C44')) THEN 1 ELSE 0 END) AS malignancy,
        -- Severe Liver Disease (3 points)
        MAX(CASE WHEN (di.icd_version = 9 AND (di.icd_code LIKE '4560%' OR di.icd_code LIKE '4561%' OR di.icd_code LIKE '4562%' OR di.icd_code = '5722'))
                   OR (di.icd_version = 10 AND (LEFT(di.icd_code,3) = 'I85' OR LEFT(di.icd_code,4) = 'I864' OR LEFT(di.icd_code,4) = 'I982$' OR LEFT(di.icd_code,3) = 'K72' OR di.icd_code IN ('K743', 'K744', 'K745', 'K767'))) THEN 1 ELSE 0 END) AS sev_liver,
        -- Metastatic Solid Tumor (6 points)
        MAX(CASE WHEN (di.icd_version = 9 AND (LEFT(di.icd_code,3) BETWEEN '196' AND '199'))
                   OR (di.icd_version = 10 AND (LEFT(di.icd_code,3) BETWEEN 'C77' AND 'C80')) THEN 1 ELSE 0 END) AS metast_cancer,
        -- AIDS/HIV (6 points)
        MAX(CASE WHEN (di.icd_version = 9 AND (di.icd_code LIKE '042%' OR di.icd_code = '07953' OR di.icd_code = 'V08'))
                   OR (di.icd_version = 10 AND (LEFT(di.icd_code,3) IN ('B20', 'B24') OR di.icd_code = 'R75' OR LEFT(di.icd_code,3) = 'Z21')) THEN 1 ELSE 0 END) AS aids
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    INNER JOIN
        Cohort c
        ON di.hadm_id = c.hadm_id
    GROUP BY
        di.hadm_id
),
-- CTE to calculate the total Charlson score for each admission
CharlsonCalculated AS (
    SELECT
        cc.hadm_id,
        (cc.mi * 1) + (cc.chf * 1) + (cc.pvd * 1) + (cc.cvd * 1) + (cc.dementia * 1) +
        (cc.copd * 1) + (cc.conn_tissue * 1) + (cc.pud * 1) + (cc.mild_liver * 1) +
        -- Diabetes logic: 2 points if complications, else 1 point if no complications, else 0
        (CASE WHEN cc.dm_complication = 1 THEN 2
              WHEN cc.dm_no_complication = 1 THEN 1 ELSE 0 END) +
        (cc.hemiplegia * 2) + (cc.renal * 2) + (cc.malignancy * 2) +
        (cc.sev_liver * 3) +
        (cc.metast_cancer * 6) + (cc.aids * 6) AS charlson_score
    FROM
        CharlsonComorbidities cc
),
-- CTE to detect medical interventions and derive other features for each admission
AdmissionFeatures AS (
    SELECT
        c.hadm_id,
        MAX(CASE WHEN ie.stay_id IS NOT NULL THEN 1 ELSE 0 END) AS has_icu_stay, -- Use MAX to check if any ICU stay exists for the hadm_id
        CASE
            WHEN TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY) <= 7 THEN 'LOS_LE_7'
            ELSE 'LOS_GT_7'
        END AS los_category,
        -- Mechanical Ventilation: detect using common chartevents itemids
        MAX(CASE WHEN ce_vent.charttime IS NOT NULL THEN 1 ELSE 0 END) AS has_mech_vent,
        -- Vasopressors: detect from inputevents (ICU) and prescriptions (Hosp)
        MAX(CASE WHEN ie_vaso.starttime IS NOT NULL THEN 1 ELSE 0 END) AS has_vasopressor_icu,
        MAX(CASE WHEN px.starttime IS NOT NULL THEN 1 ELSE 0 END) AS has_vasopressor_hosp,
        -- RRT: detect from procedures_icd (Hosp) and chartevents (ICU)
        MAX(CASE WHEN picd_rrt.icd_code IS NOT NULL THEN 1 ELSE 0 END) AS has_rrt_icd,
        MAX(CASE WHEN ce_rrt.charttime IS NOT NULL THEN 1 ELSE 0 END) AS has_rrt_chartevents
    FROM
        Cohort c
    LEFT JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` ie
        ON c.hadm_id = ie.hadm_id
    LEFT JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce_vent
        ON c.hadm_id = ce_vent.hadm_id
        AND ce_vent.itemid IN (
            223848, -- Ventilator Mode
            224687, -- Respiratory Rate (Set)
            224688, -- Respiratory Rate (Actual)
            220339, -- PEEP
            227287, -- Ventilator Settings
            224701, -- Tidal Volume (Set)
            224702  -- Tidal Volume (Actual)
        )
    LEFT JOIN
        `physionet-data.mimiciv_3_1_icu.inputevents` ie_vaso
        ON c.hadm_id = ie_vaso.hadm_id -- Fix: Changed ie_vasm_code to ie_vaso
        AND ie_vaso.itemid IN (
            221906, -- Norepinephrine
            221653, -- Dopamine
            221289, -- Epinephrine
            227310, -- Phenylephrine
            222301  -- Vasopressin
        )
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` px
        ON c.hadm_id = px.hadm_id
        AND (
            LOWER(px.drug) LIKE '%norepinephrine%' OR
            LOWER(px.drug) LIKE '%epinephrine%' OR
            LOWER(px.drug) LIKE '%dopamine%' OR
            LOWER(px.drug) LIKE '%vasopressin%' OR
            LOWER(px.drug) LIKE '%phenylephrine%'
        )
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` picd_rrt
        ON c.hadm_id = picd_rrt.hadm_id
        AND (
            (picd_rrt.icd_version = 9 AND (picd_rrt.icd_code = '3995' OR picd_rrt.icd_code = '5498')) OR
            (picd_rrt.icd_version = 10 AND (picd_rrt.icd_code = '5A1D00Z' OR picd_rrt.icd_code = '5A1H0ZZ')) -- Common RRT ICD-10 codes for Hemodialysis and other RRT
        )
    LEFT JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce_rrt
        ON c.hadm_id = ce_rrt.hadm_id
        AND ce_rrt.itemid IN (
            225792, -- CRRT Filter Total Duration
            225107, -- Dialysis Total UF
            225108, -- Dialysis Access Site
            224149  -- Hemodialysis
        )
    GROUP BY
        c.hadm_id, c.dischtime, c.admittime
),
-- Combine all information for the final analysis
FinalData AS (
    SELECT
        c.subject_id,
        c.hadm_id,
        af.has_icu_stay,
        af.los_category,
        CASE
            WHEN COALESCE(cs.charlson_score, 0) <= 1 THEN 'Charlson_0_1'
            WHEN COALESCE(cs.charlson_score, 0) = 2 THEN 'Charlson_2'
            WHEN COALESCE(cs.charlson_score, 0) >= 3 THEN 'Charlson_GE_3'
            ELSE 'No_Charlson_Score' -- Should not happen if all admissions are in diagnoses_icd based on query flow and COALESCE
        END AS charlson_category,
        c.hospital_expire_flag,
        af.has_mech_vent,
        (af.has_vasopressor_icu = 1 OR af.has_vasopressor_hosp = 1) AS has_vasopressor,
        (af.has_rrt_icd = 1 OR af.has_rrt_chartevents = 1) AS has_rrt
    FROM
        Cohort c
    INNER JOIN
        AdmissionFeatures af
        ON c.hadm_id = af.hadm_id
    LEFT JOIN
        CharlsonCalculated cs
        ON c.hadm_id = cs.hadm_id
)
-- Final aggregation and calculation of percentages with 95% CI
SELECT
    CASE WHEN has_icu_stay = 1 THEN 'ICU' ELSE 'No_ICU' END AS ICU_Stay,
    los_category,
    charlson_category,
    COUNT(DISTINCT subject_id) AS num_patients_in_group,
    COUNT(hadm_id) AS num_admissions_in_group,
    ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(hadm_id), 2) AS in_hospital_mortality_pct,
    -- Define Z-score for 95% CI (1.96)
    -- Calculate 95% CI for mortality using Wilson Score Interval
    -- Lower bound
    ROUND(
        ( (SUM(hospital_expire_flag)/COUNT(hadm_id)) + (1.96*1.96)/(2.0*COUNT(hadm_id)) - 1.96*SQRT((SUM(hospital_expire_flag)/COUNT(hadm_id))*(1-(SUM(hospital_expire_flag)/COUNT(hadm_id)))/COUNT(hadm_id) + (1.96*1.96)/(4.0*COUNT(hadm_id)*COUNT(hadm_id))) ) / (1 + (1.96*1.96)/COUNT(hadm_id)) * 100.0, 2
    ) AS mortality_ci_lower_pct,
    -- Upper bound
    ROUND(
        ( (SUM(hospital_expire_flag)/COUNT(hadm_id)) + (1.96*1.96)/(2.0*COUNT(hadm_id)) + 1.96*SQRT((SUM(hospital_expire_flag)/COUNT(hadm_id))*(1-(SUM(hospital_expire_flag)/COUNT(hadm_id)))/COUNT(hadm_id) + (1.96*1.96)/(4.0*COUNT(hadm_id)*COUNT(hadm_id))) ) / (1 + (1.96*1.96)/COUNT(hadm_id)) * 100.0, 2
    ) AS mortality_ci_upper_pct,
    ROUND(SUM(has_mech_vent) * 100.0 / COUNT(hadm_id), 2) AS mech_vent_prevalence_pct,
    ROUND(SUM(CAST(has_vasopressor AS INT64)) * 100.0 / COUNT(hadm_id), 2) AS vasopressor_prevalence_pct,
    ROUND(SUM(CAST(has_rrt AS INT64)) * 100.0 / COUNT(hadm_id), 2) AS rrt_prevalence_pct
FROM
    FinalData
GROUP BY
    ICU_Stay,
    los_category,
    charlson_category
ORDER BY
    ICU_Stay DESC, -- ICU first
    los_category,
    charlson_category;