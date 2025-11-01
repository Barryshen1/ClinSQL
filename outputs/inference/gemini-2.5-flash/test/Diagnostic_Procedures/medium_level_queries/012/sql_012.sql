WITH PatientAdmissions AS (
    -- Step 1: Filter for relevant demographics and admissions
    SELECT
        adm.subject_id,
        adm.hadm_id,
        pat.gender,
        EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age AS age_at_admission,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'M'
        AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 35 AND 45
        AND DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 7
),
ACS_Admissions AS (
    -- Step 2: Identify Acute Coronary Syndrome (ACS) admissions
    SELECT DISTINCT -- Use DISTINCT here to ensure each hadm_id is only represented once
        pa.subject_id,
        pa.hadm_id,
        pa.los_days,
        CASE
            WHEN pa.los_days BETWEEN 1 AND 3 THEN '1-3 days'
            WHEN pa.los_days BETWEEN 4 AND 7 THEN '4-7 days'
            ELSE 'Other' -- Should not be reached due to initial LOS filter
        END AS los_category
    FROM
        PatientAdmissions AS pa
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
        ON pa.hadm_id = di.hadm_id
    WHERE
        -- Filter for ACS ICD codes (ICD-10 and ICD-9)
        (
            di.icd_version = 10 AND (
                di.icd_code LIKE 'I20%' OR -- Angina Pectoris
                di.icd_code LIKE 'I21%' OR -- Acute myocardial infarction
                di.icd_code LIKE 'I24%'    -- Other acute ischemic heart diseases
            )
        ) OR (
            di.icd_version = 9 AND (
                di.icd_code LIKE '410%' OR -- Acute myocardial infarction
                di.icd_code LIKE '411%' OR -- Other acute and subacute forms of ischemic heart disease
                di.icd_code LIKE '413%'    -- Angina pectoris
            )
        )
),
UltrasoundProceduresPerAdmission AS (
    -- Step 3: Count ultrasound procedures for each identified ACS admission
    SELECT
        sa.subject_id,
        sa.hadm_id,
        sa.los_category,
        COUNT(proc_filtered.icd_code) AS num_ultrasounds_per_admission
    FROM
        ACS_Admissions AS sa
    LEFT JOIN (
        SELECT
            hadm_id,
            icd_code,
            icd_version
        FROM
            `physionet-data.mimiciv_3_1_hosp.procedures_icd`
        WHERE
            -- Filter for ultrasound/echocardiography ICD codes (ICD-10-PCS and ICD-9-CM)
            (
                icd_version = 10 AND (
                    icd_code LIKE 'B40%' OR -- Diagnostic Ultrasonography Heart and Great Vessels
                    icd_code LIKE '0UJC%'   -- Measurement of Cardiac Output (includes Transthoracic Echocardiography)
                )
            ) OR (
                icd_version = 9 AND icd_code = '88.72' -- Diagnostic ultrasound of heart
            )
    ) AS proc_filtered
    ON sa.hadm_id = proc_filtered.hadm_id
    GROUP BY
        sa.subject_id,
        sa.hadm_id,
        sa.los_category
)
-- Step 4: Aggregate results by LOS category
SELECT
    uppa.los_category,
    COUNT(DISTINCT uppa.subject_id) AS patient_count,
    COUNT(DISTINCT uppa.hadm_id) AS admission_count,
    SAFE_DIVIDE(SUM(uppa.num_ultrasounds_per_admission), COUNT(DISTINCT uppa.hadm_id)) AS mean_ultrasounds_per_admission
FROM
    UltrasoundProceduresPerAdmission AS uppa
GROUP BY
    uppa.los_category
ORDER BY
    uppa.los_category;