WITH admissions_cohort AS (
    SELECT
        pa.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` pa
    JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON pa.subject_id = ad.subject_id
    WHERE
        pa.gender = 'M'
        AND pa.anchor_age BETWEEN 36 AND 46
        -- Must have a discharge time for 'last 12h' calculation
        AND ad.dischtime IS NOT NULL
        -- Ensure the admission is at least 12 hours long for a meaningful 'last 12h' window
        AND TIMESTAMP_DIFF(ad.dischtime, ad.admittime, HOUR) >= 12
),
-- Filter admissions_cohort further for those with both diabetes and heart failure diagnoses
hadm_diagnoses AS (
    SELECT
        ac.subject_id,
        ac.hadm_id,
        ac.admittime,
        ac.dischtime,
        MAX(CASE
            WHEN (d.icd_version = 9 AND d.icd_code LIKE '250%') -- ICD-9 Diabetes
            OR (d.icd_version = 10 AND d.icd_code BETWEEN 'E08' AND 'E13') -- ICD-10 Diabetes
            THEN 1 ELSE 0 END) AS has_diabetes,
        MAX(CASE
            WHEN (d.icd_version = 9 AND d.icd_code LIKE '428%') -- ICD-9 Heart Failure
            OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%') -- ICD-10 Heart Failure
            THEN 1 ELSE 0 END) AS has_heart_failure
    FROM
        admissions_cohort ac
    JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON ac.subject_id = d.subject_id AND ac.hadm_id = d.hadm_id
    GROUP BY
        ac.subject_id, ac.hadm_id, ac.admittime, ac.dischtime
    HAVING
        has_diabetes = 1 AND has_heart_failure = 1
),
-- Step 2: Classify prescriptions and assign to time windows for the cohort
classified_prescriptions AS (
    SELECT
        hd.hadm_id,
        LOWER(p.drug) AS drug_name_lower,
        p.starttime,
        -- Define drug classes based on common drug names
        CASE
            WHEN LOWER(p.drug) LIKE '%insulin%'
              OR LOWER(p.drug) LIKE '%metformin%'
              OR LOWER(p.drug) LIKE '%glipizide%'
              OR LOWER(p.drug) LIKE '%glyburide%'
              OR LOWER(p.drug) LIKE '%glimepiride%'
              OR LOWER(p.drug) LIKE '%sitagliptin%'
              OR LOWER(p.drug) LIKE '%saxagliptin%'
              OR LOWER(p.drug) LIKE '%linagliptin%'
              OR LOWER(p.drug) LIKE '%alogliptin%'
              OR LOWER(p.drug) LIKE '%empagliflozin%'
              OR LOWER(p.drug) LIKE '%canagliflozin%'
              OR LOWER(p.drug) LIKE '%dapagliflozin%'
              OR LOWER(p.drug) LIKE '%semaglutide%'
              OR LOWER(p.drug) LIKE '%liraglutide%'
              OR LOWER(p.drug) LIKE '%dulaglutide%'
              OR LOWER(p.drug) LIKE '%pioglitazone%'
            THEN 'Antidiabetic'
            WHEN LOWER(p.drug) LIKE '%furosemide%'
              OR LOWER(p.drug) LIKE '%bumetanide%'
              OR LOWER(p.drug) LIKE '%torsemide%'
              OR LOWER(p.drug) LIKE '%hydrochlorothiazide%'
              OR LOWER(p.drug) LIKE '%spironolactone%'
              OR LOWER(p.drug) LIKE '%eplerenone%'
              OR LOWER(p.drug) LIKE '%lisinopril%'
              OR LOWER(p.drug) LIKE '%enalapril%'
              OR LOWER(p.drug) LIKE '%ramipril%'
              OR LOWER(p.drug) LIKE '%captopril%'
              OR LOWER(p.drug) LIKE '%losartan%'
              OR LOWER(p.drug) LIKE '%valsartan%'
              OR LOWER(p.drug) LIKE '%candesartan%'
              OR LOWER(p.drug) LIKE '%metoprolol%'
              OR LOWER(p.drug) LIKE '%carvedilol%'
              OR LOWER(p.drug) LIKE '%bisoprolol%'
              OR LOWER(p.drug) LIKE '%digoxin%'
              OR LOWER(p.drug) LIKE '%hydralazine%'
              OR LOWER(p.drug) LIKE '%nitroglycerin%'
              OR LOWER(p.drug) LIKE '%atorvastatin%'
              OR LOWER(p.drug) LIKE '%simvastatin%'
              OR LOWER(p.drug) LIKE '%rosuvastatin%'
              OR LOWER(p.drug) LIKE '%amiodarone%'
            THEN 'Cardiac'
            ELSE 'Other' -- Exclude other drugs from further analysis
        END AS drug_class,
        -- Determine if prescription falls into first 48h
        CASE
            WHEN p.starttime >= hd.admittime
            AND p.starttime <= TIMESTAMP_ADD(hd.admittime, INTERVAL 48 HOUR)
            THEN 1 ELSE 0
        END AS in_first_48h,
        -- Determine if prescription falls into last 12h
        CASE
            WHEN p.starttime IS NOT NULL
            AND p.starttime >= TIMESTAMP_SUB(hd.dischtime, INTERVAL 12 HOUR)
            AND p.starttime <= hd.dischtime
            THEN 1 ELSE 0
        END AS in_last_12h
    FROM
        hadm_diagnoses hd
    JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        ON hd.subject_id = p.subject_id AND hd.hadm_id = p.hadm_id
    WHERE
        p.starttime IS NOT NULL -- Exclude prescriptions without a valid start time
),
-- Step 3: Identify unique drug class prescription per hadm_id for each time window
-- This ensures that if a patient received multiple drugs from the same class, or the same drug multiple times,
-- it only counts as 1 for prevalence (i.e., 'prescribed' or 'not prescribed').
distinct_drug_occurrence AS (
    SELECT
        hadm_id,
        drug_class,
        MAX(in_first_48h) AS prescribed_in_first_48h,
        MAX(in_last_12h) AS prescribed_in_last_12h
    FROM
        classified_prescriptions
    WHERE
        drug_class != 'Other' -- Only focus on the specified drug classes
    GROUP BY
        hadm_id, drug_class
),
-- Step 4: Calculate total number of admissions in the cohort (the denominator for prevalence)
total_cohort_admissions AS (
    SELECT
        COUNT(DISTINCT hadm_id) AS total_admissions_count
    FROM
        hadm_diagnoses
),
-- Step 5: Calculate raw counts for each drug class in each window
prevalence_counts AS (
    SELECT
        drug_class,
        SUM(prescribed_in_first_48h) AS count_first_48h,
        SUM(prescribed_in_last_12h) AS count_last_12h -- Corrected column name
    FROM
         distinct_drug_occurrence
    GROUP BY
        drug_class
)
-- Step 6: Calculate prevalence percentages and absolute differences
SELECT
    pc.drug_class,
    SAFE_DIVIDE(pc.count_first_48h * 100.0, tca.total_admissions_count) AS prevalence_first_48h_percent,
    SAFE_DIVIDE(pc.count_last_12h * 100.0, tca.total_admissions_count) AS prevalence_last_12h_percent,
    (SAFE_DIVIDE(pc.count_last_12h * 100.0, tca.total_admissions_count) - SAFE_DIVIDE(pc.count_first_48h * 100.0, tca.total_admissions_count)) AS absolute_difference_pp
FROM
    prevalence_counts pc
CROSS JOIN -- Use CROSS JOIN as total_cohort_admissions is a single-row table
    total_cohort_admissions tca
ORDER BY
    pc.drug_class;