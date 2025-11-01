WITH TargetPatients AS (
    -- Select subject_id and hadm_id for female patients aged 58-68
    SELECT
        p.subject_id,
        adm.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 58 AND 68 -- Filter by age at their first admission
),
DistinctProcedureCounts AS (
    -- Count distinct coronary angiography/PCI procedures for each hospitalization
    SELECT
        tp.subject_id,
        tp.hadm_id,
        COUNT(DISTINCT
            CASE
                WHEN
                    (picd.icd_version = 9 AND (
                        picd.icd_code LIKE '36.0%' -- PCI: Percutaneous transluminal coronary angioplasty, stent, atherectomy
                        OR picd.icd_code = '88.55' -- Angiography: Angiocardiography of coronary arteries
                    ))
                    OR (picd.icd_version = 10 AND (
                        picd.icd_code LIKE '027%' -- PCI: Dilation of Coronary Artery
                        OR picd.icd_code LIKE '02F%' -- PCI: Insertion of device in Coronary Artery (e.g., stent)
                        OR (REGEXP_CONTAINS(dp.long_title, '(?i)coronary artery') AND REGEXP_CONTAINS(dp.long_title, '(?i)(angiography|visualiz|fluoroscopy)')) -- Angiography: Coronary Angiography (ICD-10 by title)
                    ))
                THEN picd.icd_code -- Count this ICD code if it matches criteria
                ELSE NULL -- Do not count if it doesn't match
            END
        ) AS n_distinct_procedures
    FROM
        TargetPatients tp
    LEFT JOIN -- Use LEFT JOIN to include all hospitalizations, even those with no relevant procedures
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` picd
        ON tp.hadm_id = picd.hadm_id
    LEFT JOIN -- LEFT JOIN again to get procedure descriptions, handle cases where picd.icd_code might not have a d_icd_procedures entry
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
        ON picd.icd_code = dp.icd_code AND picd.icd_version = dp.icd_version
    GROUP BY
        tp.subject_id,
        tp.hadm_id
)
-- Calculate the 75th percentile of the distinct procedure counts
SELECT
    PERCENTILE_CONT(n_distinct_procedures, 0.75) OVER() AS percentile_75th_distinct_procedures
FROM
    DistinctProcedureCounts;