WITH PatientAdmissions AS (
    -- Select subject_id and hadm_id for male patients aged 82-92
    SELECT
        p.subject_id,
        ad.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
        ON p.subject_id = ad.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 82 AND 92
),
PacemakerICDProcedures AS (
    -- Identify all ICD codes related to pacemaker or ICD implantation/management
    SELECT DISTINCT
        pro.hadm_id,
        pro.icd_code
    FROM
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pro
    JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d_proc
        ON pro.icd_code = d_proc.icd_code AND pro.icd_version = d_proc.icd_version
    WHERE
        -- ICD-9 codes for cardiac pacemaker / defibrillator insertion/revision
        (pro.icd_version = 9 AND pro.icd_code LIKE '37.8%')
        -- OR ICD-10-PCS codes by keyword search in their long titles
        OR (pro.icd_version = 10 AND
            (d_proc.long_title LIKE '%pacemak%' OR
             d_proc.long_title LIKE '%defibrillator%' OR
             d_proc.long_title LIKE '%cardioverter%'))
),
DistinctProceduresPerHospitalization AS (
    -- For each qualifying hospitalization, count the distinct number of identified pacemaker/ICD procedures
    SELECT
        pa.hadm_id,
        COUNT(DISTINCT pp.icd_code) AS num_distinct_procedures
    FROM
        PatientAdmissions AS pa
    INNER JOIN -- Use INNER JOIN to only include hospitalizations that actually have these procedures
        PacemakerICDProcedures AS pp
        ON pa.hadm_id = pp.hadm_id
    GROUP BY
        pa.hadm_id
)
-- Find the minimum of these counts
SELECT
    MIN(num_distinct_procedures) AS min_distinct_pacemaker_icd_procedures_per_hosp
FROM
    DistinctProceduresPerHospitalization;