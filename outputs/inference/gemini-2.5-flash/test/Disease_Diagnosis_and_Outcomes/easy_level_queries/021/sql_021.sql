WITH FilteredAdmissions AS (
    SELECT
        ad.subject_id,
        ad.hadm_id,
        -- Calculate LOS in days. Ensure dischtime is not null for a valid LOS.
        DATE_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pa
        ON ad.subject_id = pa.subject_id
    WHERE
        pa.gender = 'F'
        -- Calculate age at admission to filter correctly within the desired range
        AND (pa.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - pa.anchor_year)) BETWEEN 58 AND 68
        -- Ensure discharge time is recorded for a complete admission and LOS calculation
        AND ad.dischtime IS NOT NULL
        -- Check for presence of Hemorrhagic stroke diagnosis for the admission
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di_stroke
            WHERE
                di_stroke.subject_id = ad.subject_id
                AND di_stroke.hadm_id = ad.hadm_id
                AND (
                    -- ICD-10 Hemorrhagic stroke codes
                    (di_stroke.icd_version = 10 AND (di_stroke.icd_code LIKE 'I60%' OR di_stroke.icd_code LIKE 'I61%'))
                    -- ICD-9 Hemorrhagic stroke codes
                    OR (di_stroke.icd_version = 9 AND (di_stroke.icd_code LIKE '430%' OR di_stroke.icd_code LIKE '431%'))
                )
        )
        -- Check for presence of COPD exacerbation diagnosis for the admission
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di_copd
            WHERE
                di_copd.subject_id = ad.subject_id
                AND di_copd.hadm_id = ad.hadm_id
                AND (
                    -- ICD-10 COPD exacerbation code (J44.1 is stored as J441 in diagnoses_icd)
                    (di_copd.icd_version = 10 AND di_copd.icd_code = 'J441')
                    -- ICD-9 COPD exacerbation code (491.21 is stored as 49121 in diagnoses_icd)
                    OR (di_copd.icd_version = 9 AND di_copd.icd_code = '49121')
                )
        )
)
SELECT
    -- Calculate the 25th percentile (Q1) of LOS
    PERCENTILE_CONT(0.25) OVER() AS q1_los_days,
    -- Calculate the 75th percentile (Q3) of LOS
    PERCENTILE_CONT(0.75) OVER() AS q3_los_days,
    -- Calculate the Interquartile Range (IQR = Q3 - Q1) of LOS
    (PERCENTILE_CONT(0.75) OVER() - PERCENTILE_CONT(0.25) OVER()) AS iqr_los_days
FROM
    FilteredAdmissions
LIMIT 1; -- We only need one row as the window functions without PARTITION BY apply to the whole set.;