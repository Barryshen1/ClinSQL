SELECT MIN(procedure_count) AS min_distinct_valve_procedures_per_hospitalization
FROM (
    SELECT COUNT(*) AS procedure_count
    FROM physionet-data.mimiciv_3_1_hosp.patients p
    INNER JOIN physionet-data.mimiciv_3_1_hosp.procedures_icd pi
        ON p.subject_id = pi.subject_id
    INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_procedures dip
        ON pi.icd_code = dip.icd_code AND pi.icd_version = dip.icd_version
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 57 AND 67
        AND (
            LOWER(dip.long_title) LIKE '%valve%repair%'
            OR LOWER(dip.long_title) LIKE '%valve%replacement%'
        )
    GROUP BY pi.hadm_id
) AS per_admission_counts;