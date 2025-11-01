WITH ap_admissions AS (
    -- Step 1: Identify relevant hospital admissions for male patients (51-61) with acute pancreatitis.
    -- Categorize each admission by LOS and determine if the pancreatitis diagnosis was primary or secondary.
    SELECT
        p.subject_id,
        a.hadm_id,
        CASE
            WHEN CEIL(DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0) BETWEEN 1 AND 3 THEN '1-3 days'
            WHEN CEIL(DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0) BETWEEN 4 AND 7 THEN '4-7 days'
        END AS los_category,
        -- Determine if the diagnosis is primary by checking the minimum seq_num for pancreatitis for this admission.
        MIN(CASE WHEN diag.seq_num = 1 THEN 1 ELSE 2 END) AS diagnosis_priority
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON p.subject_id = a.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag ON a.hadm_id = diag.hadm_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 51 AND 61
        -- Filter for acute pancreatitis using both ICD-9 and ICD-10 codes.
        AND (
            (diag.icd_version = 9 AND diag.icd_code = '5770')
            OR (diag.icd_version = 10 AND diag.icd_code LIKE 'K85%')
        )
        -- Filter for admissions within the specified LOS ranges.
        AND CEIL(DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0) BETWEEN 1 AND 7
    GROUP BY
        p.subject_id,
        a.hadm_id,
        los_category
),
imaging_counts AS (
    -- Step 2: Count the number of radiography/CT procedures for each hospital admission.
    SELECT
        hadm_id,
        COUNT(*) AS imaging_count
    FROM
        `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
    WHERE
        -- Filter for HCPCS descriptions related to CT scans and radiography.
        LOWER(short_description) LIKE 'ct %'                -- e.g., 'CT ABDOMEN W/O CONTRAST'
        OR LOWER(short_description) LIKE '% tomograph%'       -- e.g., 'COMPUTED TOMOGRAPHY...'
        OR LOWER(short_description) LIKE 'radiologic exam%' -- e.g., 'RADIOLOGIC EXAM; CHEST...'
    GROUP BY
        hadm_id
)
-- Step 3: Join admissions with imaging counts and perform final aggregation.
SELECT
    ap.los_category,
    CASE
        WHEN ap.diagnosis_priority = 1 THEN 'Primary'
        ELSE 'Secondary'
    END AS diagnosis_type,
    COUNT(DISTINCT ap.subject_id) AS patient_count,
    -- Calculate the mean by dividing the total number of imaging procedures by the number of unique admissions in each group.
    SUM(COALESCE(img.imaging_count, 0)) / COUNT(DISTINCT ap.hadm_id) AS mean_radiography_cts_per_admission
FROM
    ap_admissions AS ap
LEFT JOIN
    imaging_counts AS img ON ap.hadm_id = img.hadm_id
GROUP BY
    ap.los_category,
    diagnosis_type
ORDER BY
    ap.los_category,
    diagnosis_type;