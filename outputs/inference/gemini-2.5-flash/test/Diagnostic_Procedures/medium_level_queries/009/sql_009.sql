WITH TargetAdmissions AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        -- Calculate LOS in days
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_raw_days,
        CASE
            WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4 days'
            WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 5 AND 7 THEN '5-7 days'
            ELSE NULL -- Admissions outside this range are filtered out by the outer WHERE clause
        END AS los_category,
        -- Determine if the admission involved an ICU stay
        CASE
            WHEN EXISTS (SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` icu_sub WHERE icu_sub.hadm_id = adm.hadm_id) THEN 'ICU Stay'
            ELSE 'No ICU Stay'
        END AS icu_status
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'F'
        -- Calculate age at admission to ensure it's between 44 and 54
        AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 44 AND 54
        -- Filter LOS to the relevant range (1 to 7 days)
        AND DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 7
        -- Check for TIA diagnosis (ICD-9 435.x or ICD-10 G45.x)
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
            WHERE
                diag.hadm_id = adm.hadm_id
                AND (
                    (diag.icd_version = 9 AND STARTS_WITH(diag.icd_code, '435')) -- ICD-9 TIA codes
                    OR (diag.icd_version = 10 AND STARTS_WITH(diag.icd_code, 'G45')) -- ICD-10 TIA codes
                )
        )
),
ImagingProcedures AS (
    -- Count diagnostic imaging procedures for each admission
    SELECT
        px.hadm_id,
        COUNT(*) AS imaging_count
    FROM
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` px
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d_px
        ON px.icd_code = d_px.icd_code AND px.icd_version = d_px.icd_version
    WHERE
        -- Filter for common diagnostic imaging keywords in the long title
        LOWER(d_px.long_title) LIKE '%ct%'
        OR LOWER(d_px.long_title) LIKE '%computed tomography%'
        OR LOWER(d_px.long_title) LIKE '%mri%'
        OR LOWER(d_px.long_title) LIKE '%magnetic resonance%'
        OR LOWER(d_px.long_title) LIKE '%ultrasound%'
        OR LOWER(d_px.long_title) LIKE '%echocardiography%'
        OR LOWER(d_px.long_title) LIKE '%radiograph%'
        OR LOWER(d_px.long_title) LIKE '%angiography%'
    GROUP BY
        px.hadm_id
)
-- Final query to calculate percentiles of imaging counts per admission,
-- grouped by LOS category and ICU status
SELECT
    ta.los_category,
    ta.icu_status,
    -- Calculate 25th, 50th (median), and 75th percentiles
    PERCENTILE_CONT(COALESCE(ip.imaging_count, 0), 0.25) OVER (PARTITION BY ta.los_category, ta.icu_status) AS p25_imaging_count,
    PERCENTILE_CONT(COALESCE(ip.imaging_count, 0), 0.50) OVER (PARTITION BY ta.los_category, ta.icu_status) AS p50_imaging_count,
    PERCENTILE_CONT(COALESCE(ip.imaging_count, 0), 0.75) OVER (PARTITION BY ta.los_category, ta.icu_status) AS p75_imaging_count
FROM
    TargetAdmissions ta
LEFT JOIN
    ImagingProcedures ip
    ON ta.hadm_id = ip.hadm_id
-- Use QUALIFY to select only one row per partition, as the percentile function duplicates results
QUALIFY ROW_NUMBER() OVER (PARTITION BY ta.los_category, ta.icu_status ORDER BY 1) = 1
ORDER BY
    ta.los_category,
    ta.icu_status;