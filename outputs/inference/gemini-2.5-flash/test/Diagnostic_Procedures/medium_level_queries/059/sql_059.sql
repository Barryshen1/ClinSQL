WITH Admissions_Cohort AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        pat.gender,
        pat.anchor_age,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 67 AND 77
        AND DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 7 -- Filter for LOS 1-7 days
),
-- Identify all Heart Failure ICD-10 diagnoses
Heart_Failure_Diagnoses AS (
    SELECT
        d.subject_id,
        d.hadm_id,
        d.seq_num
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    WHERE
        d.icd_version = 10 -- Assuming ICD-10 for HF codes
        AND d.icd_code LIKE 'I50%' -- ICD-10 code for heart failure
),
-- Classify each admission in the cohort as Primary HF or Secondary HF
Admission_HF_Type AS (
    SELECT
        ac.subject_id,
        ac.hadm_id,
        ac.los_days,
        CASE
            WHEN MAX(CASE WHEN hfd.seq_num = 1 THEN 1 ELSE 0 END) = 1 THEN 'Primary HF'
            WHEN MAX(CASE WHEN hfd.seq_num > 1 THEN 1 ELSE 0 END) = 1 THEN 'Secondary HF'
            ELSE NULL -- Exclude admissions without 'I50%' diagnoses or not fitting criteria
        END AS hf_type
    FROM
        Admissions_Cohort AS ac
    INNER JOIN
        Heart_Failure_Diagnoses AS hfd
        ON ac.subject_id = hfd.subject_id AND ac.hadm_id = hfd.hadm_id
    GROUP BY
        ac.subject_id, ac.hadm_id, ac.los_days
    HAVING
        hf_type IS NOT NULL
),
-- Count imaging procedures per admission for the cohort
Imaging_Counts AS (
    SELECT
        proc.subject_id,
        proc.hadm_id,
        COUNT(*) AS num_imaging_studies
    FROM
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
    WHERE
        proc.icd_version = 10
        AND proc.icd_code LIKE 'B%' -- ICD-10-PCS range for Diagnostic Imaging procedures
    GROUP BY
        proc.subject_id, proc.hadm_id
),
-- Combine HF type, LOS, and imaging counts
Combined_Data AS (
    SELECT
        ahft.subject_id,
        ahft.hadm_id,
        ahft.los_days,
        ahft.hf_type,
        CASE
            WHEN ahft.los_days BETWEEN 1 AND 4 THEN '1-4 days'
            WHEN ahft.los_days BETWEEN 5 AND 7 THEN '5-7 days'
            ELSE NULL -- Should not happen due to initial filter in Admissions_Cohort
        END AS los_category,
        COALESCE(ic.num_imaging_studies, 0) AS num_imaging_studies -- Handle cases with no imaging
    FROM
        Admission_HF_Type AS ahft
    LEFT JOIN
        Imaging_Counts AS ic
        ON ahft.subject_id = ic.subject_id AND ahft.hadm_id = ic.hadm_id
)
-- Calculate percentiles of imaging studies
SELECT
    cd.los_category,
    cd.hf_type,
    CAST(PERCENTILE_CONT(cd.num_imaging_studies, 0.25) AS INT64) AS p25_imaging_studies,
    CAST(PERCENTILE_CONT(cd.num_imaging_studies, 0.50) AS INT64) AS p50_imaging_studies,
    CAST(PERCENTILE_CONT(cd.num_imaging_studies, 0.75) AS INT64) AS p75_imaging_studies
FROM
    Combined_Data AS cd
WHERE
    cd.los_category IS NOT NULL -- Ensure only desired LOS categories are included
GROUP BY
    cd.los_category,
    cd.hf_type
ORDER BY
    cd.los_category,
    cd.hf_type;