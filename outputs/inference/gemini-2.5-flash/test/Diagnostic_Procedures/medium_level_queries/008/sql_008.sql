WITH PatientDemographics AS (
    -- Select patients within the specified age and gender range, calculate LOS
    SELECT
        p.subject_id,
        adm.hadm_id,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 58 AND 68
        -- Filter admissions with LOS between 1 and 7 days as requested by the question segments
        AND DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 7
),
HHS_Admissions AS (
    -- Filter admissions for Hyperosmolar Hyperglycemic State (HHS) diagnostic codes
    SELECT DISTINCT
        pd.subject_id,
        pd.hadm_id,
        pd.los_days
    FROM
        PatientDemographics pd
    JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON pd.hadm_id = di.hadm_id
    WHERE
        (di.icd_version = 9 AND di.icd_code LIKE '250.2%') -- ICD-9 codes for diabetes with hyperosmolarity
        OR (di.icd_version = 10 AND (di.icd_code LIKE 'E11.0%' OR di.icd_code LIKE 'E13.0%')) -- ICD-10 codes for DM with hyperosmolarity
),
RadiographyCT_Procedures AS (
    -- Count radiography/CT procedures per admission
    SELECT
        pr.hadm_id,
        COUNT(pr.icd_code) AS num_radiography_ct_procedures
    FROM
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
        ON pr.icd_code = dip.icd_code AND pr.icd_version = dip.icd_version
    WHERE
        LOWER(dip.long_title) LIKE '%radiograph%'              -- Covers various radiography types
        OR LOWER(dip.long_title) LIKE '%computed tomography%' -- Covers full term for CT
        OR LOWER(dip.long_title) LIKE '%ct scan%'             -- Covers common abbreviation for CT
    GROUP BY
        pr.hadm_id
)
-- Final aggregation
SELECT
    CASE
        WHEN hhs.los_days BETWEEN 1 AND 4 THEN '1-4 days'
        WHEN hhs.los_days BETWEEN 5 AND 7 THEN '5-7 days'
        ELSE 'Other' -- Should not be reached due to initial LOS filter
    END AS los_group,
    COUNT(DISTINCT hhs.subject_id) AS patient_count,
    COUNT(DISTINCT hhs.hadm_id) AS admission_count,
    -- Calculate mean procedures per admission, handling cases with 0 procedures
    AVG(COALESCE(rcp.num_radiography_ct_procedures, 0)) AS mean_radiography_ct_procedures_per_admission
FROM
    HHS_Admissions hhs
LEFT JOIN -- Use LEFT JOIN to include admissions that had 0 radiography/CT procedures
    RadiographyCT_Procedures rcp
    ON hhs.hadm_id = rcp.hadm_id
GROUP BY
    los_group
ORDER BY
    los_group;