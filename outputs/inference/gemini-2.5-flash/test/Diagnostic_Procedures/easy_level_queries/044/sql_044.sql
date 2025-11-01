SELECT
    STDDEV(num_distinct_mcs_procedures) AS stddev_distinct_mcs_procedures_per_patient
FROM (
    SELECT
        pat.subject_id,
        COUNT(DISTINCT proc.icd_code) AS num_distinct_mcs_procedures
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    JOIN
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
        ON pat.subject_id = proc.subject_id
    JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d_proc
        ON proc.icd_code = d_proc.icd_code
        AND proc.icd_version = d_proc.icd_version
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 56 AND 66
        AND (
            LOWER(d_proc.long_title) LIKE '%extracorporeal membrane oxygenation%'
            OR LOWER(d_proc.long_title) LIKE '%iabp%'
            OR LOWER(d_proc.long_title) LIKE '%intra-aortic balloon%'
            OR LOWER(d_proc.long_title) LIKE '%ventricular assist%'
            OR LOWER(d_proc.long_title) LIKE '%heart assist device%'
            OR LOWER(d_proc.long_title) LIKE '%cardiac assist device%'
        )
    GROUP BY
        pat.subject_id
) AS patient_mcs_counts;