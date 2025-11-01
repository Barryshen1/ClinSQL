with ischemic stroke, this query calculates the
-- mean, min, and max number of diagnostic procedures per admission.
-- Results are stratified by length of stay (1-4 vs 5-8 days) and
-- whether the stroke was a primary or secondary diagnosis.

-- Step 1: Create a CTE to identify all relevant ICD codes for Ischemic Stroke.
WITH IschemicStrokeCodes AS (
    SELECT icd_code, icd_version
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE
        (
            LOWER(long_title) LIKE '%ischemic stroke%'
            OR LOWER(long_title) LIKE '%cerebral infarction%'
        )
        -- Exclude diagnoses that are historical to focus on the acute problem.
        AND LOWER(long_title) NOT LIKE '%history of%'
),

-- Step 2: Identify all hospital admissions for the target cohort (females, 49-59)
-- with an ischemic stroke diagnosis.
StrokeAdmissions AS (
    SELECT
        ad.hadm_id,
        -- Determine if stroke was a primary diagnosis by finding the minimum sequence number.
        MIN(dx.seq_num) AS min_stroke_seq_num,
        -- Calculate the length of stay in days.
        DATETIME_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
        ON p.subject_id = ad.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        ON ad.hadm_id = dx.hadm_id
    -- Ensure the diagnosis is for ischemic stroke.
    INNER JOIN IschemicStrokeCodes AS isc
        ON dx.icd_code = isc.icd_code AND dx.icd_version = isc.icd_version
    WHERE
        p.gender = 'F'
        -- Calculate age at admission and filter for the 49-59 age range.
        AND (EXTRACT(YEAR FROM ad.admittime) - p.anchor_year + p.anchor_age) BETWEEN 49 AND 59
    GROUP BY
        ad.hadm_id,
        ad.admittime,
        ad.dischtime
),

-- Step 3: Count the number of diagnostic procedures for each admission, including both ICD-9 and ICD-10.
DiagnosticProcedureCounts AS (
    SELECT
        hadm_id,
        COUNT(icd_code) AS num_diag_procedures
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
    WHERE
        -- ICD-9-CM codes for miscellaneous diagnostic and therapeutic procedures
        (icd_version = 9 AND SUBSTR(icd_code, 1, 2) BETWEEN '87' AND '99')
        OR
        -- ICD-10-PCS codes for diagnostic-related procedures
        -- B = Imaging, 4 = Measurement and Monitoring, C = Nuclear Medicine
        (icd_version = 10 AND SUBSTR(icd_code, 1, 1) IN ('B', '4', 'C'))
    GROUP BY
        hadm_id
),

-- Step 4: Combine admission info with procedure counts and create final categories.
CombinedData AS (
    SELECT
        sa.hadm_id,
        -- Categorize length of stay.
        CASE
            WHEN sa.los_days BETWEEN 1 AND 4 THEN '1-4 day stay'
            WHEN sa.los_days BETWEEN 5 AND 8 THEN '5-8 day stay'
            ELSE NULL
        END AS los_group,
        -- Categorize diagnosis type.
        CASE
            WHEN sa.min_stroke_seq_num = 1 THEN 'Primary Diagnosis'
            ELSE 'Secondary Diagnosis'
        END AS diagnosis_type,
        -- Use COALESCE to count 0 for admissions with no diagnostic procedures.
        COALESCE(dpc.num_diag_procedures, 0) AS num_diag_procedures
    FROM StrokeAdmissions AS sa
    LEFT JOIN DiagnosticProcedureCounts AS dpc
        ON sa.hadm_id = dpc.hadm_id
    -- Pre-filter for only the LOS groups of interest.
    WHERE sa.los_days BETWEEN 1 AND 8
)

-- Step 5: Final aggregation to calculate mean, min, and max procedures per group.
SELECT
    los_group,
    diagnosis_type,
    ROUND(AVG(num_diag_procedures), 2) AS mean_diag_procedures,
    MIN(num_diag_procedures) AS min_diag_procedures,
    MAX(num_diag_procedures) AS max_diag_procedures,
    COUNT(hadm_id) AS number_of_admissions
FROM CombinedData
WHERE los_group IS NOT NULL
GROUP BY
    los_group,
    diagnosis_type
ORDER BY
    los_group,
    diagnosis_type;