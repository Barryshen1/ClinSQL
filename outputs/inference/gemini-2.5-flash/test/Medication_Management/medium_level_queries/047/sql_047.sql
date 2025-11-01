with diabetes and heart failure
WITH Cohort AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 40 AND 50
        -- Check for Diabetes ICD codes
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dicd_dm
            WHERE
                dicd_dm.subject_id = adm.subject_id
                AND dicd_dm.hadm_id = adm.hadm_id
                AND (
                    (dicd_dm.icd_version = 9 AND dicd_dm.icd_code LIKE '250%')
                    OR (dicd_dm.icd_version = 10 AND dicd_dm.icd_code BETWEEN 'E10%' AND 'E14%')
                )
        )
        -- Check for Heart Failure ICD codes
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dicd_hf
            WHERE
                dicd_hf.subject_id = adm.subject_id
                AND dicd_hf.hadm_id = adm.hadm_id
                AND (
                    (dicd_hf.icd_version = 9 AND dicd_hf.icd_code LIKE '428%')
                    OR (dicd_hf.icd_version = 10 AND dicd_hf.icd_code LIKE 'I50%')
                )
        )
),
-- Step 2: Identify medication prescriptions for the cohort and categorize them into drug classes
MedicationPrescriptions AS (
    SELECT
        c.subject_id,
        c.hadm_id,
        c.admittime,
        c.dischtime,
        pr.drug,
        pr.starttime,
        pr.stoptime,
        -- Define drug classes using broad pattern matching for common generic names
        CASE
            WHEN LOWER(pr.drug) LIKE '%insulin%'
                 OR LOWER(pr.drug) LIKE '%metformin%'
                 OR LOWER(pr.drug) LIKE '%glipizide%'
                 OR LOWER(pr.drug) LIKE '%glyburide%'
                 OR LOWER(pr.drug) LIKE '%glimepiride%'
                 OR LOWER(pr.drug) LIKE '%canagliflozin%'
                 OR LOWER(pr.drug) LIKE '%dapagliflozin%'
                 OR LOWER(pr.drug) LIKE '%empagliflozin%'
                 OR LOWER(pr.drug) LIKE '%liraglutide%'
                 OR LOWER(pr.drug) LIKE '%semaglutide%'
                 OR LOWER(pr.drug) LIKE '%dulaglutide%'
                 OR LOWER(pr.drug) LIKE '%exenatide%'
                 OR LOWER(pr.drug) LIKE '%sitagliptin%'
                 OR LOWER(pr.drug) LIKE '%saxagliptin%'
                 OR LOWER(pr.drug) LIKE '%linagliptin%'
                 OR LOWER(pr.drug) LIKE '%pioglitazone%'
                 OR LOWER(pr.drug) LIKE '%rosiglitazone%'
                 OR LOWER(pr.drug) LIKE '%acarbose%'
                 OR LOWER(pr.drug) LIKE '%miglitol%'
                 OR LOWER(pr.drug) LIKE '%repaglinide%'
                 OR LOWER(pr.drug) LIKE '%nateglinide%'
            THEN 'Antidiabetic'
            WHEN LOWER(pr.drug) LIKE '%metoprolol%'
                 OR LOWER(pr.drug) LIKE '%carvedilol%'
                 OR LOWER(pr.drug) LIKE '%bisoprolol%'
                 OR LOWER(pr.drug) LIKE '%atenolol%'
                 OR LOWER(pr.drug) LIKE '%propranolol%'
                 OR LOWER(pr.drug) LIKE '%labetalol%'
                 OR LOWER(pr.drug) LIKE '%sotalol%'
                 OR LOWER(pr.drug) LIKE '%timolol%'
                 OR LOWER(pr.drug) LIKE '%esmolol%'
            THEN 'Beta-blocker'
            WHEN LOWER(pr.drug) LIKE '%lisinopril%'
                 OR LOWER(pr.drug) LIKE '%ramipril%'
                 OR LOWER(pr.drug) LIKE '%enalapril%'
                 OR LOWER(pr.drug) LIKE '%captopril%'
                 OR LOWER(pr.drug) LIKE '%quinapril%'
                 OR LOWER(pr.drug) LIKE '%benazepril%'
                 OR LOWER(pr.drug) LIKE '%fosinopril%'
                 OR LOWER(pr.drug) LIKE '%moexipril%'
                 OR LOWER(pr.drug) LIKE '%perindopril%'
                 OR LOWER(pr.drug) LIKE '%trandolapril%'
                 OR LOWER(pr.drug) LIKE '%losartan%'
                 OR LOWER(pr.drug) LIKE '%valsartan%'
                 OR LOWER(pr.drug) LIKE '%candesartan%'
                 OR LOWER(pr.drug) LIKE '%irbesartan%'
                 OR LOWER(pr.drug) LIKE '%olmesartan%'
                 OR LOWER(pr.drug) LIKE '%telmisartan%'
                 OR LOWER(pr.drug) LIKE '%sacubitril%' -- for sacubitril/valsartan (Entresto)
                 OR LOWER(pr.drug) LIKE '%entresto%'
            THEN 'ACEi_ARB_ARNI'
            WHEN LOWER(pr.drug) LIKE '%furosemide%'
                 OR LOWER(pr.drug) LIKE '%bumetanide%'
                 OR LOWER(pr.drug) LIKE '%torsemide%'
            THEN 'Loop Diuretic'
            ELSE 'Other' -- Catches drugs not of interest
        END AS drug_class
    FROM
        Cohort AS c
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
        ON c.subject_id = pr.subject_id AND c.hadm_id = pr.hadm_id
    -- Removed original WHERE clause as it's redundant and better handled in the next CTE
),
-- Step 3: Determine medication status for each patient, admission, and period
-- Ensure correct handling of NULL stoptime by assuming the drug continues for the duration of the hospital stay
MedicationStatus AS (
    SELECT
        mp.subject_id,
        mp.hadm_id,
        mp.admittime, -- Include admittime for more robust period calculations
        mp.dischtime,  -- Include dischtime for more robust period calculations
        mp.drug_class,
        -- Define the effective stoptime: if NULL, assume it continues beyond dischtime (or at least one day after discharge)
        -- This covers cases where prescriptions are ongoing at discharge.
        COALESCE(mp.stoptime, DATETIME_ADD(mp.dischtime, INTERVAL 1 DAY)) AS effective_stoptime,
        
        -- Flag if drug was active during the first 24 hours of admission
        -- The period starts at admittime and ends at LEAST(admittime + 24h, dischtime)
        -- A drug is active if its starttime is before or at the end of the period,
        -- AND its effective_stoptime is after or at the start of the period.
        (mp.starttime <= LEAST(DATETIME_ADD(mp.admittime, INTERVAL 24 HOUR), mp.dischtime)
         AND COALESCE(mp.stoptime, DATETIME_ADD(mp.dischtime, INTERVAL 1 DAY)) >= mp.admittime
        ) AS on_first_24h_raw,
        
        -- Flag if drug was active during the last 24 hours of admission
        -- The period starts at GREATEST(dischtime - 24h, admittime) and ends at dischtime
        (mp.starttime <= mp.dischtime
         AND COALESCE(mp.stoptime, DATETIME_ADD(mp.dischtime, INTERVAL 1 DAY)) >= GREATEST(DATETIME_SUB(mp.dischtime, INTERVAL 24 HOUR), mp.admittime)
        ) AS on_last_24h_raw
    FROM
        MedicationPrescriptions AS mp
    WHERE mp.drug_class != 'Other' -- Filter out non-relevant drug classes
),
-- Step 4: Aggregate medication status per admission and drug class
-- Use MAX to get a single indicator (1 if any drug in class was active, 0 otherwise) per period
AggregatedMedicationStatus AS (
    SELECT
        subject_id,
        hadm_id,
        drug_class,
        MAX(CASE WHEN on_first_24h_raw THEN 1 ELSE 0 END) AS on_first_24h,
        MAX(CASE WHEN on_last_24h_raw THEN 1 ELSE 0 END) AS on_last_24h
    FROM
        MedicationStatus
    GROUP BY
        subject_id,
        hadm_id,
        drug_class
),
-- Total number of unique admissions in the cohort for percentage calculation
TotalAdmissions AS (
    SELECT
        COUNT(DISTINCT hadm_id) AS total_admissions
    FROM
        Cohort
)
-- Step 5: Calculate the final metrics (percentages and counts)
SELECT
    ams.drug_class,
    -- Percentage on first 24h of admission
    ROUND(SUM(ams.on_first_24h) * 100.0 / ta.total_admissions, 2) AS percent_on_first_24h_of_stay,
    -- Percentage on last 24h of admission
    ROUND(SUM(ams.on_last_24h) * 100.0 / ta.total_admissions, 2) AS percent_on_last_24h_of_stay,
    -- Count of patients who continued the medication (on first 24h AND on last 24h)
    SUM(CASE WHEN ams.on_first_24h = 1 AND ams.on_last_24h = 1 THEN 1 ELSE 0 END) AS count_continued,
    -- Count of patients who initiated the medication late (NOT on first 24h AND on last 24h)
    SUM(CASE WHEN ams.on_first_24h = 0 AND ams.on_last_24h = 1 THEN 1 ELSE 0 END) AS count_initiated_late,
    -- Count of patients who discontinued the medication (on first 24h AND NOT on last 24h)
    SUM(CASE WHEN ams.on_first_24h = 1 AND ams.on_last_24h = 0 THEN 1 ELSE 0 END) AS count_discontinued
FROM
    AggregatedMedicationStatus AS ams
CROSS JOIN
    TotalAdmissions AS ta
GROUP BY
    ams.drug_class,
    ta.total_admissions
ORDER BY
    ams.drug_class;