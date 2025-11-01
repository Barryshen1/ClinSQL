WITH dialysis_hadm AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
        ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
    WHERE LOWER(d.long_title) LIKE '%dialysis%'
    UNION DISTINCT
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` p
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` d 
        ON p.itemid = d.itemid
    WHERE LOWER(d.label) LIKE '%dialysis%'
),
patient_admissions AS (
    SELECT 
        a.hadm_id, 
        a.admittime, 
        a.dischtime, 
        p.gender, 
        p.anchor_age, 
        p.anchor_year
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
)
SELECT STDDEV(los_days) AS sd_los
FROM (
    SELECT 
        TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM patient_admissions a
    JOIN dialysis_hadm dh 
        ON a.hadm_id = dh.hadm_id
    WHERE 
        a.gender = 'M'
        AND (a.anchor_age + (EXTRACT(YEAR FROM a.admittime) - a.anchor_year)) BETWEEN 44 AND 54
) AS los_values;