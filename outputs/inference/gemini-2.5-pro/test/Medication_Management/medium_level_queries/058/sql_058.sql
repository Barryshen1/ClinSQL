WITH
-- Step 1: Select male patients aged 36-46
patient_cohort AS (
    SELECT
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS a
        ON p.subject_id = a.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 36 AND 46
),

-- Step 2: Identify hospital admissions with both T2DM and Heart Failure
hadm_with_conditions AS (
    SELECT
        hadm_id
    FROM (
        SELECT
            dia.hadm_id,
            CASE
                WHEN (
                    LOWER(did.long_title) LIKE '%type 2 diabetes mellitus%'
                    OR (did.icd_version = 10 AND did.icd_code LIKE 'E11%')
                ) THEN 'T2DM'
                WHEN (
                    LOWER(did.long_title) LIKE '%heart failure%'
                    OR (did.icd_version = 10 AND did.icd_code LIKE 'I50%')
                    OR (did.icd_version = 9 AND did.icd_code LIKE '428%')
                ) THEN 'HF'
                ELSE NULL
            END AS condition
        FROM
            `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dia
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS did
            ON dia.icd_code = did.icd_code AND dia.icd_version = did.icd_version
    )
    WHERE condition IS NOT NULL
    GROUP BY
        hadm_id
    HAVING
        COUNT(DISTINCT condition) = 2 -- Ensure both conditions are present
),

-- Step 3: Create the final cohort by combining demographics and diagnoses
final_cohort AS (
    SELECT
        pc.hadm_id,
        pc.admittime,
        pc.dischtime
    FROM
        patient_cohort AS pc
    INNER JOIN
        hadm_with_conditions AS hwc
        ON pc.hadm_id = hwc.hadm_id
),

-- Step 4: Classify antidiabetic prescriptions for the cohort
classified_prescriptions AS (
    SELECT
        p.hadm_id,
        p.starttime,
        CASE
            WHEN LOWER(p.drug) LIKE '%metformin%' THEN 'Biguanides'
            WHEN LOWER(p.drug) LIKE '%glipizide%' OR LOWER(p.drug) LIKE '%glyburide%' OR LOWER(p.drug) LIKE '%glimepiride%' THEN 'Sulfonylureas'
            WHEN LOWER(p.drug) LIKE '%pioglitazone%' OR LOWER(p.drug) LIKE '%rosiglitazone%' THEN 'Thiazolidinediones (TZDs)'
            WHEN LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%linagliptin%' OR LOWER(p.drug) LIKE '%saxagliptin%' OR LOWER(p.drug) LIKE '%alogliptin%' THEN 'DPP-4 inhibitors'
            WHEN LOWER(p.drug) LIKE '%empagliflozin%' OR LOWER(p.drug) LIKE '%canagliflozin%' OR LOWER(p.drug) LIKE '%dapagliflozin%' OR LOWER(p.drug) LIKE '%ertugliflozin%' THEN 'SGLT-2 inhibitors'
            WHEN LOWER(p.drug) LIKE '%liraglutide%' OR LOWER(p.drug) LIKE '%exenatide%' OR LOWER(p.drug) LIKE '%semaglutide%' OR LOWER(p.drug) LIKE '%dulaglutide%' OR LOWER(p.drug) LIKE '%lixisenatide%' THEN 'GLP-1 receptor agonists'
            WHEN LOWER(p.drug) LIKE '%insulin%' OR LOWER(p.drug) LIKE '%humalog%' OR LOWER(p.drug) LIKE '%novolog%' OR LOWER(p.drug) LIKE '%lantus%' OR LOWER(p.drug) LIKE '%levemir%' OR LOWER(p.drug) LIKE '%aspart%' OR LOWER(p.drug) LIKE '%lispro%' OR LOWER(p.drug) LIKE '%glargine%' OR LOWER(p.drug) LIKE '%detemir%' THEN 'Insulin'
            ELSE NULL
        END AS drug_class
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
    WHERE p.hadm_id IN (SELECT hadm_id FROM final_cohort)
),

-- Step 5: Identify the first prescription (initiation) for each drug class per admission
drug_initiations AS (
    SELECT
        hadm_id,
        drug_class,
        starttime AS initiation_time
    FROM (
        SELECT
            hadm_id,
            starttime,
            drug_class,
            ROW_NUMBER() OVER(PARTITION BY hadm_id, drug_class ORDER BY starttime) as rn
        FROM classified_prescriptions
        WHERE drug_class IS NOT NULL
    )
    WHERE rn = 1
)

-- Step 6: Calculate initiation rates and net change
SELECT
    di.drug_class,
    SAFE_DIVIDE(
        COUNT(DISTINCT CASE WHEN di.initiation_time BETWEEN fc.admittime AND DATETIME_ADD(fc.admittime, INTERVAL 12 HOUR) THEN fc.hadm_id END) * 100.0,
        total_patients.count
    ) AS initiation_rate_first_12h_pct,
    SAFE_DIVIDE(
        COUNT(DISTINCT CASE WHEN di.initiation_time BETWEEN DATETIME_SUB(fc.dischtime, INTERVAL 48 HOUR) AND fc.dischtime THEN fc.hadm_id END) * 100.0,
        total_patients.count
    ) AS initiation_rate_final_48h_pct,
    (
        SAFE_DIVIDE(
            COUNT(DISTINCT CASE WHEN di.initiation_time BETWEEN DATETIME_SUB(fc.dischtime, INTERVAL 48 HOUR) AND fc.dischtime THEN fc.hadm_id END) * 100.0,
            total_patients.count
        )
        -
        SAFE_DIVIDE(
            COUNT(DISTINCT CASE WHEN di.initiation_time BETWEEN fc.admittime AND DATETIME_ADD(fc.admittime, INTERVAL 12 HOUR) THEN fc.hadm_id END) * 100.0,
            total_patients.count
        )
    ) AS net_change_pp
FROM
    drug_initiations AS di
INNER JOIN
    final_cohort AS fc ON di.hadm_id = fc.hadm_id
CROSS JOIN
    (SELECT COUNT(hadm_id) AS count FROM final_cohort) AS total_patients
GROUP BY
    di.drug_class,
    total_patients.count
ORDER BY
    drug_class;