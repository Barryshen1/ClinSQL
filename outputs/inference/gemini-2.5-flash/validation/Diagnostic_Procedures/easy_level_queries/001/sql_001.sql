SELECT
    PERCENTILE_DISC(num_distinct_cardiac_procedures, 0.75) OVER () AS c75_percentile_distinct_cardiac_procedures
FROM
    (
        SELECT
            adm.subject_id,
            adm.hadm_id,
            COUNT(DISTINCT proc.icd_code) AS num_distinct_cardiac_procedures
        FROM
            `physionet-data.mimiciv_3_1_hosp.patients` p
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.admissions` adm
            ON p.subject_id = adm.subject_id
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
            ON adm.subject_id = proc.subject_id AND adm.hadm_id = proc.hadm_id
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd
            ON proc.icd_code = dicd.icd_code AND proc.icd_version = dicd.icd_version
        WHERE
            p.gender = 'M'
            AND p.anchor_age BETWEEN 63 AND 73
            AND (
                LOWER(dicd.long_title) LIKE '%cardiac%'
                OR LOWER(dicd.long_title) LIKE '%heart%'
                OR LOWER(dicd.long_title) LIKE '%coronary%'
                OR LOWER(dicd.long_title) LIKE '%aorta%'
                OR LOWER(dicd.long_title) LIKE '%valve%'
                OR LOWER(dicd.long_title) LIKE '%angioplasty%'
                OR LOWER(dicd.long_title) LIKE '%bypass%'
                OR LOWER(dicd.long_title) LIKE '%catheterization%'
            )
        GROUP BY
            adm.subject_id,
            adm.hadm_id
    )
LIMIT 1;