SELECT
    MIN(distinct_mcs_procedures) AS min_distinct_mcs_procedures_per_patient
FROM (
    SELECT
        p.subject_id,
        COUNT(DISTINCT pr.icd_code) AS distinct_mcs_procedures
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
        ON p.subject_id = pr.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
        ON pr.icd_code = dp.icd_code AND pr.icd_version = dp.icd_version
    WHERE
        p.gender = 'F' -- Filter for female patients
        AND p.anchor_age BETWEEN 40 AND 50 -- Filter for age range 40-50
        AND (
            LOWER(dp.long_title) LIKE '%ecmo%' -- Extracorporeal Membrane Oxygenation
            OR LOWER(dp.long_title) LIKE '%ventricular assist device%' -- VADs
            OR LOWER(dp.long_title) LIKE '%intra-aortic balloon pump%' -- IABP
            OR LOWER(dp.long_title) LIKE '%mechanical circulatory support%' -- General MCS term
            OR LOWER(dp.long_title) LIKE '%total artificial heart%' -- TAH
        )
    GROUP BY
        p.subject_id
) AS patient_mcs_counts;