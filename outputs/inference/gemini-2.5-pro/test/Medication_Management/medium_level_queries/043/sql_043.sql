WITH
-- Step 1: Identify hospital admissions (hadm_id) with both Diabetes and Heart Failure diagnoses.
hadm_with_conditions AS (
    SELECT
        hadm_id
    FROM (
        SELECT
            hadm_id,
            -- Flag for any diabetes diagnosis code
            MAX(CASE
                WHEN (icd_version = 9 AND icd_code LIKE '250%')
                  OR (icd_version = 10 AND (
                        icd_code LIKE 'E08%' OR icd_code LIKE 'E09%' OR icd_code LIKE 'E10%' OR
                        icd_code LIKE 'E11%' OR icd_code LIKE 'E13%'
                     ))
                THEN 1 ELSE 0
            END) AS has_diabetes,
            -- Flag for any heart failure diagnosis code
            MAX(CASE
                WHEN (icd_version = 9 AND icd_code LIKE '428%')
                  OR (icd_version = 10 AND icd_code LIKE 'I50%')
                THEN 1 ELSE 0
            END) AS has_hf
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        GROUP BY hadm_id
    ) AS diagnoses_by_hadm
    WHERE has_diabetes = 1 AND has_hf = 1
),

-- Step 2: Define the final patient cohort: Male, aged 77-87, with the required conditions.
cohort AS (
    SELECT
        adm.hadm_id,
        adm.admittime,
        adm.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    -- Filter for admissions that have our conditions of interest
    INNER JOIN hadm_with_conditions hwc
        ON adm.hadm_id = hwc.hadm_id
    WHERE
        -- Filter for male patients
        pat.gender = 'M'
        -- Filter for age at admission between 77 and 87 (inclusive)
        AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 77 AND 87
        -- Ensure admission and discharge times are valid and the stay is long enough
        -- for the two time windows not to overlap. (48h + 12h = 60h)
        AND adm.admittime IS NOT NULL AND adm.dischtime IS NOT NULL
        AND DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) > 60
),

-- Step 3: Classify medications and flag if they fall into the time windows.
med_events AS (
    SELECT
        c.hadm_id,
        -- Classify drug into categories of interest using regular expressions
        CASE
            WHEN REGEXP_CONTAINS(LOWER(pr.drug), r'^(insulin|metformin|glipizide|glyburide|glimepiride|pioglitazone|rosiglitazone|sitagliptin|saxagliptin|linagliptin|alogliptin|exenatide|liraglutide|semaglutide|dulaglutide|canagliflozin|dapagliflozin|empagliflozin|repaglinide|nateglinide)')
                THEN 'Antidiabetics'
            WHEN REGEXP_CONTAINS(LOWER(pr.drug), r'^(metoprolol|carvedilol|bisoprolol|atenolol|propranolol|labetalol|esmolol|nebivolol)')
                THEN 'Beta-blockers'
            WHEN REGEXP_CONTAINS(LOWER(pr.drug), r'^(lisinopril|enalapril|ramipril|captopril|benazepril|quinapril|perindopril|losartan|valsartan|irbesartan|olmesartan|candesartan|telmisartan|sacubitril|entresto)')
                THEN 'ACEi/ARB/ARNI'
            WHEN REGEXP_CONTAINS(LOWER(pr.drug), r'^(furosemide|bumetanide|torsemide|ethacrynic acid)')
                THEN 'Loop Diuretics'
            ELSE NULL
        END AS drug_class,
        -- Flag if the prescription start time is in the first 48 hours
        CASE
            WHEN pr.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
            THEN 1 ELSE 0
        END AS in_first_48h,
        -- Flag if the prescription start time is in the last 12 hours
        CASE
            WHEN pr.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime
            THEN 1 ELSE 0
        END AS in_last_12h
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    -- Only consider prescriptions for patients in our cohort
    INNER JOIN cohort AS c
        ON pr.hadm_id = c.hadm_id
    WHERE pr.starttime IS NOT NULL
),

-- Step 4: For each patient and drug class, determine if they received it in each window (1 if yes, 0 if no).
patient_drug_summary AS (
    SELECT
        hadm_id,
        drug_class,
        MAX(in_first_48h) AS received_in_first_48h,
        MAX(in_last_12h) AS received_in_last_12h
    FROM med_events
    WHERE drug_class IS NOT NULL
    GROUP BY hadm_id, drug_class
)

-- Final Step 5: Calculate the final rates and net change by drug class.
SELECT
    pds.drug_class,
    -- Calculate rate for the first 48h
    SUM(pds.received_in_first_48h) * 100.0 / (SELECT COUNT(DISTINCT hadm_id) FROM cohort) AS initiation_rate_first_48h_pct,
    -- Calculate rate for the last 12h
    SUM(pds.received_in_last_12h) * 100.0 / (SELECT COUNT(DISTINCT hadm_id) FROM cohort) AS initiation_rate_last_12h_pct,
    -- Calculate the net change in rates
    (SUM(pds.received_in_last_12h) * 100.0 / (SELECT COUNT(DISTINCT hadm_id) FROM cohort))
    - (SUM(pds.received_in_first_48h) * 100.0 / (SELECT COUNT(DISTINCT hadm_id) FROM cohort)) AS net_change_pct
FROM patient_drug_summary AS pds
GROUP BY pds.drug_class
ORDER BY pds.drug_class;