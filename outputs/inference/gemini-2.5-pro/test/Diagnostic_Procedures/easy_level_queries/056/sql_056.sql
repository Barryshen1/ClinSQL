WITH patient_cohort AS (
    SELECT
        p.subject_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 43 AND 53
),

-- CTE to count the number of distinct mechanical circulatory support procedures for each patient in the cohort
procedures_per_patient AS (
    SELECT
        pc.subject_id,
        -- Count distinct ICD codes that represent mechanical circulatory support.
        -- This will correctly be 0 for patients in the cohort who had no such procedures, thanks to the LEFT JOIN.
        COUNT(DISTINCT proc.icd_code) AS num_distinct_procedures
    FROM
        patient_cohort AS pc
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
        ON pc.subject_id = proc.subject_id
        -- Filter for ICD codes related to mechanical circulatory support
        AND proc.icd_code IN (
            -- ICD-9-CM codes for MCS
            '37.61', -- Intra-aortic balloon pump
            '39.65', -- Extracorporeal circulation auxiliary to open heart surgery (often used for ECMO)
            '39.66', -- Extracorporeal membrane oxygenation [ECMO]
            '37.62', -- Implantation of heart assist system
            '37.65', -- Implantation of external heart assist system
            '37.66', -- Insertion of implantable heart assist system
            '37.68', -- Insertion of percutaneous external heart assist device

            -- ICD-10-PCS codes for MCS
            '5A15223', -- Extracorporeal Oxygenation, Membrane, Central
            '5A1522F', -- Extracorporeal Oxygenation, Membrane, Peripheral Veno-arterial
            '5A1522G', -- Extracorporeal Oxygenation, Membrane, Peripheral Veno-venous
            '02HA3RZ', -- Insertion of IABP into Aorta, Percutaneous Approach
            '02HA4RZ', -- Insertion of IABP into Aorta, Percutaneous Endoscopic Approach
            '02HA0QZ'  -- Insertion of Short-Term External Heart Assist System into Heart, Open Approach
        )
    GROUP BY
        pc.subject_id
)

-- Final Step: Calculate the 25th percentile of the procedure counts across all patients in the cohort.
SELECT
    APPROX_QUANTILES(num_distinct_procedures, 100)[OFFSET(25)] AS percentile_25th_distinct_mcs_procedures
FROM
    procedures_per_patient;