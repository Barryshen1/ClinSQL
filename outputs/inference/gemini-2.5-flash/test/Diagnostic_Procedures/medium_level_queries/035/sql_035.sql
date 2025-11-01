WITH Admissions_AKI_Eligible AS (
    -- Step 1: Identify AKI admissions with demographics and initial LOS
    SELECT
        a.subject_id,
        a.hadm_id,
        -- Calculate LOS in full days
        DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
        p.gender,
        p.anchor_age,
        -- Flags to determine AKI type (primary/secondary)
        MAX(CASE WHEN di.seq_num = 1 THEN 1 ELSE 0 END) AS has_primary_aki_diag,
        MAX(CASE WHEN di.seq_num > 1 THEN 1 ELSE 0 END) AS has_secondary_aki_diag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON a.subject_id = p.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
        ON a.hadm_id = di.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_diag
        ON di.icd_code = d_diag.icd_code AND di.icd_version = d_diag.icd_version
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 43 AND 53
        AND (
               (d_diag.icd_version = 9 AND d_diag.icd_code LIKE '584.%') -- ICD-9 for AKI
            OR (d_diag.icd_version = 10 AND d_diag.icd_code LIKE 'N17.%') -- ICD-10 for AKI
        )
    GROUP BY
        a.subject_id, a.hadm_id, a.admittime, a.dischtime, p.gender, p.anchor_age
),
Admissions_AKI_Classified AS (
    -- Step 2: Classify AKI admissions into Primary/Secondary based on sequence number,
    -- and filter for relevant LOS
    SELECT
        subject_id,
        hadm_id,
        los_days,
        CASE
            WHEN los_days BETWEEN 1 AND 4 THEN 'LOS 1-4 days'
            WHEN los_days BETWEEN 5 AND 7 THEN 'LOS 5-7 days'
            ELSE NULL -- Filtered later if not in target LOS
        END AS los_group,
        CASE
            WHEN has_primary_aki_diag = 1 THEN 'Primary AKI'
            WHEN has_primary_aki_diag = 0 AND has_secondary_aki_diag = 1 THEN 'Secondary AKI'
            ELSE 'Unknown AKI Type' -- Should not be reached with proper filtering
        END AS aki_type
    FROM
        Admissions_AKI_Eligible
    WHERE
        (has_primary_aki_diag = 1 OR has_secondary_aki_diag = 1) -- Ensure it's an AKI admission
        AND los_days BETWEEN 1 AND 7 -- Filter for the specified LOS ranges
),
Imaging_Procedures_Count AS (
    -- Step 3: Count MRI/CT procedures per admission
    SELECT
        pr.hadm_id,
        COUNT(pr.icd_code) AS count_mri_ct_procedures
    FROM
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pr
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d_proc
        ON pr.icd_code = d_proc.icd_code AND pr.icd_version = d_proc.icd_version
    WHERE
        (
               LOWER(d_proc.long_title) LIKE '%computed tomograph%'
            OR LOWER(d_proc.long_title) LIKE '%ct scan%'
            OR LOWER(d_proc.long_title) LIKE '%magnetic resonance imagin%'
            OR LOWER(d_proc.long_title) LIKE '%mri%'
        )
    GROUP BY
        pr.hadm_id
)
-- Step 4: Combine all data and calculate final metrics
SELECT
    aki.aki_type,
    aki.los_group,
    COUNT(DISTINCT aki.hadm_id) AS patient_admissions_count,
    COALESCE(AVG(ip.count_mri_ct_procedures), 0) AS mean_mri_ct_per_admission
FROM
    Admissions_AKI_Classified AS aki
LEFT JOIN
    Imaging_Procedures_Count AS ip
    ON aki.hadm_id = ip.hadm_id
GROUP BY
    aki.aki_type,
    aki.los_group
ORDER BY
    aki.aki_type,
    aki.los_group;