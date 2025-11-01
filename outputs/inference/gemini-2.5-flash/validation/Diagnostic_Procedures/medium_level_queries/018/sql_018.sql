WITH hemorrhagic_stroke_admissions AS (
    -- Step 1: Identify the target patient population
    -- Women aged 80-90 with a hemorrhagic stroke diagnosis
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.subject_id = diag.subject_id AND adm.hadm_id = diag.hadm_id
    WHERE
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 80 AND 90 -- anchor_age represents age at first admission, suitable for this age range
        AND (
            -- ICD-9 codes for hemorrhagic stroke: Subarachnoid Hemorrhage, Intracerebral Hemorrhage, Other/Unspecified Intracranial Hemorrhage
            (diag.icd_version = 9 AND diag.icd_code IN ('430', '431', '432')) OR
            -- ICD-10 codes for hemorrhagic stroke: Nontraumatic Subarachnoid, Intracerebral, Other Nontraumatic Intracranial Hemorrhage
            (diag.icd_version = 10 AND (diag.icd_code LIKE 'I60%' OR diag.icd_code LIKE 'I61%' OR diag.icd_code LIKE 'I62%'))
        )
    GROUP BY -- Ensure distinct admissions that meet the criteria
        adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime
),
ultrasound_procedures AS (
    -- Step 2: Identify all procedures that are ultrasounds
    SELECT
        proc.hadm_id,
        proc.icd_code,
        proc.icd_version
    FROM
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d_proc
        ON proc.icd_code = d_proc.icd_code AND proc.icd_version = d_proc.icd_version
    WHERE
        (proc.icd_version = 9 AND proc.icd_code LIKE '88.7%') -- ICD-9 codes for Diagnostic Ultrasound
        OR
        (proc.icd_version = 10 AND (
            d_proc.long_title LIKE '%ultrasound%' OR
            d_proc.long_title LIKE '%echocardiogram%' -- Echocardiograms are a type of ultrasound
        ))
),
admission_ultrasound_counts AS (
    -- Step 3: Count ultrasounds per relevant admission and calculate LOS
    SELECT
        hsa.hadm_id,
        DATE_DIFF(hsa.dischtime, hsa.admittime, DAY) AS los_days,
        COUNT(up.hadm_id) AS num_ultrasounds -- Count the number of ultrasound procedures for each admission
    FROM
        hemorrhagic_stroke_admissions hsa
    LEFT JOIN -- Use LEFT JOIN to include admissions with 0 ultrasounds
        ultrasound_procedures up
        ON hsa.hadm_id = up.hadm_id
    GROUP BY
        hsa.hadm_id, los_days
)
-- Step 4: Categorize by LOS and calculate mean, min, max ultrasounds
SELECT
    CASE
        WHEN los_days BETWEEN 1 AND 4 THEN '1-4 Days'
        WHEN los_days BETWEEN 5 AND 7 THEN '5-7 Days'
        ELSE 'Other' -- Should be filtered out but good for completeness
    END AS los_category,
    COUNT(hadm_id) AS num_admissions_in_category,
    AVG(num_ultrasounds) AS mean_ultrasounds_per_admission,
    MIN(num_ultrasounds) AS min_ultrasounds_per_admission,
    MAX(num_ultrasounds) AS max_ultrasounds_per_admission
FROM
    admission_ultrasound_counts
WHERE
    los_days BETWEEN 1 AND 7 -- Filter for the specified length of stay ranges
GROUP BY
    los_category
ORDER BY
    los_category;