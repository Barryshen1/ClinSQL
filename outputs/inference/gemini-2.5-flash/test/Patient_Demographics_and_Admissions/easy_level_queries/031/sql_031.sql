WITH PatientDemographic AS (
    -- CTE 1: Filter patients based on demographic criteria (female, age 38-48)
    SELECT
        p.subject_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 38 AND 48
),
HFAmissions AS (
    -- CTE 2: Identify all admissions for these patients that include a Heart Failure diagnosis
    SELECT
        pd.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag
    FROM
        PatientDemographic pd
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON pd.subject_id = ad.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON ad.hadm_id = di.hadm_id
    WHERE
        -- ICD-9 codes for Heart Failure (e.g., 428.xx)
        (di.icd_version = 9 AND di.icd_code LIKE '428%')
        -- OR ICD-10 codes for Heart Failure (e.g., I50.xx)
        OR (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
    GROUP BY -- Group by hadm_id to ensure that if an admission has multiple HF codes, it's counted once
        pd.subject_id, ad.hadm_id, ad.admittime, ad.dischtime, ad.hospital_expire_flag
),
efh AS (
    -- CTE 3: For each patient, find their first admission with a Heart Failure diagnosis
    SELECT
        subject_id,
        hadm_id AS first_hf_hadm_id,
        admittime AS first_hf_admittime,
        dischtime AS first_hf_dischtime,
        hospital_expire_flag
    FROM
        (
            SELECT
                *,
                ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
            FROM
                HFAmissions
        ) AS RankedHFAmissions -- Alias for the subquery
    WHERE
        rn = 1
        -- Exclude patients who died during their first HF admission, as they cannot be readmitted
        AND hospital_expire_flag = 0
),
r30 AS (
    -- CTE 4: Identify patients with a 30-day readmission after their first eligible HF admission
    SELECT DISTINCT
        efh_cte.subject_id
    FROM
        efh AS efh_cte -- Alias to differentiate from the CTE "efh" itself when referencing
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad_sub
        ON efh_cte.subject_id = ad_sub.subject_id
    WHERE
        -- The subsequent admission must be strictly after the discharge of the first HF admission
        ad_sub.admittime > efh_cte.first_hf_dischtime
        -- Ensure it's not the same admission (though the above condition should handle this)
        AND ad_sub.hadm_id != efh_cte.first_hf_hadm_id
        -- A readmission is considered '30-day' if it occurs within 30 days (inclusive)
        AND DATETIME_DIFF(ad_sub.admittime, efh_cte.first_hf_dischtime, DAY) <= 30
)
-- Final SELECT statement to calculate the readmission rate
SELECT
    -- Total patients eligible for first heart failure admission (denominator)
    COUNT(DISTINCT efh.subject_id) AS total_patients_first_hf_admission,
    -- Number of unique patients from the above group who had at least one 30-day readmission (numerator)
    COUNT(DISTINCT r30.subject_id) AS patients_with_30_day_readmission,
    -- Calculate the 30-day readmission rate as a percentage.
    -- Handle division by zero if no eligible patients are found.
    IF(COUNT(DISTINCT efh.subject_id) > 0,
       COUNT(DISTINCT r30.subject_id) * 100.0 / COUNT(DISTINCT efh.subject_id),
       0.0) AS readmission_rate_percentage
FROM
    efh
LEFT JOIN
    r30 ON efh.subject_id = r30.subject_id;