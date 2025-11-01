WITH patient_cohort AS (
    -- Step 1: Identify the base cohort of female patients aged 71-81 at admission
    SELECT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON a.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        -- Calculate age at admission and filter
        AND (DATETIME_DIFF(a.admittime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) + p.anchor_age) BETWEEN 71 AND 81
),

lgib_admissions AS (
    -- Step 2: Find admissions with LGIB and classify as 'Primary' or 'Secondary'
    SELECT
        hadm_id,
        -- If any LGIB code is seq_num=1, classify the admission as 'Primary'
        CASE
            WHEN MIN(seq_num) = 1 THEN 'Primary'
            ELSE 'Secondary'
        END AS diagnosis_type
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        -- Common ICD-9 and ICD-10 codes for Lower GI Bleed
        icd_code IN (
            'K921',   -- Melena (ICD-10)
            'K922',   -- Gastrointestinal hemorrhage, unspecified (ICD-10)
            'K625',   -- Hemorrhage of anus and rectum (ICD-10)
            '5781',   -- Melena (ICD-9)
            '5789',   -- Hemorrhage of gastrointestinal tract, unspecified (ICD-9)
            '5693'    -- Hemorrhage of rectum and anus (ICD-9)
        )
    GROUP BY
        hadm_id
),

imaging_counts AS (
    -- Step 3: Count the number of CT/Radiography procedures for each admission
    SELECT
        h.hadm_id,
        COUNT(h.hcpcs_cd) AS num_imaging_studies
    FROM
        `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
        ON h.hcpcs_cd = d.code
    WHERE
        -- Filter for descriptions related to CT scans or radiography
        LOWER(d.long_description) LIKE '%computed tomography%'
        OR LOWER(d.long_description) LIKE '% ct %'
        OR LOWER(d.long_description) LIKE '%radiograph%'
    GROUP BY
        h.hadm_id
)

-- Step 4: Final assembly and calculation
SELECT
    final_data.los_category,
    final_data.diagnosis_type,
    AVG(final_data.num_imaging_studies) AS mean_radiography_ct_per_admission
FROM (
    SELECT
        pc.hadm_id,
        lgib.diagnosis_type,
        COALESCE(ic.num_imaging_studies, 0) AS num_imaging_studies,
        -- Calculate LOS in days, rounding up to the nearest day
        CEIL(DATETIME_DIFF(pc.dischtime, pc.admittime, HOUR) / 24.0) AS los_days,
        -- Categorize LOS into the specified buckets
        CASE
            WHEN CEIL(DATETIME_DIFF(pc.dischtime, pc.admittime, HOUR) / 24.0) BETWEEN 1 AND 3 THEN '1-3 day stay'
            WHEN CEIL(DATETIME_DIFF(pc.dischtime, pc.admittime, HOUR) / 24.0) BETWEEN 4 AND 7 THEN '4-7 day stay'
            ELSE NULL
        END AS los_category
    FROM
        patient_cohort AS pc
    -- Restrict to the cohort of patients who also have an LGIB diagnosis
    INNER JOIN
        lgib_admissions AS lgib
        ON pc.hadm_id = lgib.hadm_id
    -- Left join to include admissions with zero imaging studies
    LEFT JOIN
        imaging_counts AS ic
        ON pc.hadm_id = ic.hadm_id
) AS final_data
-- Filter out admissions that do not fall into the specified LOS categories
WHERE
    final_data.los_category IS NOT NULL
-- Group by the required categories to calculate the final average
GROUP BY
    final_data.los_category,
    final_data.diagnosis_type
ORDER BY
    final_data.los_category,
    final_data.diagnosis_type;