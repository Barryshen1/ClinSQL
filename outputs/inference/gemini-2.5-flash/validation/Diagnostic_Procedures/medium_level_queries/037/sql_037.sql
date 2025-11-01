WITH admissions_ami_age_filtered AS (
    -- Step 1: Filter admissions for males aged 43-53 with at least one AMI diagnosis
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS duration_days,
        (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) AS admission_age,
        -- Determine if there is any AMI diagnosis, and if so, whether a primary AMI diagnosis exists
        MAX(CASE
            WHEN (diag.icd_version = 9 AND SUBSTR(diag.icd_code, 1, 3) = '410')
                OR (diag.icd_version = 10 AND SUBSTR(diag.icd_code, 1, 3) IN ('I21', 'I22'))
            THEN 1 ELSE 0
        END) AS has_ami,
        -- Use MAX() with string comparison: 'Primary' > 'Secondary' to prioritize primary diagnosis if present
        MAX(CASE
            WHEN (diag.seq_num = 1) AND
                 ((diag.icd_version = 9 AND SUBSTR(diag.icd_code, 1, 3) = '410')
                 OR (diag.icd_version = 10 AND SUBSTR(diag.icd_code, 1, 3) IN ('I21', 'I22')))
            THEN 'Primary AMI'
            WHEN ((diag.icd_version = 9 AND SUBSTR(diag.icd_code, 1, 3) = '410')
                 OR (diag.icd_version = 10 AND SUBSTR(diag.icd_code, 1, 3) IN ('I21', 'I22')))
            THEN 'Secondary AMI' -- Any AMI diagnosis which is not primary
            ELSE NULL
        END) AS ami_diagnosis_category
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
        ON adm.subject_id = diag.subject_id AND adm.hadm_id = diag.hadm_id
    WHERE
        pat.gender = 'M'
        AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 43 AND 53
    GROUP BY
        adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime, pat.anchor_age, pat.anchor_year
    HAVING
        MAX(CASE
            WHEN (diag.icd_version = 9 AND SUBSTR(diag.icd_code, 1, 3) = '410')
                OR (diag.icd_version = 10 AND SUBSTR(diag.icd_code, 1, 3) IN ('I21', 'I22'))
            THEN 1 ELSE 0
        END) = 1 -- Ensure the admission has at least one AMI diagnosis
),
radiography_ct_procedures AS (
    -- Step 2: Identify and count radiography/CT procedures per admission
    SELECT
        px.subject_id,
        px.hadm_id,
        COUNT(px.icd_code) AS ct_radiography_count
    FROM
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS px
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d_px
        ON px.icd_code = d_px.icd_code AND px.icd_version = d_px.icd_version
    WHERE
        LOWER(d_px.long_title) LIKE '%ct scan%'
        OR LOWER(d_px.long_title) LIKE '%computed tomograph%'
        OR LOWER(d_px.long_title) LIKE '%radiograph%'
        OR LOWER(d_px.long_title) LIKE '%x-ray%'
    GROUP BY
        px.subject_id, px.hadm_id
),
final_cohort AS (
    -- Step 3: Combine filtered admissions with procedure counts and categorize stay duration
    SELECT
        ami.subject_id,
        ami.hadm_id,
        ami.ami_diagnosis_category,
        CASE
            WHEN ami.duration_days >= 1 AND ami.duration_days <= 3 THEN '1-3 Day Stay'
            WHEN ami.duration_days >= 4 AND ami.duration_days <= 7 THEN '4-7 Day Stay'
            ELSE 'Other Stay Duration' -- Admissions outside the 1-7 day range will be filtered later
        END AS stay_duration_category,
        COALESCE(rad_ct.ct_radiography_count, 0) AS ct_radiography_count -- Assign 0 if no procedures found
    FROM
        admissions_ami_age_filtered AS ami
    LEFT JOIN
        radiography_ct_procedures AS rad_ct
        ON ami.subject_id = rad_ct.subject_id AND ami.hadm_id = rad_ct.hadm_id
    WHERE
        ami.duration_days >= 1 AND ami.duration_days <= 7 -- Filter for relevant stay durations
)
-- Step 4: Calculate median and IQR for each stratum
SELECT
    ami_diagnosis_category,
    stay_duration_category,
    COUNT(DISTINCT hadm_id) AS total_admissions,
    APPROX_QUANTILES(ct_radiography_count, 100)[OFFSET(50)] AS median_radiography_ct, -- Median (50th percentile)
    APPROX_QUANTILES(ct_radiography_count, 100)[OFFSET(75)] - APPROX_QUANTILES(ct_radiography_count, 100)[OFFSET(25)] AS iqr_radiography_ct -- IQR (75th percentile - 25th percentile)
FROM
    final_cohort
WHERE
    stay_duration_category IN ('1-3 Day Stay', '4-7 Day Stay') -- Ensure only the requested stay duration categories are included
GROUP BY
    ami_diagnosis_category,
    stay_duration_category
ORDER BY
    ami_diagnosis_category,
    stay_duration_category;