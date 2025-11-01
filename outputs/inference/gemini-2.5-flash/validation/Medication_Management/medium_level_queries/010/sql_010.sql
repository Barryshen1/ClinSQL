WITH admission_info AS (
    -- Step 1: Filter patients by gender and age range
    SELECT
        p.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        p.gender,
        p.anchor_age
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON adm.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 67 AND 77
),
t2dm_hf_patients AS (
    -- Step 2: Identify admissions with both T2DM and HF diagnoses
    SELECT
        ai.subject_id,
        ai.hadm_id,
        ai.admittime,
        ai.dischtime
    FROM
        admission_info AS ai
    WHERE
        -- Check for Type 2 Diabetes Mellitus (T2DM) diagnosis
        EXISTS (
            SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di_dm
            WHERE
                di_dm.subject_id = ai.subject_id
                AND di_dm.hadm_id = ai.hadm_id
                AND (
                    -- ICD-9 codes for Diabetes Mellitus (often used as proxy for T2DM)
                    (di_dm.icd_version = 9 AND di_dm.icd_code LIKE '250%')
                    -- ICD-10 codes for Type 2 Diabetes Mellitus
                    OR (di_dm.icd_version = 10 AND di_dm.icd_code LIKE 'E11%' OR di_dm.icd_code LIKE 'E13%') -- E13 is other specified diabetes mellitus, E11 is T2DM. Added E13 for broader coverage if intended.
                )
        )
        -- Check for Heart Failure (HF) diagnosis
        AND EXISTS (
            SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di_hf
            WHERE
                di_hf.subject_id = ai.subject_id
                AND di_hf.hadm_id = ai.hadm_id
                AND (
                    -- ICD-9 codes for Heart Failure
                    (di_hf.icd_version = 9 AND di_hf.icd_code LIKE '428%')
                    -- ICD-10 codes for Heart Failure
                    OR (di_hf.icd_version = 10 AND di_hf.icd_code LIKE 'I50%')
                )
        )
),
qualified_patients AS (
    -- Final list of unique qualified patient-admission pairs
    SELECT DISTINCT subject_id, hadm_id, admittime, dischtime
    FROM t2dm_hf_patients
),
total_qualified_patients_count AS (
    -- Step 3: Calculate the total number of unique qualified patients
    SELECT COUNT(DISTINCT subject_id) AS total_patients
    FROM qualified_patients
),
patient_initiation_summary AS (
    -- Step 4: Map prescriptions to drug classes and check for initiation within windows
    SELECT
        dcm.drug_class,
        qp.subject_id,
        -- Flag if any drug from this class was initiated in the first 12 hours
        MAX(CASE
            WHEN dcm.starttime >= qp.admittime
            AND dcm.starttime <= DATETIME_ADD(qp.admittime, INTERVAL 12 HOUR)
            THEN 1 ELSE 0
        END) AS initiated_first_12h,
        -- Flag if any drug from this class was initiated in the final 48 hours
        MAX(CASE
            WHEN dcm.starttime >= DATETIME_SUB(qp.dischtime, INTERVAL 48 HOUR)
            AND dcm.starttime <= qp.dischtime
            THEN 1 ELSE 0
        END) AS initiated_final_48h
    FROM
        qualified_patients AS qp
    INNER JOIN
    (
        -- Subquery to categorize drugs into classes
        SELECT
            p.subject_id,
            p.hadm_id,
            p.starttime,
            p.stoptime,
            CASE
                WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'Insulin'
                WHEN LOWER(p.drug) LIKE '%metformin%' THEN 'Metformin'
                WHEN REGEXP_CONTAINS(LOWER(p.drug), r'glipi?zide|glyburide|glimepiride') THEN 'SU' -- Sulfonylureas
                WHEN REGEXP_CONTAINS(LOWER(p.drug), r'sitagliptin|saxagliptin|linagliptin|alogliptin') THEN 'DPP-4' -- DPP-4 inhibitors
                WHEN REGEXP_CONTAINS(LOWER(p.drug), r'canagliflozin|dapagliflozin|empagliflozin') THEN 'SGLT2' -- SGLT2 inhibitors
                WHEN REGEXP_CONTAINS(LOWER(p.drug), r'exenatide|liraglutide|dulaglutide|semaglutide') THEN 'GLP-1' -- GLP-1 receptor agonists
                WHEN REGEXP_CONTAINS(LOWER(p.drug), r'pioglitazone|rosiglitazone') THEN 'TZD' -- Thiazolidinediones
                ELSE NULL
            END AS drug_class
        FROM
            `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
        WHERE
            p.drug IS NOT NULL AND p.drug != ''
    ) AS dcm
    ON qp.subject_id = dcm.subject_id AND qp.hadm_id = dcm.hadm_id
    WHERE dcm.drug_class IS NOT NULL
    GROUP BY
        dcm.drug_class, qp.subject_id
)
-- Step 5: Calculate final percentages and net change
SELECT
    pis.drug_class,
    -- Count of unique patients who initiated a drug from this class in the first 12h
    COUNT(DISTINCT IF(pis.initiated_first_12h = 1, pis.subject_id, NULL)) AS num_initiated_first_12h_patients,
    -- Count of unique patients who initiated a drug from this class in the final 48h
    COUNT(DISTINCT IF(pis.initiated_final_48h = 1, pis.subject_id, NULL)) AS num_initiated_final_48h_patients,
    -- Percentage of patients who initiated in the first 12h
    ROUND(COUNT(DISTINCT IF(pis.initiated_first_12h = 1, pis.subject_id, NULL)) * 100.0 / tp.total_patients, 2) AS percent_first_12h,
    -- Percentage of patients who initiated in the final 48h
    ROUND(COUNT(DISTINCT IF(pis.initiated_final_48h = 1, pis.subject_id, NULL)) * 100.0 / tp.total_patients, 2) AS percent_final_48h,
    -- Net change in percentage points
    ROUND((COUNT(DISTINCT IF(pis.initiated_final_48h = 1, pis.subject_id, NULL)) * 100.0 / tp.total_patients) -
          (COUNT(DISTINCT IF(pis.initiated_first_12h = 1, pis.subject_id, NULL)) * 100.0 / tp.total_patients), 2) AS net_change_pp
FROM
    patient_initiation_summary AS pis,
    total_qualified_patients_count AS tp -- tp is cross-joined as it contains a single aggregate value
GROUP BY
    pis.drug_class, tp.total_patients
ORDER BY
    pis.drug_class;