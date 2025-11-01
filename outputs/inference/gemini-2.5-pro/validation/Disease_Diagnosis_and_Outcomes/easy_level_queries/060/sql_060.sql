WITH
-- Step 1: Identify a comprehensive set of ICD codes for Upper GI Bleed (UGIB)
ugib_codes AS (
    SELECT DISTINCT icd_code, icd_version
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE
    -- ICD-9 UGIB codes
    (icd_version = 9 AND (
        icd_code LIKE '531.0%' OR -- Gastric ulcer with hemorrhage
        icd_code LIKE '531.2%' OR -- Gastric ulcer with perforation and hemorrhage
        icd_code LIKE '531.4%' OR -- Chronic gastric ulcer with hemorrhage
        icd_code LIKE '531.6%' OR -- Chronic gastric ulcer with perforation and hemorrhage
        icd_code LIKE '532.0%' OR -- Duodenal ulcer with hemorrhage
        icd_code LIKE '532.2%' OR -- Duodenal ulcer with perforation and hemorrhage
        icd_code LIKE '532.4%' OR -- Chronic duodenal ulcer with hemorrhage
        icd_code LIKE '532.6%' OR -- Chronic duodenal ulcer with perforation and hemorrhage
        icd_code LIKE '533.0%' OR -- Peptic ulcer with hemorrhage
        icd_code LIKE '533.2%' OR -- Peptic ulcer with perforation and hemorrhage
        icd_code LIKE '533.4%' OR -- Chronic peptic ulcer with hemorrhage
        icd_code LIKE '533.6%' OR -- Chronic peptic ulcer with perforation and hemorrhage
        icd_code LIKE '534.0%' OR -- Gastrojejunal ulcer with hemorrhage
        icd_code LIKE '534.2%' OR -- Gastrojejunal ulcer with perforation and hemorrhage
        icd_code LIKE '534.4%' OR -- Chronic gastrojejunal ulcer with hemorrhage
        icd_code LIKE '534.6%' OR -- Chronic gastrojejunal ulcer with perforation and hemorrhage
        icd_code = '578.0'    OR -- Hematemesis
        icd_code = '578.1'    OR -- Melena
        icd_code = '578.9'       -- Hemorrhage of gastrointestinal tract, unspecified
    ))
    OR
    -- ICD-10 UGIB codes
    (icd_version = 10 AND (
        icd_code IN (
            'K25.0', 'K25.2', 'K25.4', 'K25.6', -- Gastric ulcer with hemorrhage/perforation
            'K26.0', 'K26.2', 'K26.4', 'K26.6', -- Duodenal ulcer with hemorrhage/perforation
            'K27.0', 'K27.2', 'K27.4', 'K27.6', -- Peptic ulcer with hemorrhage/perforation
            'K28.0', 'K28.2', 'K28.4', 'K28.6', -- Gastrojejunal ulcer with hemorrhage/perforation
            'K29.01', -- Acute gastritis with bleeding
            'K92.0',  -- Hematemesis
            'K92.1',  -- Melena
            'K92.2'   -- Gastrointestinal hemorrhage, unspecified
        ) OR
        icd_code LIKE 'I85.01%' -- Esophageal varices with bleeding
    ))
),

-- Step 2: Find hospital admissions with a "primary" diagnosis of UGIB
-- "Primary" is interpreted as being one of the first two diagnoses listed (seq_num <= 2)
ugib_admissions AS (
    SELECT DISTINCT dx.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    INNER JOIN ugib_codes AS uc
        ON dx.icd_code = uc.icd_code AND dx.icd_version = uc.icd_version
    WHERE
        dx.seq_num <= 2
),

-- Step 3: Combine filters for demographics and diagnosis, and calculate LOS
final_cohort_los AS (
    SELECT
        -- Calculate hospital length of stay in fractional days
        DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS a
        ON p.subject_id = a.subject_id
    INNER JOIN
        ugib_admissions AS ua
        ON a.hadm_id = ua.hadm_id
    WHERE
        -- Filter for males
        p.gender = 'M'
        -- Calculate age at admission and filter for the 74-84 range
        AND (DATETIME_DIFF(a.admittime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) + p.anchor_age) BETWEEN 74 AND 84
)

-- Step 4: Calculate the 25th percentile of the LOS for the final cohort
SELECT
    APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS los_25th_percentile_days
FROM
    final_cohort_los
WHERE
    los_days IS NOT NULL AND los_days > 0;