WITH PatientAdmissionCohort AS (
    -- CTE 1: Filter admissions based on demographics and primary diagnosis
    SELECT
        ad.subject_id,
        ad.hadm_id,
        DATETIME_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days,
        CASE
            -- Check if *any* ICU stay exists for this hadm_id using an EXISTS subquery
            WHEN EXISTS (SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` icu WHERE icu.hadm_id = ad.hadm_id) THEN 'With ICU Stay'
            ELSE 'Without ICU Stay'
        END AS icu_use_status
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pa
        ON ad.subject_id = pa.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
        ON ad.hadm_id = di.hadm_id AND ad.subject_id = di.subject_id
    WHERE
        pa.gender = 'M'
        AND pa.anchor_age BETWEEN 49 AND 59 -- Filter for age 49-59
        AND di.seq_num = 1 -- Primary diagnosis
        AND (di.icd_code LIKE 'I50%' OR di.icd_code LIKE '428%') -- Heart Failure ICD-10 (I50) or ICD-9 (428)
),
CTMRICodes AS (
    -- CTE 2: Identify CT/MRI procedure codes
    SELECT DISTINCT
        p.icd_code,
        p.icd_version
    FROM
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS p
    WHERE
        (LOWER(p.long_title) LIKE '%ct scan%' OR LOWER(p.long_title) LIKE '%computed tomography%')
        OR (LOWER(p.long_title) LIKE '%mri%' OR LOWER(p.long_title) LIKE '%magnetic resonance imaging%')
),
AdmissionCTMRICounts AS (
    -- CTE 3: Count CT/MRI procedures for each admission
    SELECT
        pr.hadm_id,
        COUNT(pr.icd_code) AS ct_mri_count -- Count instances of CT/MRI procedures for this admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pr
    INNER JOIN
        CTMRICodes AS ctc
        ON pr.icd_code = ctc.icd_code AND pr.icd_version = ctc.icd_version
    GROUP BY
        pr.hadm_id
)
SELECT
    CASE
        WHEN pac.los_days BETWEEN 1 AND 4 THEN 'LOS 1-4 Days'
        WHEN pac.los_days BETWEEN 5 AND 7 THEN 'LOS 5-7 Days'
        -- Ensure all relevant LOS are covered by the CASE statement, though WHERE clause also filters.
        ELSE 'Undefined LOS Group' -- Should not be reached with the WHERE clause below.
    END AS los_group,
    pac.icu_use_status,
    COUNT(DISTINCT pac.hadm_id) AS admission_count,
    AVG(COALESCE(actmri.ct_mri_count, 0)) AS mean_ct_mri_per_admission
FROM
    PatientAdmissionCohort AS pac
LEFT JOIN
    AdmissionCTMRICounts AS actmri
    ON pac.hadm_id = actmri.hadm_id
WHERE
    pac.los_days BETWEEN 1 AND 7 -- Filter for the specified LOS ranges (1-4 days and 5-7 days)
GROUP BY
    los_group,
    pac.icu_use_status
ORDER BY
    los_group,
    pac.icu_use_status;