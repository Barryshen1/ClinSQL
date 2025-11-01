WITH CohortLOS AS (
    SELECT
        DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS hospital_los_days -- Calculate LOS in days
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON adm.hadm_id = d.hadm_id
    WHERE
        p.gender = 'F' -- Filter for females
        AND p.anchor_age BETWEEN 83 AND 93 -- Filter for age at first admission between 83 and 93
        AND d.seq_num = 1 -- Select only the primary diagnosis
        AND (
            -- ICD-9 codes for Community-Acquired Pneumonia (CAP)
            (d.icd_version = 9 AND d.icd_code IN (
                '481', '4820', '4821', '4822', '4823', '4829', '4830', '4831', '4838',
                '4841', '4842', '4843', '4845', '4846', '4848', '485', '486', '4870'
            ))
            OR
            -- ICD-10 codes for Community-Acquired Pneumonia (CAP)
            (d.icd_version = 10 AND d.icd_code IN (
                'J180', 'J181', 'J188', 'J189'
            ))
        )
        -- Ensure valid admission and discharge times for LOS calculation
        AND adm.admittime IS NOT NULL
        AND adm.dischtime IS NOT NULL
        -- Ensure discharge is not before admission
        AND DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) >= 0
)
-- Calculate the median hospital LOS from the filtered cohort
SELECT
    APPROX_QUANTILES(hospital_los_days, 100)[OFFSET(50)] AS median_hospital_los_days
FROM
    CohortLOS;