WITH 
-- Get admissions for women 80-90
filtered_admissions AS (
    SELECT 
        a.hadm_id,
        p.gender,
        -- Compute age at admission
        p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE p.gender = 'F'
        AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 80 AND 90
),
-- Filter for hemorrhagic stroke diagnoses
stroke_admissions AS (
    SELECT 
        fa.hadm_id
    FROM filtered_admissions fa
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON fa.hadm_id = di.hadm_id
    WHERE 
        (di.icd_version = 9 AND di.icd_code IN ('430','431','432'))
        OR 
        (di.icd_version = 10 AND (di.icd_code LIKE 'I60%' OR di.icd_code LIKE 'I61%' OR di.icd_code LIKE 'I62%'))
    GROUP BY fa.hadm_id
),
-- Count ultrasound procedures per admission
ultrasound_counts AS (
    SELECT 
        h.hadm_id,
        COUNT(*) AS ultrasound_count
    FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
        ON h.hcpcs_cd = d.code
    WHERE LOWER(d.long_description) LIKE '%ultrasound%'
    GROUP BY h.hadm_id
),
-- Get ICU stay information for these admissions
icu_stays AS (
    SELECT 
        i.hadm_id,
        i.los,
        CASE WHEN i.los >= 1 AND i.los < 5 THEN 1 ELSE 0 END AS is_short_stay,
        CASE WHEN i.los >= 5 AND i.los <= 7 THEN 1 ELSE 0 END AS is_medium_stay
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    WHERE i.hadm_id IN (SELECT hadm_id FROM stroke_admissions)
),
-- Aggregate ICU stay flags per admission
admission_groups AS (
    SELECT 
        hadm_id,
        MAX(is_short_stay) AS has_short_stay,
        MAX(is_medium_stay) AS has_medium_stay
    FROM icu_stays
    GROUP BY hadm_id
),
-- Combine with ultrasound counts
base_data AS (
    SELECT 
        ag.hadm_id,
        COALESCE(uc.ultrasound_count, 0) AS ultrasound_count,
        ag.has_short_stay,
        ag.has_medium_stay
    FROM admission_groups ag
    LEFT JOIN ultrasound_counts uc
        ON ag.hadm_id = uc.hadm_id
)

-- Calculate statistics for each group
SELECT 
    '1-4 days' AS stay_group,
    AVG(ultrasound_count) AS mean_ultrasound,
    MIN(ultrasound_count) AS min_ultrasound,
    MAX(ultrasound_count) AS max_ultrasound
FROM base_data
WHERE has_short_stay = 1
UNION ALL
SELECT 
    '5-7 days' AS stay_group,
    AVG(ultrasound_count) AS mean_ultrasound,
    MIN(ultrasound_count) AS min_ultrasound,
    MAX(ultrasound_count) AS max_ultrasound
FROM base_data
WHERE has_medium_stay = 1;