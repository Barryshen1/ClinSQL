WITH QualifyingPatients AS (
    -- Step 1: Identify patients who are female, aged 77-87, and have a dialysis diagnosis
    SELECT
        p.subject_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 77 AND 87
        AND p.subject_id IN (
            SELECT DISTINCT d.subject_id
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            WHERE
                -- ICD-9 codes for End-Stage Renal Disease (ESRD) or dialysis
                (d.icd_version = 9 AND d.icd_code IN ('5856', 'V560', 'V451'))
                OR
                -- ICD-10 codes for End-Stage Renal Disease (ESRD) or dependence on dialysis
                (d.icd_version = 10 AND d.icd_code IN ('N186', 'Z992'))
        )
),
FirstICULOS AS (
    -- Step 2 & 3: For each qualifying patient, select their first ICU stay and calculate its length of stay in days
    SELECT
        ie.subject_id,
        TIMESTAMP_DIFF(ie.outtime, ie.intime, HOUR) / 24.0 AS los_days
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN
        QualifyingPatients qp
        ON ie.subject_id = qp.subject_id
    QUALIFY ROW_NUMBER() OVER (PARTITION BY ie.subject_id ORDER BY ie.intime) = 1
)
-- Step 4: Calculate the Interquartile Range (IQR) of the first ICU length of stay
SELECT
    PERCENTILE_CONT(los_days, 0.25) OVER() AS q1_los_days,
    PERCENTILE_CONT(los_days, 0.75) OVER() AS q3_los_days,
    (PERCENTILE_CONT(los_days, 0.75) OVER() - PERCENTILE_CONT(los_days, 0.25) OVER()) AS iqr_of_first_icu_los_days
FROM
    FirstICULOS
QUALIFY ROW_NUMBER() OVER(ORDER BY 1) = 1; -- Ensure only one result row is returned;