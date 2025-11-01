WITH target_hadm AS (
    SELECT a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    WHERE p.gender = 'F'
      AND (EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age)) BETWEEN 84 AND 94
),
echocardiography_procedures AS (
    SELECT hadm_id, icd_code AS procedure_code
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
        ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
    WHERE LOWER(d.long_title) LIKE '%echocardi%'
    UNION ALL
    SELECT hadm_id, itemid AS procedure_code
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` p
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` d 
        ON p.itemid = d.itemid
    WHERE LOWER(d.label) LIKE '%echocardi%'
),
counts_per_hadm AS (
    SELECT th.hadm_id, COUNT(DISTINCT ep.procedure_code) AS num_procedures
    FROM target_hadm th
    LEFT JOIN echocardiography_procedures ep 
        ON th.hadm_id = ep.hadm_id
    GROUP BY th.hadm_id
)
SELECT PERCENTILE_CONT(num_procedures, 0.25) AS percentile_25
FROM counts_per_hadm;