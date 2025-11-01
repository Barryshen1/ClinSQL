SELECT
    STDDEV(num_distinct_cabg_procedures_types) AS stddev_distinct_cabg_procedures
FROM (
    SELECT
        p.subject_id,
        COUNT(DISTINCT pi.icd_code) AS num_distinct_cabg_procedures_types
    FROM
        `physionet-data.mimiciv_3_1_hosp`.patients p
    JOIN
        `physionet-data.mimiciv_3_1_hosp`.procedures_icd pi
        ON p.subject_id = pi.subject_id
    JOIN
        `physionet-data.mimiciv_3_1_hosp`.d_icd_procedures dip
        ON pi.icd_code = dip.icd_code AND pi.icd_version = dip.icd_version
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 41 AND 51
        AND LOWER(dip.long_title) LIKE '%coronary artery bypass%'
    GROUP BY
        p.subject_id
) AS PatientCABGCounts;