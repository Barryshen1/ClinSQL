WITH cohort AS (
    SELECT 
        ie.subject_id, 
        ie.hadm_id, 
        ie.stay_id,
        ie.intime,
        ie.outtime
    FROM `physionet-data.mimiciv_3_1_icu`.icustays ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
        ON ie.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions adm
        ON ie.hadm_id = adm.hadm_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 37 AND 47
        AND ie.los >= 144  -- ICU stay >= 144 hours
    -- Check for diabetes and heart failure
    AND ie.hadm_id IN (
        SELECT di.hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
        WHERE (
            -- Diabetes codes (ICD-9: 250.*, ICD-10: E10-E14)
            (di.icd_version = 9 AND di.icd_code LIKE '250%')
            OR (di.icd_version = 10 AND di.icd_code LIKE 'E1%')
        )
    )
    AND ie.hadm_id IN (
        SELECT di.hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
        WHERE (
            -- Heart failure codes (ICD-9: 428.*, ICD-10: I50.*)
            (di.icd_version = 9 AND di.icd_code LIKE '428%')
            OR (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
        )
    )
),

-- Define time windows for each stay
time_windows AS (
    SELECT
        stay_id,
        intime AS start_icu,
        outtime AS end_icu,
        DATETIME_ADD(intime, INTERVAL 72 HOUR) AS end_first72,
        -- Ensure start_final72 doesn't come before ICU start
        GREATEST(DATETIME_SUB(outtime, INTERVAL 72 HOUR), intime) AS start_final72
    FROM cohort
),

-- Identify medications for each drug class
meds AS (
    SELECT
        pr.subject_id,
        pr.hadm_id,
        pr.starttime,
        -- If stoptime is NULL, assume it continues until ICU discharge
        COALESCE(pr.stoptime, tw.end_icu) AS stoptime,
        tw.stay_id,
        tw.start_icu,
        tw.end_icu,
        tw.end_first72,
        tw.start_final72,
        -- Drug class flags
        CASE WHEN LOWER(pr.drug) LIKE '%insulin%' OR LOWER(pr.drug) LIKE '%metformin%' OR LOWER(pr.drug) LIKE '%glipizide%' OR LOWER(pr.drug) LIKE '%glyburide%' OR LOWER(pr.drug) LIKE '%glimepiride%' OR LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%saxagliptin%' OR LOWER(pr.drug) LIKE '%linagliptin%' OR LOWER(pr.drug) LIKE '%empagliflozin%' OR LOWER(pr.drug) LIKE '%dapagliflozin%' OR LOWER(pr.drug) LIKE '%canagliflozin%' OR LOWER(pr.drug) LIKE '%pioglitazone%' OR LOWER(pr.drug) LIKE '%rosiglitazone%' OR LOWER(pr.drug) LIKE '%exenatide%' OR LOWER(pr.drug) LIKE '%liraglutide%' OR LOWER(pr.drug) LIKE '%semaglutide%' THEN 1 ELSE 0 END AS antidiabetic,
        CASE WHEN LOWER(pr.drug) LIKE '%metoprolol%' OR LOWER(pr.drug) LIKE '%atenolol%' OR LOWER(pr.drug) LIKE '%propranolol%' OR LOWER(pr.drug) LIKE '%carvedilol%' OR LOWER(pr.drug) LIKE '%labetalol%' OR LOWER(pr.drug) LIKE '%bisoprolol%' OR LOWER(pr.drug) LIKE '%nebivolol%' THEN 1 ELSE 0 END AS beta_blocker,
        CASE WHEN LOWER(pr.drug) LIKE '%lisinopril%' OR LOWER(pr.drug) LIKE '%enalapril%' OR LOWER(pr.drug) LIKE '%ramipril%' OR LOWER(pr.drug) LIKE '%quinapril%' OR LOWER(pr.drug) LIKE '%captopril%' OR LOWER(pr.drug) LIKE '%benazepril%' OR LOWER(pr.drug) LIKE '%losartan%' OR LOWER(极pr.drug) LIKE '%valsartan%' OR LOWER(pr.drug) LIKE '%irbesartan%' OR LOWER(pr.drug) LIKE '%candesartan%' OR LOWER(pr.drug) LIKE '%olmesartan%' OR LOWER(pr.drug) LIKE '%telmisartan%' OR LOWER(pr.drug) LIKE '%azilsartan%' OR LOWER(pr.drug) LIKE '%sacubitril%' OR LOWER(pr.drug) LIKE '%entresto%' OR LOWER(pr.drug) LIKE '%arni%' THEN 1 ELSE 0 END AS acei_arb_arni,
        CASE WHEN LOWER(pr.drug) LIKE '%furosemide%' OR LOWER(pr.drug) LIKE '%bumetanide%' OR LOWER(pr.drug) LIKE '%torsemide%' OR LOWER(pr.drug) LIKE '%ethacrynic acid%' THEN 1 ELSE 0 END AS loop_diuretic
    FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions pr
    INNER JOIN cohort c ON pr.hadm_id = c.hadm_id
    INNER JOIN time_windows tw ON c.stay_id = tw.stay_id
    WHERE pr.starttime <= tw.end_icu  -- medication started before ICU end
),

-- For each stay and drug class, check if administered in first72 and final72
drug_usage AS (
    SELECT
        stay_id,
        -- Check for each drug class: if any medication in that class overlaps the window
        MAX(CASE WHEN antidiabetic = 1 AND starttime <= end_first72 AND stoptime >= start_icu THEN 1 ELSE 0 END) AS antidiabetic_first72,
        MAX(CASE WHEN antidiabetic = 1 AND starttime <= end_icu AND stoptime >= start_final72 THEN 1 ELSE 0 END) AS antidiabetic_final72,

        MAX(CASE WHEN beta_blocker = 1 AND starttime <= end_first72 AND stoptime >= start_icu THEN 1 ELSE 0 END) AS beta_blocker_first72,
        MAX(CASE WHEN beta_blocker = 1 AND starttime <= end_icu AND stoptime >= start_final72 THEN 1 ELSE 0 END) AS beta_blocker_final72,

        MAX(CASE WHEN acei_arb_arni = 1 AND starttime <= end_first72 AND stoptime >= start_icu THEN 1 ELSE 0 END) AS acei_arb_arni_first72,
        MAX(CASE WHEN acei_arb_arni = 1 AND starttime <= end_icu AND stoptime >= start_final72 THEN 1 ELSE 0 END) AS acei_arb_arni_final72,

        MAX(CASE WHEN loop_diuretic = 1 AND starttime <= end_first72 AND stoptime >= start_icu THEN 1 ELSE 0 END) AS loop_diuretic_first72,
        MAX(CASE WHEN loop_diuretic = 1 AND starttime <= end_icu AND stoptime >= start_final72 THEN 1 ELSE 0 END) AS loop_diuretic_final72
    FROM meds
    GROUP BY stay_id
)

-- Aggregate across stays
SELECT
    'Antidiabetics' AS drug_class,
    COUNT(*) AS total_stays,
    ROUND(100 * AVG(antidiabetic_first72), 1) AS pct_first72,
    ROUND(100 * AVG(antidiabetic_final72), 1) AS pct_final72,
    SUM(CASE WHEN antidiabetic_first72 = 1 AND antidiabetic_final72 = 1 THEN 1 ELSE 0 END) AS continued,
    SUM(CASE WHEN antidiabetic_first72 = 0 AND antidiabetic_final72 = 1 THEN 1 ELSE 0 END) AS initiated,
    SUM(CASE WHEN antidiabetic_first72 = 1 AND antidiabetic_final72 = 0 THEN 1 ELSE 0 END) AS discontinued
FROM drug_usage
UNION ALL
SELECT
    'Beta-blockers' AS drug_class,
    COUNT(*),
    ROUND(100 * AVG(beta_blocker_first72), 1),
    ROUND(100 * AVG(beta_blocker_final72), 1),
    SUM(CASE WHEN beta_blocker_first72 = 1 AND beta_blocker_final72 = 1 THEN 1 ELSE 0 END),
    SUM(CASE WHEN beta_block极er_first72 = 0 AND beta_blocker_final72 = 1 THEN 1 ELSE 0 END),
    SUM(CASE WHEN beta_blocker_first72 = 1 AND beta_blocker_final72 = 0 THEN 1 ELSE 0 END)
FROM drug_usage
UNION ALL
SELECT
    'ACEi/ARB/ARNI' AS drug_class,
    COUNT(*),
    ROUND(100 * AVG(acei_arb_arni_first72), 1),
    ROUND(100 * AVG(acei_arb_arni_final72), 1),
    SUM(CASE WHEN acei_arb_arni_first72 = 1 AND acei_arb_arni_final72 = 1 THEN 1 ELSE 0 END),
    SUM(CASE WHEN acei_arb_arni_first72 = 0 AND acei_arb_arni_final72 = 1 THEN 1 ELSE 0 END),
    SUM(CASE WHEN acei_arb_arni_first72 = 1 AND acei_arb_arni_final72 = 0 THEN 1 ELSE 0 END)
FROM drug_usage
UNION ALL
SELECT
    'Loop diuretics' AS drug_class,
    COUNT(*),
    ROUND(100 * AVG(loop_diuretic_first72), 1),
    ROUND(100 * AVG(loop_diuretic_final72), 1),
    SUM(CASE WHEN loop_diuretic_first72 = 1 AND loop_diuretic_final72 = 1 THEN 1 ELSE 0 END),
    SUM(CASE WHEN loop_diuretic_first72 = 0 AND loop_diuretic_final72 = 1 THEN 1 ELSE 0 END),
    SUM(CASE WHEN loop_diuretic_first72 = 1 AND loop_diuretic_final72 = 0 THEN 极1 ELSE 0 END)
FROM drug_usage;