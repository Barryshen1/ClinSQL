WITH
-- Step 1: Define the patient cohort of male inpatients, aged 49-59,
-- with diagnoses for both T2DM and Heart Failure.
cohort AS (
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
        AND p.anchor_age BETWEEN 49 AND 59
        AND a.hadm_id IN (
            SELECT
                hadm_id
            FROM
                `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
            GROUP BY
                hadm_id
            HAVING
                -- Condition for T2DM diagnosis (ICD-9 or ICD-10)
                SUM(CASE
                    WHEN (icd_version = 10 AND icd_code LIKE 'E11%')
                         OR (icd_version = 9 AND icd_code LIKE '250%' AND SUBSTR(icd_code, 5, 1) IN ('0', '2'))
                    THEN 1 ELSE 0
                END) > 0
            AND
                -- Condition for Heart Failure diagnosis (ICD-9 or ICD-10)
                SUM(CASE
                    WHEN (icd_version = 10 AND icd_code LIKE 'I50%')
                         OR (icd_version = 9 AND icd_code LIKE '428%')
                    THEN 1 ELSE 0
                END) > 0
        )
),

-- Step 2: For each patient and drug class, flag if administered in the first 24h or final 48h
patient_drug_flags AS (
    SELECT
        c.hadm_id,
        CASE
            -- ACEi/ARB/ARNI
            WHEN LOWER(e.medication) LIKE '%lisinopril%' OR LOWER(e.medication) LIKE '%enalapril%' OR LOWER(e.medication) LIKE '%ramipril%' OR LOWER(e.medication) LIKE '%captopril%' OR LOWER(e.medication) LIKE '%benazepril%' OR LOWER(e.medication) LIKE '%quinapril%' OR -- ACEi
                 LOWER(e.medication) LIKE '%losartan%' OR LOWER(e.medication) LIKE '%valsartan%' OR LOWER(e.medication) LIKE '%irbesartan%' OR LOWER(e.medication) LIKE '%candesartan%' OR LOWER(e.medication) LIKE '%olmesartan%' OR -- ARB
                 LOWER(e.medication) LIKE '%sacubitril%' OR LOWER(e.medication) LIKE '%entresto%' -- ARNI
                THEN 'ACEi/ARB/ARNI'
            -- Beta-Blocker
            WHEN LOWER(e.medication) LIKE '%metoprolol%' OR LOWER(e.medication) LIKE '%carvedilol%' OR LOWER(e.medication) LIKE '%atenolol%' OR LOWER(e.medication) LIKE '%labetalol%' OR LOWER(e.medication) LIKE '%bisoprolol%' OR LOWER(e.medication) LIKE '%propranolol%' OR LOWER(e.medication) LIKE '%esmolol%' OR LOWER(e.medication) LIKE '%sotalol%'
                THEN 'Beta-Blocker'
            -- Loop Diuretic
            WHEN LOWER(e.medication) LIKE '%furosemide%' OR LOWER(e.medication) LIKE '%lasix%' OR LOWER(e.medication) LIKE '%bumetanide%' OR LOWER(e.medication) LIKE '%bumex%' OR LOWER(e.medication) LIKE '%torsemide%'
                THEN 'Loop Diuretic'
            -- Antidiabetic
            WHEN LOWER(e.medication) LIKE '%insulin%' OR LOWER(e.medication) LIKE '%metformin%' OR LOWER(e.medication) LIKE '%glipizide%' OR LOWER(e.medication) LIKE '%glyburide%' OR LOWER(e.medication) LIKE '%pioglitazone%' OR LOWER(e.medication) LIKE '%rosiglitazone%' OR LOWER(e.medication) LIKE '%sitagliptin%' OR LOWER(e.medication) LIKE '%januvia%' OR LOWER(e.medication) LIKE '%saxagliptin%' OR LOWER(e.medication) LIKE '%linagliptin%' OR LOWER(e.medication) LIKE '%canagliflozin%' OR LOWER(e.medication) LIKE '%dapagliflozin%' OR LOWER(e.medication) LIKE '%empagliflozin%' OR LOWER(e.medication) LIKE '%jardiance%' OR LOWER(e.medication) LIKE '%liraglutide%' OR LOWER(e.medication) LIKE '%exenatide%' OR LOWER(e.medication) LIKE '%semaglutide%' OR LOWER(e.medication) LIKE '%ozempic%' OR LOWER(e.medication) LIKE '%dulaglutide%'
                THEN 'Antidiabetic'
            ELSE NULL
        END AS drug_class,
        -- Flag if there was at least one administration in the first 24 hours
        MAX(CASE WHEN e.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR) THEN 1 ELSE 0 END) AS in_first_24h,
        -- Flag if there was at least one administration in the final 48 hours
        MAX(CASE WHEN e.charttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime THEN 1 ELSE 0 END) AS in_final_48h
    FROM `physionet-data.mimiciv_3_1_hosp.emar` AS e
    INNER JOIN cohort AS c ON e.hadm_id = c.hadm_id
    GROUP BY
        c.hadm_id, drug_class
    HAVING drug_class IS NOT NULL
),

-- Step 3: Create a scaffold of all patients and all drug classes to ensure correct totals
all_patients_and_drugs AS (
    SELECT
      c.hadm_id,
      d.drug_class
    FROM cohort AS c
    CROSS JOIN (
        SELECT 'Antidiabetic' AS drug_class UNION ALL
        SELECT 'Beta-Blocker' AS drug_class UNION ALL
        SELECT 'ACEi/ARB/ARNI' AS drug_class UNION ALL
        SELECT 'Loop Diuretic' AS drug_class
    ) AS d
)

-- Step 4: Join the scaffold with the flags, aggregate results, and calculate all metrics
SELECT
    apd.drug_class,
    totals.total_patients,
    -- Calculate percentage of patients on the drug in the first 24h
    SAFE_DIVIDE(SUM(COALESCE(pdf.in_first_24h, 0)), totals.total_patients) * 100 AS pct_on_med_first_24h,
    -- Calculate percentage of patients on the drug in the final 48h
    SAFE_DIVIDE(SUM(COALESCE(pdf.in_final_48h, 0)), totals.total_patients) * 100 AS pct_on_med_final_48h,
    -- Count patients who were on the drug in both periods
    SUM(CASE WHEN COALESCE(pdf.in_first_24h, 0) = 1 AND COALESCE(pdf.in_final_48h, 0) = 1 THEN 1 ELSE 0 END) AS continued_count,
    -- Count patients who were not on the drug initially but were in the final period
    SUM(CASE WHEN COALESCE(pdf.in_first_24h, 0) = 0 AND COALESCE(pdf.in_final_48h, 0) = 1 THEN 1 ELSE 0 END) AS initiated_count,
    -- Count patients who were on the drug initially but not in the final period
    SUM(CASE WHEN COALESCE(pdf.in_first_24h, 0) = 1 AND COALESCE(pdf.in_final_48h, 0) = 0 THEN 1 ELSE 0 END) AS discontinued_count
FROM
    all_patients_and_drugs AS apd
LEFT JOIN
    patient_drug_flags AS pdf
    ON apd.hadm_id = pdf.hadm_id AND apd.drug_class = pdf.drug_class
-- Cross join with the total patient count to have it available for calculations
CROSS JOIN
    (SELECT COUNT(DISTINCT hadm_id) AS total_patients FROM cohort) AS totals
GROUP BY
    apd.drug_class,
    totals.total_patients
ORDER BY
    apd.drug_class;