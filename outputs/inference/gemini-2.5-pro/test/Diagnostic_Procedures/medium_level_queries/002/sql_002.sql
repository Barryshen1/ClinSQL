WITH
-- 1. Identify all unique hospital admissions for TIA
tia_hadm AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (icd_code LIKE '435%' AND icd_version = 9) -- TIA ICD-9
        OR (icd_code LIKE 'G45%' AND icd_version = 10) -- TIA ICD-10
),

-- 2. Define the patient cohort: Male, 64-74, TIA, hospital LOS 1-7 days
cohort AS (
    SELECT
        a.hadm_id,
        DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    -- Join to patients to filter by gender and age
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON a.subject_id = p.subject_id
    -- Inner join to keep only TIA admissions
    JOIN tia_hadm
        ON a.hadm_id = tia_hadm.hadm_id
    WHERE
        p.gender = 'M'
        -- Calculate age at admission and filter
        AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 64 AND 74
        -- Filter by hospital length of stay
        AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),

-- 3. Find relevant procedures from ICD codes
icd_procs AS (
    SELECT
        p.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d
        ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
    WHERE
        LOWER(d.long_title) LIKE '%ultrasound%'
        OR LOWER(d.long_title) LIKE '%echocardiography%'
),

-- 4. Find relevant procedures from HCPCS codes
hcpcs_procs AS (
    SELECT
        h.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` AS h
    JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` AS d
        ON h.hcpcs_cd = d.code
    WHERE
        LOWER(d.long_description) LIKE '%echocardiogram%'
        OR LOWER(d.long_description) LIKE '%ultrasound%'
        OR LOWER(d.long_description) LIKE '%doppler%'
),

-- 5. Combine all procedure events and count per admission
procedure_counts AS (
    SELECT
        hadm_id,
        COUNT(*) AS procedure_count
    FROM (
        SELECT hadm_id FROM icd_procs
        UNION ALL
        SELECT hadm_id FROM hcpcs_procs
    ) AS all_procedures
    GROUP BY hadm_id
),

-- 6. Identify admissions that included an ICU stay
icu_admissions AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
)

-- 7. Final aggregation: join cohort with procedures and ICU status, then stratify and average
SELECT
    CASE
        WHEN c.hospital_los BETWEEN 1 AND 3 THEN '1-3 days'
        WHEN c.hospital_los BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_group,
    CASE
        WHEN i.hadm_id IS NOT NULL THEN 'Yes'
        ELSE 'No'
    END AS hadm_with_icu_stay,
    AVG(COALESCE(p.procedure_count, 0)) AS mean_procedure_count
FROM cohort AS c
LEFT JOIN procedure_counts AS p
    ON c.hadm_id = p.hadm_id
LEFT JOIN icu_admissions AS i
    ON c.hadm_id = i.hadm_id
GROUP BY
    los_group,
    hadm_with_icu_stay
ORDER BY
    los_group,
    hadm_with_icu_stay;