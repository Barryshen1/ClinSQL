SELECT
    MAX(distinct_procedure_count) AS max_distinct_mcs_procedures
FROM (
    SELECT
        tp.subject_id,
        COUNT(DISTINCT pi.icd_code) AS distinct_procedure_count
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` tp
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
        ON tp.subject_id = pi.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
        ON pi.icd_code = dip.icd_code
        AND pi.icd_version = dip.icd_version
    WHERE
        tp.gender = 'M'
        AND tp.anchor_age BETWEEN 80 AND 90
        AND (
               LOWER(dip.long_title) LIKE '%heart assist device%'
            OR LOWER(dip.long_title) LIKE '%ventricular assist device%'
            OR LOWER(dip.long_title) LIKE '%intra-aortic balloon pump%'
            OR LOWER(dip.long_title) LIKE '%ecmo%'
            OR LOWER(dip.long_title) LIKE '%extracorporeal membrane oxygenation%'
            OR LOWER(dip.long_title) LIKE '%artificial heart%'
            OR LOWER(dip.long_title) LIKE '%total heart replacement%'
            OR LOWER(dip.long_title) LIKE '%pulsatile assist%'
            OR LOWER(dip.long_title) LIKE '%non-pulsatile assist%'
            OR LOWER(dip.long_title) LIKE '%biventricular assist%'
        )
    GROUP BY
        tp.subject_id
) AS PatientProcedureCounts;