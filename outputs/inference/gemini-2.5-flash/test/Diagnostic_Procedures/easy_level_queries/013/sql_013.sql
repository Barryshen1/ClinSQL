SELECT
    MIN(distinct_procedures_count) AS min_distinct_valve_procedures_per_hospitalization
FROM (
    SELECT
        p.subject_id,
        a.hadm_id,
        COUNT(DISTINCT pi.icd_code) AS distinct_procedures_count
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
        ON a.hadm_id = pi.hadm_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 57 AND 65 -- Patients aged 57-67; anchor_age is capped at 65 for adults >= 65.
        AND (
            (pi.icd_version = 9 AND (
                pi.icd_code LIKE '35.1%' OR -- Valvuloplasty (repair)
                pi.icd_code LIKE '35.2%'    -- Valve replacement
            ))
            OR
            (pi.icd_version = 10 AND (
                pi.icd_code LIKE '02RF%' OR -- Aortic Valve Replacement
                pi.icd_code LIKE '02RG%' OR -- Mitral Valve Replacement
                pi.icd_code LIKE '02RH%' OR -- Pulmonary Valve Replacement
                pi.icd_code LIKE '02RJ%' OR -- Tricuspid Valve Replacement
                pi.icd_code LIKE '02UQ%' OR -- Aortic Valve Repair
                pi.icd_code LIKE '02UG%' OR -- Mitral Valve Repair
                pi.icd_code LIKE '02US%' OR -- Pulmonary Valve Repair
                pi.icd_code LIKE '02UT%'    -- Tricuspid Valve Repair
            ))
        )
    GROUP BY
        p.subject_id,
        a.hadm_id
)
;