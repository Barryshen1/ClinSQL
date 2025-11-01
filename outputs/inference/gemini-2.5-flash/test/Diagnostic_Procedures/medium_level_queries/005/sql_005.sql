WITH ischemic_stroke_codes AS (
    -- Define the ICD codes for ischemic stroke, based on common clinical definitions.
    -- This includes specific sub-types of cerebral infarction for both ICD-9 and ICD-10.
    SELECT icd_code, icd_version
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE
        (icd_version = 9 AND (
            -- ICD-9 codes for cerebral infarction due to thrombosis/embolism of precerebral/cerebral arteries
            icd_code LIKE '433.01%' OR
            icd_code LIKE '433.11%' OR
            icd_code LIKE '433.21%' OR
            icd_code LIKE '433.31%' OR
            icd_code LIKE '433.81%' OR
            icd_code LIKE '433.91%' OR
            icd_code LIKE '434.01%' OR
            icd_code LIKE '434.11%' OR
            icd_code LIKE '434.91%' OR
            icd_code = '436' -- Acute, but ill-defined, cerebrovascular disease (often included in stroke definitions)
        ))
        OR (icd_version = 10 AND icd_code LIKE 'I63%') -- ICD-10 codes for Cerebral infarction
),
admissions_with_stroke_diagnosis AS (
    -- Identify the target cohort: females 49-59 with an ischemic stroke diagnosis
    -- and categorize their admission length of stay (LOS) and primary/secondary stroke diagnosis status.
    SELECT
        pa.subject_id,
        ad.hadm_id,
        DATE_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days,
        -- Determine if the ischemic stroke was a primary (seq_num = 1) or secondary diagnosis.
        -- An admission is marked 'Primary Stroke Diagnosis' if any of its ischemic stroke diagnoses is seq_num=1.
        -- Otherwise (if all ischemic stroke diagnoses are seq_num > 1), it's 'Secondary Stroke Diagnosis'.
        CASE
            WHEN SUM(CASE WHEN di.seq_num = 1 THEN 1 ELSE 0 END) > 0 THEN 'Primary Stroke Diagnosis'
            ELSE 'Secondary Stroke Diagnosis'
        END AS diagnosis_type,
        -- Categorize length of stay (LOS) into the specified bins.
        CASE
            WHEN DATE_DIFF(ad.dischtime, ad.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4 day stays'
            WHEN DATE_DIFF(ad.dischtime, ad.admittime, DAY) BETWEEN 5 AND 8 THEN '5-8 day stays'
            -- Filter out other LOS categories later, but useful to define.
            ELSE 'Other'
        END AS los_category
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pa
        ON ad.subject_id = pa.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON ad.hadm_id = di.hadm_id
    INNER JOIN
        ischemic_stroke_codes isc
        ON di.icd_code = isc.icd_code AND di.icd_version = isc.icd_version
    WHERE
        pa.gender = 'F'
        AND pa.anchor_age BETWEEN 49 AND 59
        -- Filter admissions based on the question's specified LOS ranges (total 1-8 days).
        AND DATE_DIFF(ad.dischtime, ad.admittime, DAY) BETWEEN 1 AND 8
    GROUP BY
        pa.subject_id, ad.hadm_id, ad.admittime, ad.dischtime
    HAVING
        -- Ensure that there was at least one ischemic stroke diagnosis associated with the admission.
        COUNT(isc.icd_code) > 0
),
admissions_with_procedure_counts AS (
    -- Count the number of diagnostic procedures for each identified admission.
    -- All entries in `procedures_icd` are considered "diagnostic procedures" for this analysis,
    -- as a more specific definition was not provided.
    SELECT
        aw.hadm_id,
        aw.los_category,
        aw.diagnosis_type,
        COUNT(proc.icd_code) AS num_procedures -- Count all procedures
    FROM
        admissions_with_stroke_diagnosis aw
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
        ON aw.hadm_id = proc.hadm_id
    GROUP BY
        aw.hadm_id, aw.los_category, aw.diagnosis_type
)
-- Final aggregation to calculate mean, min, and max diagnostic procedures
-- per admission, grouped by LOS category and primary/secondary diagnosis type.
SELECT
    los_category,
    diagnosis_type,
    ROUND(AVG(num_procedures), 2) AS mean_diagnostic_procedures_per_admission,
    MIN(num_procedures) AS min_diagnostic_procedures_per_admission,
    MAX(num_procedures) AS max_diagnostic_procedures_per_admission
FROM
    admissions_with_procedure_counts
WHERE
    los_category IN ('1-4 day stays', '5-8 day stays') -- Ensure only specified LOS categories are included in final results
GROUP BY
    los_category,
    diagnosis_type
ORDER BY
    los_category,
    diagnosis_type;