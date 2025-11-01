WITH cohort AS (
    -- Get first admission for male patients aged 37-47
    SELECT 
        p.subject_id,
        a.hadm_id,
        a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 37 AND 47
        -- Get the first admission (earliest admittime) for each patient
        AND a.admittime = (
            SELECT MIN(a2.admittime)
            FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
            WHERE a2.subject_id = p.subject_id
        )
),
dapt_patients AS (
    -- Identify patients who received both aspirin and a P2Y12 inhibitor
    SELECT 
        c.subject_id,
        c.hadm_id,
        c.hospital_expire_flag
    FROM cohort c
    WHERE EXISTS (
        -- Check for aspirin
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` rx1
        WHERE rx1.subject_id = c.subject_id
            AND rx1.hadm_id = c.hadm_id
            AND LOWER(rx1.drug) LIKE '%aspirin%'
    )
    AND EXISTS (
        -- Check for a P2Y12 inhibitor (clopidogrel, ticagrelor, prasugrel)
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` rx2
        WHERE rx2.subject_id = c.subject_id
            AND rx2.hadm_id = c.hadm_id
            AND (
                LOWER(rx2.drug) LIKE '%clopidogrel%'
                OR LOWER(rx2.drug) LIKE '%ticagrelor%'
                OR LOWER(rx2.drug) LIKE '%prasugrel%'
            )
    )
)
-- Compute the standard deviation of mortality (binary variable)
SELECT 
    STDDEV(hospital_expire_flag) AS mortality_sd
FROM dapt_patients;