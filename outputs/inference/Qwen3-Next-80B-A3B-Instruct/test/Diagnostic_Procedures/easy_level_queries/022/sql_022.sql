WITH pacemaker_icd_procedures AS (
    SELECT DISTINCT
        p.subject_id,
        p.hadm_id,
        p.icd_code,
        p.seq_num
    FROM physionet-data.mimiciv_3_1_hosp.procedures_icd p
    INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_procedures d
        ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
    WHERE LOWER(d.long_title) LIKE '%pacemaker%'
       OR LOWER(d.long_title) LIKE '%icd%'
       OR LOWER(d.long_title) LIKE '%implantable cardioverter defibrillator%'
       OR LOWER(d.long_title) LIKE '%cardiac resynchronization therapy%'
       OR LOWER(d.long_title) LIKE '%device insertion%'
       OR LOWER(d.long_title) LIKE '%device implantation%'
),
qualified_admissions AS (
    SELECT
        p.hadm_id,
        COUNT(*) AS procedure_count
    FROM pacemaker_icd_procedures p
    INNER JOIN physionet-data.mimiciv_3_1_hosp.patients pt
        ON p.subject_id = pt.subject_id
    WHERE pt.gender = 'M'
      AND pt.anchor_age BETWEEN 82 AND 92
    GROUP BY p.hadm_id
)
SELECT MIN(procedure_count) AS min_distinct_procedures_per_hospitalization
FROM qualified_admissions;