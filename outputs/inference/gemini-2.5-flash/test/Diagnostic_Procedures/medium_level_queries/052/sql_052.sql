WITH AdmissionsFiltered AS (
    SELECT
        ad.subject_id,
        ad.hadm_id,
        DATE_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days,
        CASE
            WHEN ad.admission_type IN ('EMERGENCY', 'URGENT', 'TRAUMA', 'OBSERVATION THROUGH ED') THEN 'ED'
            WHEN ad.admission_type = 'ELECTIVE' THEN 'Elective'
            ELSE 'Other_Admission_Type' -- Categorize other types or filter them out if not relevant
        END AS admission_type_group,
        CASE
            WHEN DATE_DIFF(ad.dischtime, ad.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 Days'
            WHEN DATE_DIFF(ad.dischtime, ad.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 Days'
            ELSE NULL -- Filter these out later if not within 1-7 days
        END AS stay_duration_group
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON ad.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 73 AND 83
        -- Only consider admissions relevant to the requested LOS and Admission Types
        AND DATE_DIFF(ad.dischtime, ad.admittime, DAY) BETWEEN 1 AND 7
        AND (ad.admission_type IN ('EMERGENCY', 'URGENT', 'TRAUMA', 'OBSERVATION THROUGH ED') OR ad.admission_type = 'ELECTIVE')
),
UltrasoundProceduresCount AS (
    SELECT
        proc.subject_id,
        proc.hadm_id,
        COUNT(proc.icd_code) AS num_ultrasounds
    FROM
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
    WHERE
        -- ICD-9 codes for Diagnostic Ultrasound (including echocardiography)
        (proc.icd_version = 9 AND proc.icd_code LIKE '88.7%')
        OR
        -- ICD-10 codes for Diagnostic Ultrasound (including echocardiography)
        (proc.icd_version = 10 AND proc.icd_code LIKE 'B_4%')
    GROUP BY
        proc.subject_id,
        proc.hadm_id
)
SELECT
    af.admission_type_group,
    af.stay_duration_group,
    COUNT(DISTINCT af.hadm_id) AS num_admissions, -- For context, count the unique admissions in each group
    IFNULL(ROUND(AVG(upc.num_ultrasounds), 2), 0.00) AS mean_ultrasounds_per_admission,
    IFNULL(MIN(upc.num_ultrasounds), 0) AS min_ultrasounds_per_admission,
    IFNULL(MAX(upc.num_ultrasounds), 0) AS max_ultrasounds_per_admission
FROM
    AdmissionsFiltered AS af
LEFT JOIN -- Use LEFT JOIN to include admissions with 0 ultrasounds
    UltrasoundProceduresCount AS upc
    ON af.subject_id = upc.subject_id AND af.hadm_id = upc.hadm_id
WHERE
    af.stay_duration_group IS NOT NULL -- Ensure only '1-3 Days' or '4-7 Days' are considered
GROUP BY
    af.admission_type_group,
    af.stay_duration_group
ORDER BY
    af.admission_type_group,
    af.stay_duration_group;