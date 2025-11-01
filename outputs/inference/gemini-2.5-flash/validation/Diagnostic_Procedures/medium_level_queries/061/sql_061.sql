WITH AKI_Admissions AS (
    -- Step 1: Identify admissions with AKI and classify as primary or secondary
    SELECT
        dia.subject_id,
        dia.hadm_id,
        -- Find the minimum sequence number for any AKI diagnosis to determine primary vs secondary precedence
        MIN(CASE
                WHEN dia.icd_version = 9 AND dia.icd_code LIKE '584%' THEN dia.seq_num
                WHEN dia.icd_version = 10 AND dia.icd_code LIKE 'N17%' THEN dia.seq_num
                ELSE NULL
            END) AS min_aki_seq_num
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dia
    WHERE
        (dia.icd_version = 9 AND dia.icd_code LIKE '584%') OR
        (dia.icd_version = 10 AND dia.icd_code LIKE 'N17%')
    GROUP BY
        dia.subject_id, dia.hadm_id
),
Filtered_Patient_Admissions AS (
    -- Step 2: Filter patients by demographic, LOS, and AKI type
    SELECT
        ad.subject_id,
        ad.hadm_id,
        p.gender,
        p.anchor_age,
        -- Calculate hospital length of stay in days, adjusting to clinical standard (e.g., same-day admit/discharge = 1 day)
        (DATE_DIFF(DATE(ad.dischtime), DATE(ad.admittime), DAY) + 1) AS los_adjusted_days,
        CASE
            WHEN akia.min_aki_seq_num = 1 THEN 'Primary AKI'
            ELSE 'Secondary AKI'
        END AS aki_diagnosis_type,
        CASE
            WHEN (DATE_DIFF(DATE(ad.dischtime), DATE(ad.admittime), DAY) + 1) BETWEEN 1 AND 3 THEN 'LOS_1-3_days'
            WHEN (DATE_DIFF(DATE(ad.admittime), DATE(ad.admittime), DAY) + 1) BETWEEN 4 AND 7 THEN 'LOS_4-7_days'
            ELSE NULL
        END AS los_group
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ad.subject_id = p.subject_id
    INNER JOIN
        AKI_Admissions akia
        ON ad.subject_id = akia.subject_id AND ad.hadm_id = akia.hadm_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 64 AND 74
        -- Ensure LOS is within the specified 1-7 days range, covering both 1-3 and 4-7 day groups
        AND (DATE_DIFF(DATE(ad.dischtime), DATE(ad.admittime), DAY) + 1) BETWEEN 1 AND 7
),
Imaging_Counts AS (
    -- Step 3: Count diagnostic imaging studies per admission
    SELECT
        hcp.hadm_id,
        COUNT(hcp.hcpcs_cd) AS num_imaging_studies
    FROM
        `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hcp
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dhcp
        ON hcp.hcpcs_cd = dhcp.code
    WHERE
        -- Extensive keyword filters for common diagnostic imaging procedures
        LOWER(dhcp.short_description) LIKE '%x-ray%' OR
        LOWER(dhcp.short_description) LIKE '%ct scan%' OR
        LOWER(dhcp.short_description) LIKE '%mri%' OR
        LOWER(dhcp.short_description) LIKE '%ultrasound%' OR
        LOWER(dhcp.short_description) LIKE '%pet scan%' OR
        LOWER(dhcp.short_description) LIKE '%radiograph%' OR
        LOWER(dhcp.short_description) LIKE '%angiography%' OR
        LOWER(dhcp.short_description) LIKE '%fluoroscopy%' OR
        LOWER(dhcp.short_description) LIKE '%echocardiogram%' OR -- Added more specific term
        LOWER(dhcp.short_description) LIKE '%doppler%' -- Added Doppler studies
    GROUP BY
        hcp.hadm_id
)
-- Final Step: Join filtered admissions with imaging counts and calculate median (IQR)
SELECT
    fpa.aki_diagnosis_type,
    fpa.los_group,
    -- Calculate median of imaging studies per admission
    APPROX_QUANTILES(COALESCE(img.num_imaging_studies, 0), 2)[OFFSET(1)] AS median_imaging_studies,
    -- Calculate Q1 (25th percentile) for IQR
    APPROX_QUANTILES(COALESCE(img.num_imaging_studies, 0), 4)[OFFSET(1)] AS q1_imaging_studies,
    -- Calculate Q3 (75th percentile) for IQR
    APPROX_QUANTILES(COALESCE(img.num_imaging_studies, 0), 4)[OFFSET(3)] AS q3_imaging_studies
FROM
    Filtered_Patient_Admissions fpa
LEFT JOIN
    Imaging_Counts img
    ON fpa.hadm_id = img.hadm_id
WHERE
    fpa.los_group IS NOT NULL -- Ensures only admissions in the 1-3 or 4-7 day LOS groups are included
GROUP BY
    fpa.aki_diagnosis_type,
    fpa.los_group
ORDER BY
    fpa.aki_diagnosis_type,
    fpa.los_group;