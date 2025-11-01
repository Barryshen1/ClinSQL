WITH TIA_Admissions_Cohort AS (
    -- Defines the cohort of TIA admissions for male patients aged 90+
    SELECT DISTINCT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.subject_id = diag.subject_id
        AND adm.hadm_id = diag.hadm_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age = 91 -- Represents patients >= 90 years old in MIMIC-IV
        AND (
            (diag.icd_version = 9 AND diag.icd_code LIKE '435%') -- ICD-9 codes for Transient Ischemic Attack
            OR
            (diag.icd_version = 10 AND diag.icd_code LIKE 'G45%') -- ICD-10 codes for Transient Ischemic Attack
        )
),
Imaging_Procedures_Per_Admission AS (
    -- Counts diagnostic imaging procedures for each admission in the TIA cohort
    SELECT
        tac.subject_id,
        tac.hadm_id,
        COUNT(proc.icd_code) AS num_imaging_procedures
    FROM
        TIA_Admissions_Cohort tac -- Reference the CTE defined above
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
        ON tac.subject_id = proc.subject_id
        AND tac.hadm_id = proc.hadm_id
    WHERE
        (
            (proc.icd_version = 9 AND (proc.icd_code LIKE '87%' OR proc.icd_code LIKE '88%')) -- ICD-9 codes for Diagnostic Radiology (87) and Other Diagnostic Imaging (88)
            OR
            (proc.icd_version = 10 AND proc.icd_code LIKE 'B%') -- ICD-10-PCS codes for Imaging section
        )
    GROUP BY
        tac.subject_id, tac.hadm_id
)
-- Final aggregation to calculate mean, min, max based on stay duration
SELECT
    CASE
        WHEN DATE_DIFF(tac.dischtime, tac.admittime, DAY) >= 1 AND DATE_DIFF(tac.dischtime, tac.admittime, DAY) <= 3 THEN '1-3 day stay'
        WHEN DATE_DIFF(tac.dischtime, tac.admittime, DAY) >= 4 AND DATE_DIFF(tac.dischtime, tac.admittime, DAY) <= 7 THEN '4-7 day stay'
    END AS stay_duration_category,
    AVG(COALESCE(ippa.num_imaging_procedures, 0)) AS mean_imaging_procedures_per_admission,
    MIN(COALESCE(ippa.num_imaging_procedures, 0)) AS min_imaging_procedures_per_admission,
    MAX(COALESCE(ippa.num_imaging_procedures, 0)) AS max_imaging_procedures_per_admission
FROM
    TIA_Admissions_Cohort tac
LEFT JOIN
    Imaging_Procedures_Per_Admission ippa
    ON tac.subject_id = ippa.subject_id
    AND tac.hadm_id = ippa.hadm_id
WHERE
    -- Filter for stays between 1 and 7 days (inclusive for both ends)
    DATE_DIFF(tac.dischtime, tac.admittime, DAY) >= 1
    AND DATE_DIFF(tac.dischtime, tac.admittime, DAY) <= 7
GROUP BY
    stay_duration_category
ORDER BY
    stay_duration_category;