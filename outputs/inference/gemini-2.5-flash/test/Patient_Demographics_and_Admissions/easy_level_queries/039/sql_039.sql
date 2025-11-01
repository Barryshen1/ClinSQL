WITH target_patients AS (
    -- Select subject_ids for men aged 43-53 with any pneumonia diagnosis
    SELECT
        p.subject_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 43 AND 53
        -- Check if the patient has ever had a pneumonia diagnosis in any admission
        AND EXISTS (
            SELECT 1
            FROM
                `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            INNER JOIN
                -- Join with admissions to link diagnoses to a patient's admission
                `physionet-data.mimiciv_3_1_hosp.admissions` adm
                ON di.hadm_id = adm.hadm_id AND di.subject_id = adm.subject_id
            WHERE
                adm.subject_id = p.subject_id -- Link to the patient from the outer query
                AND (
                    -- ICD-10 codes for pneumonia (J10-J18 range)
                    (di.icd_version = 10 AND LEFT(di.icd_code, 3) BETWEEN 'J10' AND 'J18') OR
                    -- ICD-9 codes for pneumonia (480-486 range)
                    (di.icd_version = 9 AND LEFT(di.icd_code, 3) BETWEEN '480' AND '486')
                )
        )
),
first_icu_stays AS (
    -- Get the length of stay for the first ICU admission for each target patient
    SELECT
        ic.subject_id,
        ic.los -- Length of stay in days
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` ic
    INNER JOIN
        target_patients tp
        ON ic.subject_id = tp.subject_id
    -- Qualify to get only the very first ICU stay for each patient
    QUALIFY ROW_NUMBER() OVER (PARTITION BY ic.subject_id ORDER BY ic.intime) = 1
)
-- Calculate the 25th percentile of ICU LOS for the identified first ICU stays
SELECT
    PERCENTILE_CONT(los, 0.25) AS percentile_25_icu_los_days
FROM
    first_icu_stays;